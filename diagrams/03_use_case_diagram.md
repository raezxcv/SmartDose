# 03. Use Case Diagram — SmartDose

## Description
This Use Case Diagram illustrates the system boundaries, primary actors (**Patient**, **Caregiver**, **System Administrator**, and **Hardware Unit**), and key system interactions within SmartDose.

---

## 📋 Mermaid Code for Draw.io Import

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
