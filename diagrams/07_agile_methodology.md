# 07. Agile Methodology Diagram — SmartDose

## Description
This diagram maps out the 6-Phase Agile Development Lifecycle utilized in creating the SmartDose system, aligned with **ISO/IEC 30141:2024** (IoT Reference Architecture) and **ISO/IEC 25010** (System and Software Quality Model) evaluation standards.

---

## 📋 Mermaid Code for Draw.io Import

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
