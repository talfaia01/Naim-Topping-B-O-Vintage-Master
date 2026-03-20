# BeoLiving Intelligence Driver: Digital Hi-Fi Master

## Overview
This is a custom Lua driver designed for the BeoLiving Intelligence (BLI) platform to integrate the digital side of a high-fidelity audio stack. It provides unified control over a Naim Core audio server (via UPnP/HTTP) and the Topping DAC/Pre-Amp stack (via a Global Cache iTach IP2IR gateway).

## Architecture & Hardware Routing
This driver utilizes a **Hybrid Control Strategy**, managing two separate network protocols simultaneously without dropping connections.

1. **The iTach TCP Socket (Main Channel):** The driver maintains a persistent TCP connection to the iTach IP2IR gateway to ensure zero-latency execution of IR commands.
   * **Port 1 (`1:1`):** Routed to the **Topping D90 DAC** for toggling FIR filter modes.
   * **Port 2 (`1:2`):** Routed to the **Topping A90 Pre-Amp** for unified system volume control, mute, gain, and output mode selection.
2. **The Naim Core Polling (HTTP):** The driver utilizes a non-blocking 5-second timeout inside the main TCP `process()` loop to quietly execute asynchronous `http.request()` calls to the Naim Core. This pulls live metadata (Track, Artist, Album, Playback State) without disrupting the TCP socket.

## Intended Functionality
* **Naim Core Player (`RENDERER`):** Acts as the primary Room interface in the BLI app. Transport commands (Play, Pause, Next) are routed over HTTP to the Naim Core, while Volume commands (Vol Up, Vol Down, Mute) are natively intercepted and routed to the Topping A90 via iTach Port 2. 
* **Live Metadata:** The UI dynamically populates with the currently playing track and artist based on the background UPnP polling.
* **Topping Controls (`_SELECTOR`):** Exposes three custom dropdown menus in the app to control the D90 DAC Filters, A90 Output Mode, and A90 Gain.

## Development Status & Next Steps
This script represents the structurally validated BLI framework. The following elements require final implementation based on the local network topology:
1. **Naim UPnP API Endpoints:** The HTTP GET/POST URLs in `send_naim_command()` and `poll_naim_metadata()` must be updated with the exact XML/SOAP paths required by the Naim Core's UPnP architecture.
2. **XML/JSON Parsing:** A lightweight Lua pattern matcher must be added to `poll_naim_metadata()` to extract the `TRACK`, `ARTIST`, and `STATE` values from the Naim Core's payload.
3. **IR Hex Injection:** The exact Global Cache hex codes for the D90 (Port 1) and A90 (Port 2) need to be inserted into the placeholder variables in Section 2.
