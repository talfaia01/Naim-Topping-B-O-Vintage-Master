-- =========================================================
-- SECTION 1: SPECIFICATION
-- =========================================================
driver_label = "Vintage Analog Master"
driver_help = "Strictly Analog routing: Beomaster 8000, Beogram, Beocord, and Topping A90 Amplifier via iTach IP-to-IR."

driver_channels = {
    TCP(4998, "192.168.1.100", "iTach Network", "Enter the IP address of your Global Cache iTach")
}

parameters = {
    stringArgument("_p1_label", "P1", {context_help="Preset 1 Name"}),
    stringArgument("_p2_label", "P2", {context_help="Preset 2 Name"}),
    stringArgument("_p3_label", "P3", {context_help="Preset 3 Name"}),
    stringArgument("_p4_label", "P4", {context_help="Preset 4 Name"}),
    stringArgument("_p5_label", "P5", {context_help="Preset 5 Name"}),
    stringArgument("_p6_label", "P6", {context_help="Preset 6 Name"}),
    stringArgument("_p7_label", "P7", {context_help="Preset 7 Name"}),
    stringArgument("_p8_label", "P8", {context_help="Preset 8 Name"}),
    stringArgument("_p9_label", "P9", {context_help="Preset 9 Name"}),
    stringArgument("_p0_label", "P0", {context_help="Preset 0 Name"})
}

resource_types = {
    ["Analog Receiver"] = {
        standardResourceType = "RENDERER",
        address = stringArgument("address", "main"),
        events = {},
        commands = {
            TURN_ON = {}, 
            STANDBY = {}, 
            VOLUME_UP = {}, 
            VOLUME_DOWN = {},
            SELECT_INPUT = { arguments = { { name = "INPUT", type = "string", default = "", label = "Source" } } },
            _SET_VOLUME = { arguments = { { name = "_volume", type = "int", default = 0, label = "Volume" } } },
            _MUTE_TOGGLE = {}, _SCAN_UP = {}, _SCAN_DOWN = {}, _FINE_UP = {}, _FINE_DOWN = {}, _FILTER_TOGGLE = {}, _STOP_TAPE = {}
        },
        states = {
            { name = "INPUT", label = "Source", type = "enum", default = "FM Radio", values = {"Beogram Vinyl", "Beocord Tape", "FM Radio"} },
            { name = "VOLUME", label = "Volume", type = "int", default = 0 }
        }
    },
    ["Analog Source"] = {
        standardResourceType = "_SELECTOR",
        address = stringArgument("address", "source"),
        events = { _SELECT = { arguments = { stringArgument("_value", "") } } },
        commands = { _SELECT = { arguments = { stringArgument("_value", "", {context_help="Select Source"}) } } },
        states = { { name = "_SELECTION", label = "Source", type = "enum", default = "FM Radio", values = {"Beogram Vinyl", "Beocord Tape", "FM Radio"} } }
    },
    ["BM8000 Presets"] = {
        standardResourceType = "_SELECTOR",
        address = stringArgument("address", "presets"),
        events = { _SELECT = { arguments = { stringArgument("_value", "") } } },
        commands = { _SELECT = { arguments = { stringArgument("_value", "", {context_help="P1 through P0"}) } } },
        states = { { name = "_SELECTION", label = "Active Preset", type = "enum", default = "P1", values = {"P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P0"} } }
    },
    ["A90 Output Mode"] = {
        standardResourceType = "_SELECTOR",
        address = stringArgument("address", "a90_output"),
        events = { _SELECT = { arguments = { stringArgument("_value", "") } } },
        commands = { _SELECT = { arguments = { stringArgument("_value", "", {context_help="PRE, HPA, HPA+PRE"}) } } },
        states = { { name = "_SELECTION", label = "Active Output", type = "enum", default = "PRE", values = {"PRE", "HPA", "HPA+PRE"} } }
    },
    ["A90 Gain"] = {
        standardResourceType = "_SELECTOR",
        address = stringArgument("address", "a90_gain"),
        events = { _SELECT = { arguments = { stringArgument("_value", "") } } },
        commands = { _SELECT = { arguments = { stringArgument("_value", "", {context_help="Low Gain, High Gain"}) } } },
        states = { { name = "_SELECTION", label = "Active Gain", type = "enum", default = "Low Gain", values = {"Low Gain", "High Gain"} } }
    }
}

-- =========================================================
-- SECTION 2: IR CODES & HELPERS (Placeholder Logic)
-- =========================================================
local IR_A90_WAKE = "sendir,1:1,1,38000,..."
local IR_A90_RCA = "sendir,1:1,1,38000,..."
local IR_BM8000_PHONO = "sendir,1:2,1,38000,..."
local IR_BM8000_TAPE = "sendir,1:2,1,38000,..."
local IR_BM8000_RADIO = "sendir,1:2,1,38000,..."

local function send_ir(hex_code)
    channel.write(hex_code .. "\r")
end

local function wake_a90()
    send_ir(IR_A90_WAKE)
end

-- =========================================================
-- SECTION 3: FUNCTIONALITY
-- =========================================================
function process()
    if channel.status() then driver.setOnline() end
    while channel.status() do
        local msgError, msg = channel.readUntil("\r")
    end
    channel.retry("Connection failed, retrying in 10 seconds", 10)
    driver.setError()
    return CONST.HW_ERROR
end

function executeCommand(command, resource, commandArgs)
    
    -- === 1. ANALOG RECEIVER (RENDERER) ===
    if resource.type == "Analog Receiver" then
        if command == "SELECT_INPUT" then
            local target_input = commandArgs.INPUT
            wake_a90()
            send_ir(IR_A90_RCA)
            
            if target_input == "Beogram Vinyl" then
                send_ir(IR_BM8000_PHONO)
            elseif target_input == "Beocord Tape" then
                send_ir(IR_BM8000_TAPE)
            elseif target_input == "FM Radio" then
                send_ir(IR_BM8000_RADIO)
            end
            
            setResourceState(resource.type, resource.address, { INPUT = target_input })
            Trace("Native Source Selected: " .. target_input)
        end
        
    -- === 2. ANALOG SOURCE (DROPDOWN MENU FALLBACK) ===
    elseif resource.type == "Analog Source" and command == "_SELECT" then
        local source = commandArgs._value
        wake_a90()
        send_ir(IR_A90_RCA) 
        
        if source == "Beogram Vinyl" then
            send_ir(IR_BM8000_PHONO)
        elseif source == "Beocord Tape" then
            send_ir(IR_BM8000_TAPE)
        elseif source == "FM Radio" then
            send_ir(IR_BM8000_RADIO)
        end
        
        setResourceState(resource.type, resource.address, { _SELECTION = source })
        Trace("Dropdown Source Selected: " .. source)

    -- === 3. BM8000 PRESETS & TOPPING CONTROLS ===
    elseif resource.type == "BM8000 Presets" and command == "_SELECT" then
        setResourceState(resource.type, resource.address, { _SELECTION = commandArgs._value })
        Trace("Preset Selected: " .. commandArgs._value)
        
    elseif resource.type == "A90 Output Mode" and command == "_SELECT" then
        setResourceState(resource.type, resource.address, { _SELECTION = commandArgs._value })
        Trace("Output Mode: " .. commandArgs._value)
        
    elseif resource.type == "A90 Gain" and command == "_SELECT" then
        setResourceState(resource.type, resource.address, { _SELECTION = commandArgs._value })
        Trace("Gain: " .. commandArgs._value)
    end
end
