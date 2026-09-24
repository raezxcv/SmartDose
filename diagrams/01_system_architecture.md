# 01. System Architecture Diagram — SmartDose

## Description
This diagram illustrates the multi-tier architecture of the SmartDose system, encompassing the **Hardware/Edge Tier** (ESP32 MCU, Raspberry Pi, Sensors, Motors, GSM), **Cloud Tier** (Firebase Auth, Cloud Firestore, FCM, Cloud Storage), and **Application Tier** (Flutter Mobile App & React Admin Web Console).

---

## 📋 Mermaid Code for Draw.io Import

```mermaid
graph TB
    subgraph Hardware_Edge ["HARDWARE & EDGE TIER (IoT Unit)"]
        direction TB
        subgraph Sensors_Actuators ["Sensors & Actuators Layer"]
            STEPPER["Stepper Motor (28BYJ-48 + DRV8825 Driver)<br/>10-Compartment Rotary Carousel"]
            IR_SENSOR["IR Beam-Break Sensor (GPIO13)<br/>Pill Drop Verification"]
            RTC["DS3231 Precision RTC Module<br/>Hardware Timekeeping"]
            BUZZER["Piezo Buzzer (GPIO4)<br/>Audio Alarm"]
            LED["Status LED (GPIO2)<br/>Visual Status Indicator"]
            LCD["16x2 I2C LCD Display<br/>Local Patient Status"]
            GSM["SIM800L GSM Module<br/>Cellular SMS Emergency Fallback"]
        end

        subgraph Edge_MCU ["Controller Layer"]
            ESP32["ESP32 Microcontroller<br/>Main Motor Control & Sensor Reading"]
            RPI["Raspberry Pi 4 / Zero 2W<br/>Edge Gateway & Camera Server"]
            CAM["Raspberry Pi Camera Module v2/v3<br/>MJPEG Video Stream Provider"]
        end
    end

    subgraph Cloud_Infrastructure ["CLOUD INFRASTRUCTURE TIER (Firebase)"]
        direction TB
        FBAUTH["Firebase Authentication<br/>Identity & Access Control"]
        FIRESTORE[("Cloud Firestore DB<br/>Collections: users, devices, schedules,<br/>dispensingLogs, compartments, contacts, sms_queue")]
        FCM["Firebase Cloud Messaging (FCM)<br/>Push Notification Gateway"]
        FBSTORAGE["Firebase Cloud Storage<br/>Audit Media & Verification Snapshots"]
    end

    subgraph Client_Applications ["APPLICATION & CLIENT TIER"]
        direction TB
        FLUTTER_APP["SmartDose Android App (Flutter + Riverpod)<br/>Patient / Caregiver Interface"]
        WEB_ADMIN["SmartDose Admin Console (React + Vite)<br/>System Administration & Monitoring"]
        CELLULAR_SMS["Emergency Contact Mobile Handsets<br/>Direct Cellular SMS Alerts"]
    end

    %% Internal Hardware Connectivity
    ESP32 -->|Step/Dir Control| STEPPER
    ESP32 -->|GPIO Reading| IR_SENSOR
    ESP32 -->|I2C Clock Sync| RTC
    ESP32 -->|GPIO Signal| BUZZER
    ESP32 -->|GPIO Signal| LED
    ESP32 -->|I2C Display| LCD
    ESP32 -->|UART AT Commands| GSM
    RPI -->|CSI Ribbon Cable| CAM
    ESP32 <-->|UART 115200 Baud| RPI

    %% Cloud Integration
    RPI <-->|HTTPS / WebSockets| FIRESTORE
    RPI -->|HTTPS Stream & Media Upload| FBSTORAGE
    FLUTTER_APP <-->|Firebase SDK / Realtime Sync| FIRESTORE
    FLUTTER_APP <-->|Auth Tokens| FBAUTH
    WEB_ADMIN <-->|Firebase SDK / Realtime Sync| FIRESTORE
    WEB_ADMIN <-->|Admin Auth| FBAUTH

    %% Alerts & Streaming
    FCM -->|Push Notification Signals| FLUTTER_APP
    FIRESTORE -->|Trigger Notification| FCM
    GSM -.->|Cellular Network SMS| CELLULAR_SMS
    CAM -.->|MJPEG Live Stream Stream| FLUTTER_APP
```
