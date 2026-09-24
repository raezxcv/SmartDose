# 05. Level 0 Data Flow Diagram (Context Diagram) — SmartDose

## Description
This Level 0 Context Diagram defines the organizational system boundary of the SmartDose System (Process 0) and all external entities interacting with it (**Patient & Caregiver**, **System Administrator**, **Emergency Contacts**, and **Firebase Cloud Infrastructure**).

---

## 📋 Mermaid Code for Draw.io Import

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
