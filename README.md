# Naim-Topping-B-O-Vintage-Master
Unified Audiophile Driver: Naim Core, Topping Stack, BM8000, and B&amp;O Link

Welcome to the Naim-Topping-Vintage Master driver repository. This project is a professional-grade integration designed for the Beoliving Intelligence (Generation 3) hardware by Khimo.
It enables seamless control of a high-fidelity "Triple-Hybrid" ecosystem, bridging modern digital streaming, local bit-perfect WAV libraries, and 1980s-era vintage analog hardware into a single, unified Bang & Olufsen user experience.

🎧 The Architecture -->
This driver is built to manage a complex signal path involving:
Digital: Naim Uniti Core serving bit-perfect WAV rips via BNC/AES to a Topping D90 DAC.
Streaming: Beosound Core providing Tidal and B&O Radio via Optical to the D90 DAC.
Analog: Beomaster 8000 series (Beogram 8002/Beocord 8004) feeding a Topping A90 Discrete preamp.
Distribution: Distribution of Naim audio to five secondary Beosound Cores, a Beosystem 4 Theater, and a Beosound Stage via B&O Network Link.

✨ Key Features -->
WAV Metadata Mastery: Native parsing of Naim’s proprietary WAV metadata and artwork via Port 16000 (Platinum UPnP).
455kHz Vintage Link: Controls the Beomaster 8000 using high-frequency IR bursts (via Global Caché iTach), automating the Beogram 8002 turntable and Beocord 8004 tape deck.
Progress & Quality Badges: Real-time track progress and audio quality status (e.g., 192.0 kHz / 24b) displayed on the BeoRemote Halo.
Volume Safety Governor: Implements a SAFE_VOL_LIMIT and a "Hardware Reset to Zero" logic for the Topping A90 Discrete analog relays.
Seamless Multiroom: A one-tap "Party Mode" that coordinates the Living Room's fixed RCA distribution across the entire B&O home network.

🚀 Installation for Gen 3 BLI -->
Specification: Upload src/manifest.json to the Specification tab of the Custom Driver Editor.
Script: Upload src/driver.lua to the Script tab.
Hardware Config:
Set Address to your Naim Core IP.
Set itach_ip in the resource data to your Global Caché IP2IR.
Ensure iTach Port 3 is in Blaster Mode for 455kHz support.

🛠 Tech Stack -->
Language: Lua 5.3 (Khimo Environment)
Protocols: HTTP REST (15081), UPnP/SOAP (16000), SSDP (1900), TCP (4998/IR)
Metadata Engine: Platinum UPnP SDK v1.0.5.13

🤝 Community & Support -->
This driver was developed to solve the unique challenges of integrating Naim's server architecture with B&O's control ecosystem. For community discussion or troubleshooting regarding WAV rip identification or Datalink automation, please refer to the Naim Community or the BeoWorld Forums.
