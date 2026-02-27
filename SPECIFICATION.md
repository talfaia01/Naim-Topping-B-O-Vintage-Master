File Role: Resource Specification & UI Schema
Target Hardware: Beoliving Intelligence (Generation 3)
Compatibility: Naim Gen 2 Platform (Uniti Core) & Global Caché iTach Series
1. Interface & Capabilities Architecture
The JSON defines this device as a media_renderer. This specific class triggers the high-fidelity "Now Playing" screen in the Beoliving App, featuring the circular playback ring, large-scale album art, and high-resolution metadata fields.
media_browser & media_search: These capabilities enable the "Content" icon in the app. It specifically maps the BLI's internal search bar to the Naim’s UPnP ContentDirectory on Port 16000, allowing for real-time database queries of ripped WAV files.
volume_control: Unlike standard streamers, this is a Hybrid Volume Capability. While the Naim Core provides the audio, the JSON defines a volume state that the Lua script intercepts to control the Topping A90 Discrete analog relays via IR.
2. Resource & Selector Logic
source_selector: This is the master "Preamp" control. It defines five discrete states (Naim Core, B&O Streaming, Beogram Vinyl, Beocord Tape, FM Radio). Selecting an option here triggers a multi-step macro: switching the Topping D90 input (38kHz IR), switching the Topping A90 input (38kHz IR), and optionally triggering the Beomaster 8000 (455kHz IR).
playlist_selector: Designed specifically for the BeoRemote Halo wheel. It populates the Halo screen with "Smart Playlists" from the Naim Core, allowing the user to bypass the app for daily listening.
party_mode: A specialized switch resource. It manages the B&O Network Link state, commanding all satellite Beosound Cores and Stages to "Join" the Living Room's fixed RCA distribution path.
3. State Tracking & Metadata Schema
TRACK_PROGRESS & TRACK_DURATION: Defined as integers (seconds). These drive the real-time progress bar on the BeoRemote Halo.
AUDIO_QUALITY: A dynamic string state. It displays technical stream data (e.g., 192.0 kHz / 24b) to confirm the audiophile integrity of the BNC/AES signal path.
ONLINE_STATUS: An enumerated state (ONLINE/OFFLINE) driven by a 5-second HTTP heartbeat. This provides system health feedback directly to the Beoliving App notifications.
4. Safety & Constraints
VOLUME (min: 0, max: 100): While the scale is standard, the JSON sets the bounds for the Volume Safety Hook. The driver is constrained by a SAFE_VOL_LIMIT (typically 60) defined in the Lua logic to protect the BeoLab speakers from accidental gain spikes during source transitions.
