# BeoLiving Intelligence Driver: Vintage Analog Master

## Overview
This is a custom Lua driver designed for the BeoLiving Intelligence (BLI) platform. Its purpose is to integrate a vintage analog B&O stack (Beomaster 8000, Beogram, Beocord) and a Topping A90 Headphone Amplifier into the modern BeoLiving App interface via a Global Cache iTach IP-to-IR gateway.

## Intended Functionality
The driver uses standard BLI Standard Resource Types (SRT) to abstract complex IR macros into a clean user interface. 

* **Topping A90 Control:** Routes volume commands and custom `_SELECTOR` states for Gain and Output Mode (PRE, HPA, HPA+PRE).
* **Beomaster 8000 Control:** Maps standard B&O Datalink commands to wake the amplifier, switch to RCA routing, and trigger the physical turntable or tape deck.
* **Radio Presets:** Exposes a `_SELECTOR` to allow the user to label and select P1-P0 radio presets from the app.

## Current Roadblock (For Khimo Support)
The driver successfully compiles without errors and passes all strict syntax validations. The `executeCommand` backend logic works perfectly when invoked manually.

However, we are unable to get the **Sources/Inputs** to map natively to the BeoLiving App UI (under `Interfaces -> AV Products -> Inputs`). 

**What we have tried:**
1. We mapped the `Analog Receiver` as a `RENDERER`.
2. To satisfy the compiler, we defined the `SELECT_INPUT` command argument strictly as a `string`.
3. To trigger the UI dropdowns, we defined the `INPUT` state as an `enum` with the values: `{"Beogram Vinyl", "Beocord Tape", "FM Radio"}`.
4. We attempted to use the global `setResourceFieldsForID` inside `onResourceUpdate` to dynamically push the input table, but it appears custom drivers lack the internal permissions to write to the `AV Products` input mapping array.

**The Ask:**
Because the `Inputs` table remains blank in the Web Setup, we cannot expose native B&O source buttons (e.g., a "Turntable" or "Tape" icon) to the main Room/Zone screen. What is the correct protocol for a custom Lua driver to expose its `SELECT_INPUT` values so they can be mapped to native UI buttons in the BeoLiving App, similar to how official drivers (like LG webOS) dynamically populate the Inputs table?

## Setup & Testing
Currently, as a fallback, we have implemented an `Analog Source` resource using the `_SELECTOR` standard type to force a dropdown menu in the app, but a native `RENDERER` source mapping is the ultimate goal.
