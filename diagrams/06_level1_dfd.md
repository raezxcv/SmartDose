# 06. Level 1 Data Flow Diagram — SmartDose

## Description
This Level 1 Data Flow Diagram decomposes the SmartDose system into six major functional sub-processes (1.0 to 6.0) and details the flow of data between external entities, processes, and core data stores (D1 to D4).

---

## 📋 Mermaid Code for Draw.io Import

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
