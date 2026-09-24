# 02. Dispensing Flowchart — SmartDose

## Description
This flowchart depicts the end-to-end execution flow of the medication dispensing process in the SmartDose system, including RTC schedule matching, stepper motor control, IR beam-break pill verification, retry mechanism, and multi-channel failure fallback (FCM & SIM800L GSM).

---

## 📋 Mermaid Code for Draw.io Import

```mermaid
flowchart TD
    START([Start / System Standby]) --> INIT[Initialize ESP32, DS3231 RTC, IR Sensor & Firestore Stream]
    INIT --> CHECK_TRIGGER{Dispensing Triggered?}
    
    CHECK_TRIGGER -->|No| WAIT[Wait 1s / Poll DS3231 RTC & Firestore Flags]
    WAIT --> CHECK_TRIGGER
    
    CHECK_TRIGGER -->|Scheduled Time Matched OR<br/>App Manual Dispense Signal OR<br/>Physical Emergency Button| START_DISPENSE[Retrieve Medication & Compartment Info<br/>Target: Compartment 1 to 10]
    
    START_DISPENSE --> ALARM_ON[Activate Piezo Buzzer GPIO4 Audio Alarm<br/>Turn ON Status LED GPIO2 & Update LCD Display]
    ALARM_ON --> CALC_STEPS[Calculate Stepper Motor Steps<br/>~204 steps per compartment for 28BYJ-48]
    CALC_STEPS --> ROTATE_MOTOR[Energize DRV8825 Driver<br/>Rotate Carousel to Target Compartment]
    
    ROTATE_MOTOR --> SENSING[Enable IR Beam-Break Sensor GPIO13<br/>Monitor Pill Chute Passage]
    SENSING --> PILL_DETECTED{Pill Dropped &<br/>IR Beam Interrupted?}
    
    PILL_DETECTED -->|Yes| SUCCESS_LOG[Pill Dispense Verified]
    SUCCESS_LOG --> SOUND_CHIME[Play Success Chime on Buzzer GPIO4<br/>Update LCD: 'TAKE MEDICATION']
    SOUND_CHIME --> DB_LOG_SUCCESS[Write Log to Firestore 'dispensingLogs'<br/>status: 'taken', timestamp: NOW]
    DB_LOG_SUCCESS --> DECREMENT_STOCK[Decrement stockCount in 'compartments'<br/>Clear pendingDispense flag in 'devices']
    DECREMENT_STOCK --> END_SUCCESS([End - Dispense Complete])

    PILL_DETECTED -->|No| RETRY_CHECK{Retry Count < 3?}
    RETRY_CHECK -->|Yes| AGITATE[Agitate Carousel Motor ±10 Steps<br/>Increment Retry Count]
    AGITATE --> SENSING

    RETRY_CHECK -->|No| FAIL_ALERT[Dispense Failure / Empty Compartment Detected]
    FAIL_ALERT --> SOUND_FAIL[Sound Warning Tone on Buzzer<br/>Update LCD: 'DISPENSE FAILED']
    SOUND_FAIL --> DB_LOG_FAIL[Write Log to Firestore 'dispensingLogs'<br/>status: 'missed', timestamp: NOW]
    DB_LOG_FAIL --> SEND_FCM[Send FCM Push Notification to Caregiver & Patient App]
    SEND_FCM --> QUEUE_SMS[Enqueue SMS Record into Firestore 'sms_queue']
    QUEUE_SMS --> GSM_SEND[ESP32 / RPi Sends AT Commands to SIM800L GSM<br/>Dispatch Emergency SMS to Contacts]
    GSM_SEND --> END_FAIL([End - Alert Dispatched])
```
