# 📑 System Handover & Technical Protocol
**Project:** Naim-Topping-B&O Hybrid Master (Living Room)  
**Control Platform:** BeoLiving Intelligence (Gen 3)  
**Host IP:** static IP assigned to **Naim Core** 

**Date:** February 2026

---

### **1. Executive Summary**
This system integrates three distinct generations of audio technology: **Modern Digital** (Naim/Topping), **Network Link Streaming** (B&O), and **Vintage Analog** (Beomaster 8000). The [BeoLiving Intelligence (BLI) Gen 3](https://beoliving.khimo.com) acts as the central "Brain," managing complex IP-to-Infrared translations to provide a unified Bang & Olufsen user experience.

---

### **2. Hybrid Signal Path Architecture**
The system uses a dual-path design to maintain bit-perfect integrity in the main zone while enabling whole-home distribution via the B&O ecosystem.


| Path | Source | Connectivity | Target |
| :--- | :--- | :--- | :--- |
| **Primary Digital** | Naim Uniti Core | BNC $\rightarrow$ AES | Topping D90 DAC |
| **Secondary Stream** | Beosound Core | Optical Out | Topping D90 DAC |
| **Vintage Analog** | Beomaster 8000 | RCA Out | Topping A90 Discrete |
| **Distribution** | Topping D90 | RCA Fixed Out | Beosound Core Line-In |

*   **Logic:** The Living Room [Beosound Core](https://www.bang-olufsen.com) serves a dual role: it is a **Source** for Tidal/Radio (via Optical Out) and a **Broadcaster** for the Naim Core (via Line-In).

---

### **3. Control Protocol & Port Mapping**
Control is centralized via a [Global Caché iTach IP2IR](https://www.globalcache.com) located at a static IP. **Port Mapping is critical:**


| iTach Port | Frequency | Protocol | Hardware Targets |
| :--- | :--- | :--- | :--- |
| **Port 1 & 2** | **38kHz** | NEC/38kHz IR | Topping D90 & A90 Discrete |
| **Port 3** | **455kHz** | B&O/455kHz IR | Beomaster 8000 (Datalink Bridge) |

*   **CRITICAL SETTING:** Port 3 **MUST** be configured as an **"IR Blaster"** in the iTach Web UI to support the 455kHz carrier frequency required by the [BeoLab Terminal](https://beoworld.org) protocol.

---

### **4. Proprietary Software Logic**

#### **A. WAV Metadata Engine (Port 16000)**
The driver utilizes a custom [SSDP discovery](https://khimo.github.io) loop to locate the Naim Core’s UPnP ContentDirectory. This enables the extraction of proprietary WAV metadata (Title/Artist), high-resolution artwork, and track progress that standard DLNA renderers often fail to capture.

#### **B. Volume "Zero-Sync" Engine**
To resolve the lack of feedback from the analog Topping A90 Discrete, the driver implements a hardware-based re-zeroing logic:
1.  **Trigger:** Any source selection change (e.g., switching to Naim).
2.  **Action:** The BLI toggles A90 inputs (RCA $\rightarrow$ XLR).
3.  **Hardware Reaction:** The A90 Discrete triggers its internal **"Safe Volume"** (pre-configured to **0**).
4.  **Sync:** The BLI resets its internal `LAST_KNOWN_VOL` variable to **0**, ensuring 100% mathematical accuracy for subsequent IR pulse steps from the [BeoRemote Halo](https://www.bang-olufsen.com).

#### **C. Safety Governor**
A software-level hook `SAFE_VOL_LIMIT` is set to **60**. Any command from the B&O app or Halo exceeding this value is capped at the driver level to protect the BeoLab speakers.

---

### **5. Component Settings Checklist**
*   **Topping A90D:** `Safe Volume` = ON; `Safe Volume Level` = 0; `Volume Step` = 1.0dB.
*   **Topping D90:** `Output Mode` = XLR + RCA (Simultaneous).
*   **Beosound Core:** `Line-In Sensitivity` = High; `Line-In Fix Volume` = Enabled; `Line-In Sense` = Disabled.
*   **Naim Uniti Core:** `Output` = Fixed; `Server Mode` = Enabled.

---

### **6. Troubleshooting**
*   **No Metadata:** Verify Port 16000 is open. Check [Focal & Naim app](https://www.naimaudio.com) to ensure the music store is "Online."
*   **No Vintage Control:** Verify Port 3 Blaster mode. Check line-of-sight to the BM8000 right-side glass panel.
*   **Volume Desync:** Trigger a Source Selection macro to re-initiate the "Zero-Sync" ritual.

***
