# 🏆 Pro-Tips: Naim-Topping-B&O Hybrid Integration
### Master Guidance for BeoLiving Intelligence (Gen 3) Architecture

This document consolidates the "Expert Level" configurations and calibration steps required to bridge 45 years of audio technology into a unified, high-performance ecosystem.

---

## 🔌 1. Hardware & Physical Setup
*   **iTach Port 3 Blaster Mode:** In the [Global Caché Web UI](https://www.globalcache.com), you **must** manually set Port 3 to **"IR Blaster."** Standard "Emitter" mode lacks the power to carry the 40.983kHz signal required by the Beomaster 8000.
*   **BM8000 Line-of-Sight:** Position the IR Blaster to target the **right side** of the Beomaster 8000’s glass panel. The vintage 10-bit microprocessor's IR receiver is located behind the display array.
*   **Static IP Mapping:** Ensure the **Naim Core**, **iTach**, and **BLI Gen 3** all have reserved/static IPs in your router. This eliminates "handshake lag" when the BLI fetches WAV metadata.

## 🎧 2. Signal Path & Audio Calibration
*   **The "Line-In Sense" Rule:** Disable "Line-In Sense" on the Living Room **Beosound Core**. Use the **BLI Gen 3** as the sole "brain" for activating the distribution path to prevent accidental triggers.
*   **Sensitivity Calibration:** Set the Beosound Core **Line-In Sensitivity to "High"** in the B&O App. This ensures the fixed-level RCA signal from the Topping D90 is robust when "Joined" by secondary rooms.
*   **Naim "Fixed" Output:** In the [Focal & Naim app](https://www.naimaudio.com), ensure the Uniti Core output is set to **"Fixed."** Variable output will cause the BLI "Safety Hook" to conflict with the Naim's internal digital volume.
*   **D90 Dual Output:** Confirm the **Topping D90** is set to **"XLR + RCA" simultaneous output** so the "Distribution Path" to the other rooms is always "live" while you listen in the main zone.

## 🎛️ 3. Topping A90 Discrete Specifics
*   **The "Zero-Sync" Anchor:** In the A90 internal menu, enable **"Safe Volume"** and set the level to **0**. The `reset_a90_hardware()` Lua function relies on this hardware behavior to "re-zero" the analog relays during source switching.
*   **Relay Safety (ms):** Maintain a **40ms to 50ms delay** (`os.sleep`) between volume IR pulses. Faster intervals may cause the A90’s physical relays to "chatter" or skip steps.
*   **Display Auto-Off:** Set the A90 display to **"Auto Off."** This reduces electrical noise in the preamp stage and improves IR receiver "attentiveness" to iTach pulses.

## 💻 4. BLI Gen 3 Software & Driver Logic
*   **Manifest-First Upload:** Always upload the `manifest.json` **before** the `driver.lua`. The BLI requires the JSON schema to create the environment variables (like `itach_ip`) used by the script.
*   **The "Search" Governor:** Maintain the `RequestedCount` for WAV searches at **50**. If library browsing feels sluggish, reduce this to **25** to lower the XML parsing load on the BLI CPU.
*   **Parametric Labels:** Utilize the **Preset Name parameters** (`p1_label`, etc.) in the BLI UI. This allows you to rename radio stations (e.g., "BBC Jazz") in the app without modifying the GitHub code. [Ref: Khimo Developer Guide](https://khimo.github.io)

## 🔘 5. BeoRemote Halo Interface Design
*   **Side-Swipe Strategy:** Map "Big Moves" (Source Select/Auto-Scan) to the main Halo screen. Place "Surgical Moves" (Fine-Tune/Gain/Filter) on a **side-swipe page** to keep the primary interface uncluttered.
*   **Tactile Feedback:** Use the **BeoRemote Halo** physical wheel for volume and source selection. Map the "Manual Scan" (>> ) to the Halo's touch arrows for a modern take on the vintage search experience.
*   **Color-Coding:** In the [BLI Interface Designer](https://beoliving.khimo.com), color-code the "Fine Tune" buttons in **B&O Blue** to mirror the vintage Beolab Terminal’s secondary function keys.

## 📂 6. Maintenance & Version Control
*   **Single Source of Truth:** Keep your [GitHub Repository](https://github.com) updated. It is your disaster recovery plan; if the BLI hardware fails, you can restore your entire 45-year hybrid system in minutes.
*   **Diagnostic Boot:** Run the `run_full_system_test()` script on the first boot of the Gen 3 to verify the **Port 16000 metadata path** and iTach connectivity are active.
