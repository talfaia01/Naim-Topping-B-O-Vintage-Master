# Naim-Topping-B&O Vintage Master Driver for BeoLiving Intelligence
**Version:** 3.8.0  
**Type:** Media Renderer / Multi-Protocol Custom Driver  

This BeoLiving Intelligence (BLI) driver bridges modern audiophile digital streaming with vintage analog B&O hardware. It seamlessly integrates a Naim Uniti Core, a Topping D90/A90 Discrete stack, and a vintage Beomaster 8000 into a unified, single-interface control system.

## 🏗️ System Architecture & IR Routing
This driver utilizes a combination of REST API commands, UPnP XML parsing, and raw hexadecimal IR pulses routed through a Global Caché iTach adapter.

### iTach Port Mapping
For the driver to function correctly, your IR emitters must be plugged into the following ports on your iTach device:
* **Port 1:1 - Topping D90 DAC:** Uses the RC-15A protocol (`0x11EE` header). 
* **Port 1:2 - Topping A90 Discrete Pre-Amp:** Uses the RC-16A protocol (`0x5AA5` header). Requires a 300ms "Wake" pulse prior to execution to bypass the OLED screen saver.
* **Port 1:3 - Beomaster 8000:** Uses the custom 40.9 kHz B&O Datalink IR protocol.

*Note: Because the D90 and A90 Discrete use completely different IR address headers, you do not need to worry about IR command cross-contamination between the two units.*

---

## ⚙️ Hardware Pre-Requisites (CRITICAL)

Before loading this driver into the BeoLiving Intelligence, you must configure your physical Topping hardware to support the automation logic:

### 1. Topping A90 Discrete: Save Inputs to Memory
The Topping RC-16A remote only possesses sequential Left/Right input arrows, which are unreliable for automation. This driver bypasses this by utilizing the custom `C1` and `C2` memory buttons.
1. Use the physical knob on the A90 Discrete to select the **XLR** input.
2. Press and hold the **C1** button on your physical remote until the screen flashes.
3. Switch the A90 input to **RCA**, and press and hold **C2** to save it.

### 2. Topping D90 DAC: Enable Auto-Power
To prevent input de-syncing, this driver relies on the D90's native hardware logic to detect the active digital audio stream.
1. Press the **AUTO** button on your RC-15A remote until the D90 screen reads **"Auto On"** (or toggle "Auto Power" to ON in the D90's hidden boot menu).
2. The D90 will now automatically wake and lock onto the correct digital input whenever the Naim Uniti Core or B&O Streamer begins playing.

---

## 🛠️ BLI Parameter Configuration

When adding this resource to your BeoLiving Intelligence, configure the following parameters:

| Parameter | Description | Required |
| :--- | :--- | :--- |
| **iTach IP Address** | The local IP address of your Global Caché iTach (e.g., `192.168.77.XXX`). | Yes |
| **Living Room Core Path** | The exact BLI resource path for your primary B&O Core (e.g., `Main/Living Room/AV renderer/BS Core 5`). | Yes |
| **Party Zone Paths** | Comma-separated BLI paths for secondary B&O zones you want to join during "House Party Mode". | No |
| **Run Diagnostics** | If checked, the driver will automatically test Naim APIs and iTach pings on system boot. | No |
| **P1 - P0 Labels** | Custom display names for your Beomaster 8000 FM Radio presets (e.g., "93.3 WMMR"). These will print to the system log when selected from the UI dropdown. | No |

---

## 🎛️ Supported Features & UI Controls

**Naim Uniti Core Integration**
* **Instant Transport Controls:** Play, Pause, Next Track, Prev Track, Repeat, and Shuffle via Port 15081 REST API.
* **Now Playing Metadata:** High-resolution album art, track title, artist name, and track progress parsed natively via UPnP XML SOAP envelopes.
* **Audio Quality Polling:** Live reporting of bit-depth and sample rate (e.g., `44.1 kHz / 16b`).
* *Note: Direct playlist/album REST triggering is deprecated due to Naim firmware restrictions. Users should use the Focal & Naim app to queue music.*

**Topping Stack Control**
* **A90 Discrete Volume:** Hardware-synced volume ramping with intelligent "Wake" pulse logic.
* **A90 Output & Gain:** Discrete toggles for PRE (Speakers), HPA (Headphones), or HPA+PRE, plus High/Low Gain switching.
* **A90 Mute & Power:** Instant discrete toggles.
* **D90 FIR Filter:** On-the-fly toggling of the DAC's digital roll-off curves.
* **D90 Input Fallback:** Manual `>>` and `<<` buttons if the Auto-Sense feature requires nudging.

**Vintage Beomaster 8000 Routing**
* **Source Selection:** Seamless switching between Beogram Vinyl, Beocord Tape, and FM Radio.
* **FM Radio:** Scan Up/Down, Fine Tune Balance (`>`/`<`), and Filter toggles.
* **Preset Tuning:** A clean UI dropdown selector to instantly tune to Presets P1 through P0 (10), utilizing your custom parameter labels.

**House Party Mode**
* A single UI switch that instantly forces the B&O Beosound Core to broadcast its Line-In, wakes up the BeoLink ecosystem, and distributes the Naim Core audiophile stream perfectly in-sync to all secondary zones defined in your BLI parameters.

---

## 📂 Installation
1.  Upload `src/manifest.json` to the **Specification** tab of the BLI Gen 3 Editor.
2.  Upload `src/driver.lua` to the **Script** tab.
3.  Configure `itach_ip` in the resource data to point to your [Global Caché IP2IR](https://www.globalcache.com).
4.  **Important:** Set iTach **Port 3** to **IR Blaster** mode for 40.983kHz support.

---

## 🛠 Tech Stack
*   **Language:** Lua 5.3 (Khimo Runtime)
*   **Protocols:** REST (15081), UPnP/SOAP (16000), SSDP (1900), TCP IR (4998)
