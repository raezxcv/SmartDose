# Master Diagram Document — SmartDose System

This document contains all 9 Mermaid diagrams for the **SmartDose IoT Smart Pill Dispenser** project.  
You can import any of these diagrams directly into **[draw.io](https://app.diagrams.net)** via **Arrange > Insert > Advanced > Mermaid...** (or **Extras > Edit Diagram...**).

---

## Index of Diagrams
1. [01. System Architecture Diagram](#01-system-architecture-diagram)
2. [02. Dispensing Flowchart](#02-dispensing-flowchart)
3. [03. Use Case Diagram](#03-use-case-diagram)
4. [04. Entity Relationship Diagram (ERD)](#04-entity-relationship-diagram-erd)
5. [05. Level 0 Data Flow Diagram (Context Diagram)](#05-level-0-data-flow-diagram-context-diagram)
6. [06. Level 1 Data Flow Diagram](#06-level-1-data-flow-diagram)
7. [07. Agile Methodology Diagram](#07-agile-methodology-diagram)
8. [08. Input-Process-Output (IPO) Model](#08-input-process-output-ipo-model)
9. [09. Mobile App Flowchart](#09-mobile-app-flowchart)

---

## 01. System Architecture Diagram

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

---

## 02. Dispensing Flowchart

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

---

## 03. Use Case Diagram

```mermaid
graph LR
    subgraph Actors ["PRIMARY ACTORS"]
        PATIENT["👤 Patient"]
        CAREGIVER["👩‍⚕️ Caregiver / Family"]
        ADMIN["👨‍💼 System Admin"]
        HARDWARE["🤖 SmartDose Hardware Unit"]
    end

    subgraph System_Boundary ["SMARTDOSE SYSTEM BOUNDARY"]
        direction TB
        
        %% Patient Use Cases
        UC1["UC-1: View Daily Medication Schedule"]
        UC2["UC-2: Receive Audio/Visual Dispense Alarms"]
        UC3["UC-3: Trigger Emergency Manual Dispense"]
        UC4["UC-4: View Live Camera Chute Feed"]
        UC5["UC-5: View Personal Adherence Stats"]

        %% Caregiver Use Cases
        UC6["UC-6: Create & Edit Medication Schedules"]
        UC7["UC-7: Manage Compartment Pill Inventory (1-10)"]
        UC8["UC-8: Receive Missed Dose & Low Stock Alerts"]
        UC9["UC-9: Configure Emergency Contacts & SMS List"]
        UC10["UC-10: Monitor Patient Adherence History"]

        %% Admin Use Cases
        UC11["UC-11: User Account & Role Management"]
        UC12["UC-12: Device Pairing & Token Generation"]
        UC13["UC-13: System Analytics & Diagnostics Monitoring"]

        %% Hardware Use Cases
        UC14["UC-14: Hardware RTC Time Synchronization"]
        UC15["UC-15: Rotary Carousel Stepper Motor Rotation"]
        UC16["UC-16: IR Sensor Pill Drop Verification"]
        UC17["UC-17: Cellular Emergency SMS Dispatch (SIM800L)"]
        UC18["UC-18: MJPEG Video Stream Server Control"]
    end

    %% Patient Connections
    PATIENT --> UC1
    PATIENT --> UC2
    PATIENT --> UC3
    PATIENT --> UC4
    PATIENT --> UC5

    %% Caregiver Connections
    CAREGIVER --> UC6
    CAREGIVER --> UC7
    CAREGIVER --> UC8
    CAREGIVER --> UC9
    CAREGIVER --> UC10
    CAREGIVER --> UC3

    %% Admin Connections
    ADMIN --> UC11
    ADMIN --> UC12
    ADMIN --> UC13

    %% Hardware Connections
    HARDWARE --> UC14
    HARDWARE --> UC15
    HARDWARE --> UC16
    HARDWARE --> UC17
    HARDWARE --> UC18

    %% Include / Extend Relationships
    UC6 .->|<<include>>| UC7
    UC15 .->|<<include>>| UC16
    UC16 .->|<<extend on failure>>| UC17
    UC16 .->|<<extend on failure>>| UC8
```

---

## 04. Entity Relationship Diagram (ERD)

```mermaid
erDiagram
    USERS ||--o| DEVICES : "owns / paired to"
    USERS ||--o{ SCHEDULES : "has scheduled doses"
    USERS ||--o{ COMPARTMENTS : "manages inventory"
    USERS ||--o{ DISPENSING_LOGS : "generates logs"
    USERS ||--o{ CONTACTS : "configures contacts"
    USERS ||--o{ EMERGENCY_REQUESTS : "initiates"
    USERS ||--o{ SMS_QUEUE : "triggers SMS"
    DEVICES ||--o{ DISPENSING_LOGS : "executes dispense"
    DEVICES ||--o| PAIRING_TOKENS : "uses token for pairing"

    USERS {
        string uid PK "Unique User Identifier"
        string email "User Email Address"
        string name "Full Name"
        string role "Role: patient | caregiver | admin"
        string phone "Phone Number"
        string deviceId FK "Assigned Hardware Device ID (e.g. SD-0119)"
        string photoUrl "Profile Image URI / Base64"
        timestamp createdAt "Registration Timestamp"
    }

    DEVICES {
        string deviceId PK "Hardware Serial Number (e.g. SD-0119)"
        string status "Device Status: online | offline"
        string fwVersion "ESP32 Firmware Version"
        timestamp lastHeartbeat "Last Edge Pulse Time"
        boolean emergencyDispense "Emergency Dispense Active Flag"
        timestamp emergencyRequestedAt "Emergency Request Time"
        string emergencyRequestedBy "UID of Requester"
        map pendingDispense "Current Pending Remote Dispense Data"
    }

    COMPARTMENTS {
        string compartmentId PK "Document ID"
        string patientUid FK "Patient User ID"
        int compartmentNumber "Compartment Index (1 to 10)"
        string medicationName "Medication Name"
        string dosage "Dosage Description (e.g. 500mg)"
        int stockCount "Remaining Pill Count"
        int pillCapacity "Maximum Pill Capacity (e.g. 30)"
        timestamp lastRefilled "Last Refill Timestamp"
    }

    SCHEDULES {
        string scheduleId PK "Document ID"
        string patientUid FK "Patient User ID"
        int compartmentNumber "Assigned Compartment (1-10)"
        string medicationName "Medication Name"
        string dosage "Dosage String"
        timestamp scheduledTime "Time of Day / Scheduled Timestamp"
        string frequency "Frequency: Daily | Weekly | As Needed"
        boolean isActive "Schedule Enabled Flag"
        timestamp createdAt "Creation Timestamp"
    }

    DISPENSING_LOGS {
        string logId PK "Document ID"
        string patientUid FK "Patient User ID"
        string deviceId FK "Hardware Device ID"
        int compartmentNumber "Dispensed Compartment (1-10)"
        string medicationName "Medication Name"
        string status "Result Status: taken | missed | emergency"
        timestamp timestamp "Dispense Event Timestamp"
        timestamp createdAt "Record Creation Timestamp"
    }

    CONTACTS {
        string contactId PK "Document ID"
        string patientUid FK "Patient User ID"
        string name "Contact Name"
        string phone "Cellular Phone Number (+63...)"
        string relationship "Relationship: Family | Doctor | Caregiver"
        boolean isPrimary "Primary Notification Contact Flag"
    }

    EMERGENCY_REQUESTS {
        string requestId PK "Document ID"
        string patientUid FK "Patient User ID"
        string initiatedBy "Initiator: patient | caregiver"
        string status "Request Status: pending | executed | cancelled"
        timestamp requestedAt "Request Timestamp"
    }

    SMS_QUEUE {
        string queueId PK "Document ID"
        string patientUid FK "Patient User ID"
        string to "Recipient Phone Number"
        string contactName "Recipient Name"
        string message "SMS Payload Text"
        string status "Queue Status: pending | sent | failed"
        string triggeredBy "Trigger Reason: emergency | missed_dose"
        timestamp createdAt "Queue Timestamp"
    }

    PAIRING_TOKENS {
        string tokenId PK "Document ID"
        string deviceId FK "Target Device ID"
        string token "6-Digit Pairing Code"
        timestamp expiresAt "Token Expiration Time"
        boolean isUsed "Token Redemption Status"
    }
```

---

## 05. Level 0 Data Flow Diagram (Context Diagram)

```mermaid
graph TD
    subgraph External_Entities ["EXTERNAL ENTITIES"]
        PATIENT_CAREGIVER["👤/👩‍⚕️ Patient & Caregiver<br/>(Flutter App User)"]
        ADMIN["👨‍💼 System Administrator<br/>(React Web Console User)"]
        EMERGENCY_CONTACTS["📱 Emergency Contacts<br/>(Cellular Mobile Phone Users)"]
        FIREBASE_CLOUD["☁️ Firebase Cloud Infrastructure<br/>(Auth, Firestore, FCM, Storage)"]
    end

    subgraph System_Process ["CENTRAL PROCESS 0"]
        P0(("0.0<br/>SMARTDOSE IoT SYSTEM<br/>(ESP32 MCU + RPi Edge + Cloud Platform)"))
    end

    %% Data Flows to/from Patient & Caregiver
    PATIENT_CAREGIVER -->|Schedule Config, Refill Data, Remote Dispense, Emergency Trigger| P0
    P0 -->|FCM Notifications, Live MJPEG Video Stream, Adherence Logs, Low-Stock Alerts| PATIENT_CAREGIVER

    %% Data Flows to/from Admin
    ADMIN -->|Admin Auth Credentials, User Management, Device Pairing Commands| P0
    P0 -->|System Diagnostics, Telemetry Heartbeats, Global Analytics & Audit Logs| ADMIN

    %% Data Flows to Emergency Contacts
    P0 -->|Cellular GSM SMS Emergency Alerts (SIM800L)| EMERGENCY_CONTACTS

    %% Data Flows to/from Firebase Cloud
    P0 <-->|Real-time Database Sync, Auth Verification, Push Notifications & Storage Uploads| FIREBASE_CLOUD
```

---

## 06. Level 1 Data Flow Diagram

```mermaid
graph TB
    subgraph External_Entities ["EXTERNAL ENTITIES"]
        PATIENT["👤 Patient / Caregiver"]
        ADMIN["👨‍💼 System Admin"]
        CONTACTS["📱 Emergency Contacts"]
    end

    subgraph Data_Stores ["DATA STORES (Firestore)"]
        D1[("D1: Users & Devices Store")]
        D2[("D2: Schedules & Compartment Inventory")]
        D3[("D3: Dispensing Logs & Audit Trail")]
        D4[("D4: Emergency Contacts & SMS Queue")]
    end

    subgraph Processes ["SUB-PROCESSES"]
        P1(("1.0<br/>User Auth & Device Pairing"))
        P2(("2.0<br/>Schedule & Inventory Mgmt"))
        P3(("3.0<br/>RTC & Carousel Stepper Control"))
        P4(("4.0<br/>IR Sensor Verification"))
        P5(("5.0<br/>Alerting & GSM/FCM Gateway"))
        P6(("6.0<br/>Live Camera Streaming"))
    end

    %% Process 1.0 Flows
    PATIENT -->|Login / Pair Request| P1
    ADMIN -->|Pairing Token / Role Config| P1
    P1 <-->|Read / Write Profile & Device ID| D1
    P1 -->|Auth Token & Session Status| PATIENT

    %% Process 2.0 Flows
    PATIENT -->|Set Schedule & Refill Compartments| P2
    P2 <-->|Read / Write Schedules & Stock| D2
    P2 -->|Schedule Summary & Low-Stock Warning| PATIENT

    %% Process 3.0 Flows
    D2 -->|Fetch Active Schedules| P3
    P3 -->|Compare Time (DS3231 RTC)| P3
    P3 -->|Step Signals (DRV8825 + 28BYJ-48)| P4

    %% Process 4.0 Flows
    P4 -->|IR Sensor Drop Signal (GPIO13)| P4
    P4 -->|Write Log (taken / missed)| D3
    P4 -->|Decrement Stock Count| D2
    P4 -->|Dispense Result / Status| P5

    %% Process 5.0 Flows
    D4 -->|Fetch Emergency Phone Numbers| P5
    P5 -->|Enqueue SMS Record| D4
    P5 -->|Send AT Commands to SIM800L| CONTACTS
    P5 -->|FCM Push Notification| PATIENT

    %% Process 6.0 Flows
    PATIENT -->|Request Video Feed| P6
    P6 -->|MJPEG Live Video Stream| PATIENT
```

---

## 07. Agile Methodology Diagram

```mermaid
flowchart TD
    subgraph Phase1 ["PHASE 1: REQUIREMENTS & SPECIFICATION"]
        P1_1["Stakeholder Needs Analysis<br/>(Patients & Caregivers)"]
        P1_2["Define Hardware & IoT Architecture<br/>(ISO/IEC 30141:2024 IoT Standard)"]
        P1_3["Establish Quality Criteria<br/>(ISO/IEC 25010 Software Quality)"]
    end

    subgraph Phase2 ["PHASE 2: SYSTEM DESIGN & SCHEMATICS"]
        P2_1["Hardware Circuit Design<br/>(ESP32, DRV8825, DS3231, IR Sensor, SIM800L)"]
        P2_2["3D CAD Modeling<br/>(10-Compartment Rotary Carousel Chute)"]
        P2_3["Cloud & Database Modeling<br/>(Cloud Firestore Schema & Security Rules)"]
        P2_4["UI/UX Design Mockups<br/>(Flutter App & React Web Console)"]
    end

    subgraph Phase3 ["PHASE 3: ITERATIVE DEVELOPMENT SPRINTS"]
        direction TB
        S1["Sprint 1: Embedded Firmware & Hardware<br/>ESP32 Stepper Motor, IR Beam Break, RTC Sync & GSM AT Commands"]
        S2["Sprint 2: Cloud Infrastructure & Synchronization<br/>Firebase Auth, Firestore Streams & FCM Push Notifications"]
        S3["Sprint 3: Client Applications & Streaming<br/>Flutter Mobile App, Riverpod State & RPi Camera MJPEG Feed"]
    end

    subgraph Phase4 ["PHASE 4: INTEGRATION & TESTING"]
        P4_1["Hardware-in-the-Loop (HIL) Testing"]
        P4_2["Pill Drop Verification Accuracy & Retry Testing"]
        P4_3["Cellular SIM800L Fallback & FCM Latency Testing"]
    end

    subgraph Phase5 ["PHASE 5: DEPLOYMENT & EVALUATION"]
        P5_1["Field Deployment in Poblacion, Candaba, Pampanga"]
        P5_2["Alpha Testing by IT Experts<br/>(ISO/IEC 25010 Quality Evaluation)"]
        P5_3["Beta Testing by Selected Households<br/>(4-Point Likert Scale & Weighted Mean)"]
    end

    subgraph Phase6 ["PHASE 6: REVIEW & REFINEMENT"]
        P6_1["Analyze Evaluation Feedback & Survey Scores"]
        P6_2["Firmware Optimization & Bug Fixing"]
        P6_3["Final Capstone Project Documentation"]
    end

    Phase1 --> Phase2
    Phase2 --> Phase3
    S1 --> S2 --> S3
    Phase3 --> Phase4
    Phase4 -->|Issues Found / Refine| Phase3
    Phase4 -->|Passed All Tests| Phase5
    Phase5 --> Phase6
    Phase6 -->|Iterative Enhancements| Phase3
```

---

## 08. Input-Process-Output (IPO) Model

```mermaid
graph LR
    subgraph Inputs ["INPUT STAGE"]
        direction TB
        subgraph Input_Sensors ["Sensors & Hardware Signals"]
            I1["DS3231 RTC Clock Timestamp"]
            I2["IR Beam-Break Sensor Signal (GPIO13)"]
            I3["Physical Emergency Push Button"]
            I4["Raspberry Pi Camera Module Video Lens"]
        end

        subgraph Input_User ["User & App Inputs"]
            I5["Medication Schedule (Time, Dosage, Freq)"]
            I6["Compartment Stock Count & Refill Level"]
            I7["Remote Dispense Command from App"]
            I8["Emergency Alert Contacts & Phone Numbers"]
        end
    end

    subgraph Process ["PROCESS STAGE"]
        direction TB
        P1["1. Time Comparison Algorithm<br/>(DS3231 RTC vs Scheduled Time)"]
        P2["2. Stepper Motor Position Logic<br/>(DRV8825 ~204 steps per compartment)"]
        P3["3. IR Pill Passage Detection & Retry Logic<br/>(Up to 3 retries with carousel agitation)"]
        P4["4. Real-Time Cloud Synchronization<br/>(Cloud Firestore Database Updates)"]
        P5["5. Multi-Channel Alert Router<br/>(FCM Push & SIM800L Cellular SMS Engine)"]
        P6["6. MJPEG Video Encoding & Stream Gateway"]
    end

    subgraph Outputs ["OUTPUT STAGE"]
        direction TB
        subgraph Output_Physical ["Physical & Local Hardware Outputs"]
            O1["Rotated Compartment & Dispensed Pill"]
            O2["Audio Alarm Tone (Piezo Buzzer GPIO4)"]
            O3["Status LED Indicator (GPIO2)"]
            O4["16x2 I2C LCD Status Display"]
        end

        subgraph Output_Digital ["Digital & Client Outputs"]
            O5["Cloud Log Entry (status: taken / missed)"]
            O6["Updated Stock Count in Firestore"]
            O7["FCM Push Notifications to Smartphone"]
            O8["Emergency Cellular SMS to Contacts (SIM800L)"]
            O9["Live MJPEG Camera Feed on Mobile App"]
        end
    end

    Input_Sensors --> Process
    Input_User --> Process
    Process --> Output_Physical
    Process --> Output_Digital
```

---

## 09. Mobile App Flowchart

```mermaid
flowchart TD
    START([App Launch]) --> AUTH_CHECK{Authenticated &<br/>Device Paired?}
    
    AUTH_CHECK -->|First Launch| ONBOARDING[Onboarding Screen<br/>3 Splash Slides & Introduction]
    ONBOARDING --> LOGIN[Login Screen<br/>Email/Password, Google & Facebook Sign-In]
    
    AUTH_CHECK -->|Not Logged In| LOGIN
    
    LOGIN -->|New User| REGISTER[Register Screen<br/>Create Account & Select Role: Patient / Caregiver]
    LOGIN -->|Forgot Password| FORGOT_PWD[Forgot Password Screen<br/>Email Password Reset Link]
    FORGOT_PWD --> LOGIN
    REGISTER --> PAIR_DEVICE{Paired Device<br/>Assigned?}

    LOGIN -->|Success| PAIR_DEVICE
    
    PAIR_DEVICE -->|No Device Paired| PAIRING_SCREEN[Device Pairing Screen<br/>Enter 6-Digit Pairing Code / Scan QR Code]
    PAIRING_SCREEN -->|Valid Code e.g. SD-0119| DASHBOARD
    
    PAIR_DEVICE -->|Device Paired| DASHBOARD[Main Patient / Caregiver Dashboard Shell<br/>Bottom Navigation Bar]

    %% Bottom Navigation Tabs
    DASHBOARD --> TAB1[1. Home Tab]
    DASHBOARD --> TAB2[2. Medications Tab]
    DASHBOARD --> TAB3[3. History Log Tab]
    DASHBOARD --> TAB4[4. Alerts & Notifications Tab]
    DASHBOARD --> TAB5[5. Profile & Settings Tab]

    %% Tab 1: Home Tab Actions
    TAB1 --> HOME_NEXT[Next Medication Countdown Card]
    HOME_NEXT --> DISPENSE_NOW[Click 'Dispense Now'<br/>Send Signal to Firestore 'devices']
    TAB1 --> HOME_RING[Daily Adherence Ring & Progress Breakdown]
    TAB1 --> HOME_QUICK[Quick Actions]
    
    HOME_QUICK --> QA_CAM[Live Camera Stream<br/>MJPEG Video Feed]
    HOME_QUICK --> QA_CONTACTS[Emergency Contacts<br/>Call & Manage SMS List]
    HOME_QUICK --> QA_INV[Compartment Inventory<br/>10-Compartment Pill Levels]
    HOME_QUICK --> QA_DEVICE[Device Connected Screen<br/>Wi-Fi Status, Battery & SD-0119 Firmware]
    
    TAB1 --> HOME_EMERGENCY[Emergency Dispense Button]
    HOME_EMERGENCY --> TRIG_EMERGENCY[Dispatch Emergency Signal to Device &<br/>Enqueue SMS to Contacts via SIM800L]

    %% Tab 2: Medications Tab Actions
    TAB2 --> MED_LIST[View Active Medication Schedules]
    TAB2 --> ADD_MED[Click 'Add Medication']
    ADD_MED --> MED_FORM[Select Compartment 1-10, Name,<br/>Dosage, Time & Frequency]
    MED_FORM --> SAVE_SCHED[Save to Firestore 'schedules']
    MED_LIST --> REFILL_MED[Refill Compartment Pills]

    %% Tab 3: History Log Tab
    TAB3 --> LOG_FILTER[Filter Logs: All | Taken | Missed | Emergency]
    LOG_FILTER --> LOG_DETAILS[View Event Timestamps & Compartment Audit]

    %% Tab 4: Alerts Tab
    TAB4 --> ALERTS_LIST[View FCM Notifications & Low-Stock Alerts]
    ALERTS_LIST --> MARK_READ[Mark as Read / Clear All]

    %% Tab 5: Profile Tab
    TAB5 --> EDIT_PROFILE[Edit User Profile & Avatar Gradient]
    TAB5 --> VIEW_DEVICE[View Paired Device Details SD-0119]
    TAB5 --> TOGGLE_THEME[Toggle Dark / Light Theme Mode]
    TAB5 --> SIGNOUT[Sign Out]
    SIGNOUT --> LOGIN
```
