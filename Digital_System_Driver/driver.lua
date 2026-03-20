-- =========================================================
-- SECTION 1: SPECIFICATION
-- =========================================================
driver_label = "Digital Hi-Fi Master"
driver_help = "Hybrid routing: Naim Core UPnP (HTTP), Topping D90 (iTach Port 1), and Topping A90 Pre-Amp (iTach Port 2)."

-- We dedicate the main driver channel entirely to the iTach TCP socket for instant IR firing
driver_channels = {
    TCP(4998, "192.168.1.100", "iTach Network", "Enter the IP address of your Global Cache iTach")
}

parameters = {
    stringArgument("naim_ip", "192.168.1.110", {context_help="IP Address of the Naim Core"})
}

resource_types = {
    ["Naim Core Player"] = {
        standardResourceType = "RENDERER",
        address = stringArgument("address", "naim_core"),
        events = {},
        commands = {
            -- Digital Transport (Naim HTTP)
            PLAY = {}, PAUSE = {}, STOP = {}, NEXT = {}, PREVIOUS = {},
            
            -- Pre-Amp Controls (A90 via iTach)
            VOLUME_UP = {}, 
            VOLUME_DOWN = {},
            _MUTE_TOGGLE = {},
            _SET_VOLUME = { arguments = { { name = "_volume", type = "int", default = 0, label = "Volume" } } }
        },
        states = {
            { name = "STATE", label = "Playback State", type = "string", default = "Stopped" },
            { name = "TRACK", label = "Track", type = "string", default = "" },
            { name = "ARTIST", label = "Artist", type = "string", default = "" },
            { name = "ALBUM", label = "Album", type = "string", default = "" },
            { name = "VOLUME", label = "Volume", type = "int", default = 0 }
        }
    },
    ["D90 DAC Filters"] = {
        standardResourceType = "_SELECTOR",
        address = stringArgument("address", "d90_filters"),
        events = { _SELECT = { arguments = { stringArgument("_value", "") } } },
        commands = { _SELECT = { arguments = { stringArgument("_value", "", {context_help="Select FIR Filter"}) } } },
        states = { { name = "_SELECTION", label = "Active Filter", type = "enum", default = "Mode 1", values = {"Mode 1", "Mode 2", "Mode 3", "Mode 4", "Mode 5", "Mode 6"} } }
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
-- SECTION 2: HARDWARE ROUTING & HTTP POLLING
-- =========================================================

-- iTach IR Routing
-- D90 is on Port 1 (1:1), A90 is on Port 2 (1:2)
local IR_D90_FILTER = "sendir,1:1,1,38000,..."
local IR_A90_VOL_UP = "sendir,1:2,1,38000,..."
local IR_A90_VOL_DN = "sendir,1:2,1,38000,..."
local IR_A90_MUTE   = "sendir,1:2,1,38000,..."

local function send_ir(hex_code)
    channel.write(hex_code .. "\r")
end

-- Naim HTTP Routing
local function send_naim_command(cmd)
    local url = "http://" .. config.naim_ip .. "/path/to/api/command?action=" .. cmd
    -- local response = http.request(url) 
    Trace("Sent Naim HTTP Command: " .. url)
end

local function poll_naim_metadata()
    local url = "http://" .. config.naim_ip .. "/path/to/api/status"
    -- local response = http.request(url)
    
    -- Placeholder mock data representing a successful XML/JSON parse
    local mock_state = "Playing"
    local mock_track = "Hello"
    local mock_artist = "Adele"
    local mock_album = "25"
    
    setResourceState("Naim Core Player", "naim_core", { 
        STATE = mock_state,
        TRACK = mock_track,
        ARTIST = mock_artist,
        ALBUM = mock_album
    })
end

-- =========================================================
-- SECTION 3: FUNCTIONALITY
-- =========================================================
function process()
    if channel.status() then driver.setOnline() end
    
    -- Polling Loop: By using a 5-second timeout on the read, we keep the TCP socket alive
    -- while simultaneously firing the Naim metadata HTTP poll every 5 seconds.
    while channel.status() do
        local msgError, msg = channel.read(5) 
        
        if msgError == CONST.TIMEOUT then
            poll_naim_metadata()
        end
    end
    
    channel.retry("iTach connection failed, retrying in 10 seconds", 10)
    driver.setError()
    return CONST.HW_ERROR
end

function executeCommand(command, resource, commandArgs)
    
    -- === 1. NAIM CORE (RENDERER + PRE-AMP) ===
    if resource.type == "Naim Core Player" then
        
        -- Naim Transport Control (HTTP)
        if command == "PLAY" then send_naim_command("play")
        elseif command == "PAUSE" then send_naim_command("pause")
        elseif command == "NEXT" then send_naim_command("next")
        elseif command == "PREVIOUS" then send_naim_command("previous")
        
        -- Topping A90 Volume Control (IR via iTach Port 2)
        elseif command == "VOLUME_UP" then send_ir(IR_A90_VOL_UP)
        elseif command == "VOLUME_DOWN" then send_ir(IR_A90_VOL_DN)
        elseif command == "_MUTE_TOGGLE" then send_ir(IR_A90_MUTE)
        elseif command == "_SET_VOLUME" then
            -- Note: Requires a volume sync function if moving from absolute to relative IR
            Trace("A90 Target Volume: " .. commandArgs._volume)
        end
        
    -- === 2. TOPPING D90 DAC FILTERS (iTach Port 1) ===
    elseif resource.type == "D90 DAC Filters" and command == "_SELECT" then
        send_ir(IR_D90_FILTER) -- Requires logic to cycle or explicitly set the filter
        setResourceState(resource.type, resource.address, { _SELECTION = commandArgs._value })
        Trace("D90 DAC Filter Selected: " .. commandArgs._value)

    -- === 3. TOPPING A90 OUTPUT & GAIN (iTach Port 2) ===
    elseif resource.type == "A90 Output Mode" and command == "_SELECT" then
        setResourceState(resource.type, resource.address, { _SELECTION = commandArgs._value })
        Trace("A90 Output Mode: " .. commandArgs._value)
        
    elseif resource.type == "A90 Gain" and command == "_SELECT" then
        setResourceState(resource.type, resource.address, { _SELECTION = commandArgs._value })
        Trace("A90 Gain: " .. commandArgs._value)
    end
end
