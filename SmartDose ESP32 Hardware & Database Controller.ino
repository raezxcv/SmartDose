#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <ESP32Servo.h> // Standard ESP32 Servo library

// Provide the token generation and DNS processing utility
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// --- Wi-Fi Credentials ---
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// --- Firebase Credentials (SmartDose Firebase Instance) ---
#define API_KEY "AIzaSyDfPRQ-uUKxFcVa5M1hkkKYNWZ9e4Ef4v4"
#define DATABASE_URL "https://smart-pill-dispenser-baa02-default-rtdb.firebaseio.com/"

// --- Hardware Pin Mappings ---
const int SERVO_1_PIN          = 4;  // Servo Motor Signal (PWM)
const int IR_SENSOR_PIN        = 13; // IR Beam-Break Pill Drop Sensor (Input Pullup, Active LOW)
const int BUZZER_PIN           = 12; // Piezo Alarm & Chime (Active HIGH)
const int EMERGENCY_BUTTON_PIN = 14; // Physical SOS Emergency Button (Input Pullup, Active LOW)
const int STATUS_LED_PIN       = 2;  // Indicator LED (Active HIGH)

// Global Hardware & Firebase Objects
Servo servo1;
FirebaseData fbdo;
FirebaseData streamData;
FirebaseAuth auth;
FirebaseConfig config;

// State Variables
int currentAngle = 0;
unsigned long lastHeartbeatTime = 0;
bool isDispensing = false;
int lastButtonState = HIGH;
unsigned long lastDebounceTime = 0;

// Forward Declarations
bool executeDispenseCycle(int slot, int targetAngle);
void triggerAudioVisualChime();
void sendEmergencyAlert();

// ── Stream Callback for Commands from App ──
void streamCallback(StreamData data) {
  Serial.printf("[Firebase Stream] Path: %s | Type: %s\n", data.streamPath().c_str(), data.dataType().c_str());

  // 1. Direct Angle Command (/hardware/servo1)
  if (data.streamPath() == "/" || data.streamPath() == "/servo1") {
    if (data.dataType() == "int") {
      int targetAngle = constrain(data.intData(), 0, 180);
      if (targetAngle != currentAngle && !isDispensing) {
        currentAngle = targetAngle;
        servo1.write(currentAngle);
        Serial.printf("[Hardware] Servo moved to target angle: %d°\n", currentAngle);
        Firebase.RTDB.setInt(&fbdo, "/hardware/servo1_status", currentAngle);
      }
    }
  }

  // 2. Dispense Trigger Command (/hardware/dispense_trigger)
  if (data.streamPath() == "/dispense_trigger" || data.streamPath() == "/") {
    if (data.dataType() == "json" || data.dataType() == "int") {
      int slot = (data.dataType() == "int") ? data.intData() : 1;
      if (slot >= 1 && slot <= 10 && !isDispensing) {
        int calculatedAngle = (slot - 1) * 18; // 18° increment per 10-slot carousel
        executeDispenseCycle(slot, calculatedAngle);
      }
    }
  }
}

void streamTimeoutCallback(bool timeout) {
  if (timeout) {
    Serial.println("[Firebase] Stream timed out, attempting reconnection...");
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n=======================================================");
  Serial.println("  SmartDose ESP32 Hardware & Database Controller v2.5");
  Serial.println("=======================================================");

  // 1. Initialize Pins
  pinMode(IR_SENSOR_PIN, INPUT_PULLUP);
  pinMode(EMERGENCY_BUTTON_PIN, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(STATUS_LED_PIN, OUTPUT);

  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(STATUS_LED_PIN, HIGH);

  // 2. Initialize ESP32 Servo with Timer Allocation
  ESP32PWM::allocateTimer(0);
  servo1.setPeriodHertz(50); // 50Hz standard servo
  servo1.attach(SERVO_1_PIN, 500, 2400); // 500us - 2400us range
  servo1.write(0);
  currentAngle = 0;
  Serial.println("[Hardware] Servo attached to GPIO 4 (0°).");

  // 3. Connect to Wi-Fi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[Wi-Fi] Connecting to: ");
  Serial.println(WIFI_SSID);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[Wi-Fi] Connected!");
    Serial.print("[Wi-Fi] IP Address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n[Wi-Fi] Connection timeout. Operating in fallback mode.");
  }

  // 4. Configure Firebase
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  config.token_status_callback = tokenStatusCallback;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // 5. Start Real-time Database Listener
  if (Firebase.ready()) {
    if (Firebase.RTDB.beginStream(&streamData, "/hardware")) {
      Firebase.RTDB.setStreamCallback(&streamData, streamCallback, streamTimeoutCallback);
      Serial.println("[Firebase] Stream active on path: /hardware");
    } else {
      Serial.printf("[Firebase] Stream init error: %s\n", streamData.errorReason().c_str());
    }
  }
}

void loop() {
  if (Firebase.ready()) {
    // Keep stream listener alive
    if (!Firebase.RTDB.readStream(&streamData)) {
      // Error handles inside streamTimeoutCallback
    }

    // --- 1. Heartbeat Telemetry to `devices` collection (Every 15s) ---
    if (millis() - lastHeartbeatTime > 15000) {
      lastHeartbeatTime = millis();
      
      FirebaseJson statusJson;
      statusJson.add("status", "online");
      statusJson.add("isOnline", true);
      statusJson.add("ipAddress", WiFi.localIP().toString());
      statusJson.add("wifiRSSI", WiFi.RSSI());
      statusJson.add("firmwareVersion", "v2.5.0");
      statusJson.add("lastHeartbeatSec", millis() / 1000);

      Firebase.RTDB.setJSON(&fbdo, "/hardware/status", &statusJson);
    }
  }

  // --- 2. Physical SOS Emergency Button Check ---
  int reading = digitalRead(EMERGENCY_BUTTON_PIN);
  if (reading == LOW && lastButtonState == HIGH && (millis() - lastDebounceTime > 200)) {
    lastDebounceTime = millis();
    Serial.println("[Hardware Alert] PHYSICAL SOS EMERGENCY BUTTON PRESSED!");
    sendEmergencyAlert();
  }
  lastButtonState = reading;

  delay(10);
}

// ── Execute Automated Dispense Cycle ──
bool executeDispenseCycle(int slot, int targetAngle) {
  isDispensing = true;
  Serial.printf("\n[Dispense Cycle] Initiating dispense for Slot C%d at %d°...\n", slot, targetAngle);

  // Audio-visual chime cue
  triggerAudioVisualChime();

  // Rotate Carousel / Servo
  servo1.write(targetAngle);
  currentAngle = targetAngle;
  delay(800); // Allow motor to settle

  // Wait up to 10 seconds for IR Beam Drop Sensor confirmation
  Serial.println("[Hardware] Waiting for IR beam-break pill drop confirmation...");
  unsigned long startTime = millis();
  bool pillDropped = false;

  while (millis() - startTime < 10000) {
    if (digitalRead(IR_SENSOR_PIN) == LOW) { // IR Beam interrupted (Pill drop detected)
      pillDropped = true;
      Serial.println("[Hardware Sensor] SUCCESS! Pill drop confirmed by IR sensor.");
      break;
    }
    delay(10);
  }

  if (!pillDropped) {
    Serial.println("[Hardware Sensor] WARNING: No pill drop detected (Dose Missed).");
  }

  // --- Update Database Records Across Collections ---
  if (Firebase.ready()) {
    // 1. Update dispensingLogs entry
    FirebaseJson logJson;
    logJson.add("slot", slot);
    logJson.add("compartment", "C" + String(slot));
    logJson.add("status", pillDropped ? "taken" : "missed");
    logJson.add("type", pillDropped ? "dispense_success" : "dose_missed");
    logJson.add("timestampSec", millis() / 1000);
    Firebase.RTDB.setJSON(&fbdo, "/hardware/last_dispense_log", &logJson);

    // 2. Decrement stock in /hardware/compartments/comp_X
    String compPath = "/hardware/compartments/comp_" + String(slot);
    if (Firebase.RTDB.getInt(&fbdo, compPath + "/stockCount")) {
      int curStock = fbdo.intData();
      int newStock = max(0, curStock - 1);
      Firebase.RTDB.setInt(&fbdo, compPath + "/stockCount", newStock);
      Serial.printf("[Database] Compartment C%d stock updated to: %d\n", slot, newStock);
    }

    // 3. Clear trigger flag
    Firebase.RTDB.setInt(&fbdo, "/hardware/servo1_status", currentAngle);
    Firebase.RTDB.setNull(&fbdo, "/hardware/dispense_trigger");
  }

  // Return to 0° resting position
  delay(1000);
  servo1.write(0);
  currentAngle = 0;
  isDispensing = false;
  return pillDropped;
}

// ── Audio Visual Chime ──
void triggerAudioVisualChime() {
  for (int i = 0; i < 3; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    digitalWrite(STATUS_LED_PIN, HIGH);
    delay(150);
    digitalWrite(BUZZER_PIN, LOW);
    digitalWrite(STATUS_LED_PIN, LOW);
    delay(100);
  }
}

// ── Send Emergency SOS Alert to Database ──
void sendEmergencyAlert() {
  // Loud alarm buzzer
  for (int i = 0; i < 5; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    digitalWrite(STATUS_LED_PIN, HIGH);
    delay(250);
    digitalWrite(BUZZER_PIN, LOW);
    digitalWrite(STATUS_LED_PIN, LOW);
    delay(150);
  }

  if (Firebase.ready()) {
    FirebaseJson alertJson;
    alertJson.add("type", "emergency_button");
    alertJson.add("severity", "critical");
    alertJson.add("title", "Physical Emergency SOS Button Pressed");
    alertJson.add("message", "Patient pressed physical SOS panic button on dispenser hardware.");
    alertJson.add("status", "pending");
    alertJson.add("triggeredAtSec", millis() / 1000);

    // Write to Realtime Database emergency alerts queue
    Firebase.RTDB.setJSON(&fbdo, "/hardware/emergency_alert", &alertJson);
    Serial.println("[Database] Urgent Emergency SOS document written to /hardware/emergency_alert!");
  }
}
