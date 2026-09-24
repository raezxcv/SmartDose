# SmartDose Capstone Diagrams (Mermaid Format for Draw.io)

This directory contains complete, production-grade Mermaid diagrams for the **SmartDose IoT Smart Pill Dispenser** capstone project. These diagrams align with the system implementation and research paper specification (`Sept-22-SmartDose.docx`).

---

## 🎨 How to Import Mermaid Diagrams into Draw.io

1. Open **[draw.io](https://app.diagrams.net)** (or your desktop draw.io app).
2. Create a new diagram or open an existing canvas.
3. In the top toolbar, click **Arrange > Insert > Advanced > Mermaid...**  
   *(Alternative: Click **Extras > Edit Diagram...** and set format to **Mermaid**).*
4. Open any of the `.md` files in this directory (or `smartdose_all_diagrams.md`), copy the Mermaid code block (excluding the triple backticks ```), and paste it into the draw.io dialog box.
5. Click **Insert** (or **Apply**).
6. draw.io will instantly generate vector-rendered, fully editable diagram shapes!

---

## 📁 File Structure

| File Name | Diagram Type | Description |
|---|---|---|
| `smartdose_all_diagrams.md` | **All Diagrams (Master File)** | Single file containing all 8 diagrams for easy copy-pasting |
| `01_system_architecture.md` | **System Architecture** | Hardware (ESP32, RPi, Sensors), Cloud (Firebase), App (Flutter) & Web Console |
| `02_dispensing_flowchart.md` | **Dispensing Flowchart** | Detailed execution logic from RTC trigger to IR sensor check and GSM fallback |
| `03_use_case_diagram.md` | **Use Case Diagram** | Interactions between Patient, Caregiver, Admin, Hardware, and System |
| `04_entity_relationship_diagram.md` | **Entity Relationship (ERD)** | Firestore Database Schema (`users`, `devices`, `schedules`, `logs`, `compartments`, `sms_queue`) |
| `05_level0_dfd_context.md` | **Level 0 DFD (Context)** | High-level data flows between external entities and SmartDose system |
| `06_level1_dfd.md` | **Level 1 DFD** | Sub-processes breakdown (Auth, Schedule, Dispense, Verification, Alerting, Video) |
| `07_agile_methodology.md` | **Agile Methodology** | 6-Phase development lifecycle with ISO/IEC standards & evaluation |
| `08_ipo_model.md` | **IPO Model** | Input-Process-Output breakdown of hardware and software components |
| `09_mobile_app_flowchart.md` | **Mobile App Flowchart** | Flutter mobile app user navigation, auth states, tabs & feature flows |

---

## 🛠️ System Specifications Reference
- **MCU:** ESP32-WROOM-32 (Stepper control via DRV8825, IR Sensor GPIO13, Buzzer GPIO4, Status LED GPIO2)
- **Edge Host:** Raspberry Pi 4 / Zero 2W (UART 115200, Camera Stream, Firebase Gateway)
- **Carousel:** 10 Compartments (~204 steps per compartment using 28BYJ-48 stepper)
- **Cellular Backup:** SIM800L GSM Module (AT commands for emergency SMS dispatch)
- **Cloud Backend:** Firebase (Auth, Firestore `smart-pill-dispenser-baa02`, Cloud Storage, FCM)
- **Mobile Client:** Flutter (Android-first, Riverpod, Firebase)
- **Admin Client:** React + Vite
