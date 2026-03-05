# Naim-Topping-B&O Vintage Hybrid System Controller
### 🚀 Optimized for Beoliving Intelligence (Gen 3)

This repository contains the professional-grade, multi-protocol driver for the **Beoliving Intelligence (Generation 3)**. It enables seamless control of a "Triple-Hybrid" audiophile ecosystem, bridging 1980s analog engineering with modern 24-bit/192kHz digital processing.

---

## 🏗 System Architecture
The system integrates three distinct generations of technology into a unified Bang & Olufsen user experience:

1.  **Digital Transport:** [Naim Uniti Core](https://www.naimaudio.com) serving bit-perfect **WAV rips** via BNC/AES.
2.  **Conversion & Preamp:** [Topping D90 DAC](https://www.tpdz.net) and [Topping A90 Discrete](https://www.tpdz.net) managed via [Global Caché iTach IP2IR](https://www.globalcache.com).
3.  **Vintage Analog:** [Beomaster 8000](https://beoworld.org) stack (Beogram 8002/Beocord 8004) controlled via the same unique unique 8-bit **40.983 kHz infrared protocol** as the original [Beolab Terminal](https://beoworld.org/beolab-terminal-remote-controller/) Remote Controller.
4.  **Whole-Home Distribution:** Living Room fixed RCA path distributed to 5x Beosound Cores, Beosystem 4, and Beosound Stage.

## 🌐 Signal Path & Logic Map

This system utilizes a **Dual-Path Hybrid Architecture** to maintain bit-perfect audiophile integrity while enabling high-resolution whole-home distribution.

### 1. Primary Digital Path ("Naim Core" Source)
*   **Path:** [Naim Uniti Core](https://www.naimaudio.com) (BNC) → [Topping D90 DAC](https://www.tpdz.net) (AES).
*   **Performance:** Handles 24-bit/192kHz bit-perfect WAV rips for critical listening.

### 2. Secondary Streaming Path ("B&O Streaming" Source)
*   **Path:** [Beosound Core](https://www.bang-olufsen.com) (Optical) → Topping D90 DAC (Optical).
*   **Performance:** Integrates B&O Radio and Tidal directly into the Topping stack via a galvanic-isolated digital link.

### 3. Analog Path ("Vintage" Sources)
*   **Path:** [Beomaster 8000](https://beoworld.org) (RCA) → [Topping A90 Discrete](https://www.tpdz.net) (RCA).
*   **Performance:** Pure analog signal path for Vinyl (8002), Tape (8004), and FM Tuner.

### 4. Whole-Home Distribution Path
*   **Path:** Topping D90 (RCA Fixed) → Beosound Core (Line-In).
*   **Function:** This "loops" the Naim's decoded analog signal back into the B&O Network Link.
*   **Multiroom:** Allows any of the 5 secondary Cores or the Home Theater to "Join" the Naim stream without affecting the Living Room volume.

---

## ✨ Key Features

### 🔍 WAV Metadata & Search
*   **Proprietary WAV Parsing:** Native extraction of Naim metadata/artwork via **Port 16000 (UPnP)**.
*   **Halo Progress Sync:** Real-time track progress and duration displayed on the [BeoRemote Halo](https://www.bang-olufsen.com).
*   **Library Search:** Integrated `media_search` capability for the internal Naim WAV database.

### 🛡 Volume Safety & Sync
*   **Zero-Sync Logic:** A unique `reset_a90_hardware()` function toggles preamp inputs to trigger the A90’s internal **Safe Volume** reset, ensuring the digital app slider and analog relays are perfectly aligned at 0.
*   **Safety Governor:** Hard-coded `SAFE_VOL_LIMIT = 60` to protect BeoLab speakers from gain spikes.

### 📼 Vintage Datalink Bridge
*   **40.983 kHz Control:** Targeted IR bursts simulate the [Beolab Terminal]([https://beoworld.org](https://beoworld.org/beolab-terminal-remote-controller/) to automate the Beomaster 8000.
*   **Automation:** Triggering "Phono" on the app automatically starts the Beogram 8002 turntable arm.

---

## 🛠 Hardware Calibration, Safety & Final Setup

To ensure **Hardware Safety** as well as the **Distribution Path** (Naim → House) and **Source Switching** are seamless, follow these hardware calibration steps:

### Topping A90 Discrete Settings
To ensure the "Zero-Sync" volume logic functions correctly, the A90 Discrete must be configured as follows:
*   **Safe Volume Mode (SAFE):** Set to **ON**.
*   **Safe Volume Level:** Set to **0** (or -99dB).
    *   *Logic:* Toggling inputs via the BLI forces the A90 to this 'Anchor' level, allowing the driver to perfectly sync the digital slider with the analog relays.
*   **Volume Step:** Set to **1.0dB**.

### 2. Beosound Core (Living Room) - "The Hub"
*   **Line-In Sensitivity:** In the B&O App, set to **"High"**. This ensures the fixed-level RCA signal from the Topping D90 is robust enough for the secondary rooms.
*   **Line-In Fix Volume:** Set to **"Enabled/Fixed"**.
*   **Line-In Sense:** Set to **"Disabled"** (The BLI Gen 3 handles all switching logic).

### 3. Topping D90 DAC
*   **Output Mode:** Must be set to **"XLR + RCA"** (simultaneous).
*   **Bluetooth:** Disable to prevent interference with the iTach IR signal.

### 4. Beomaster 8000
*   **Safe Startup:** Ensure the BM8000 internal "Start Volume" is set to a moderate level (e.g., 3.0) to match the gain of your digital sources.

---

## 📂 Installation
1.  Upload `src/manifest.json` to the **Specification** tab of the BLI Gen 3 Editor.
2.  Upload `src/driver.lua` to the **Script** tab.
3.  Configure `itach_ip` in the resource data to point to your [Global Caché IP2IR](https://www.globalcache.com).
4.  **Important:** Set iTach **Port 3** to **IR Blaster** mode for 455kHz support.

---

## 🛠 Tech Stack
*   **Language:** Lua 5.3 (Khimo Runtime)
*   **Protocols:** REST (15081), UPnP/SOAP (16000), SSDP (1900), TCP IR (4998)
