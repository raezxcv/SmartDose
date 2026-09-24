# 09. Mobile App Flowchart — SmartDose Flutter App

## Description
This flowchart maps out the complete user navigation flow, screens, authentication states, and core feature branches of the **SmartDose Android Mobile Application** (Flutter + Riverpod + Firebase).

---

## 📋 Mermaid Code for Draw.io Import

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
