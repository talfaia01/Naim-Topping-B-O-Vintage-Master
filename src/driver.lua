local http = require("http")
local json = require("json")
local udp = require("udp")
local tcp = require("tcp")

-- 1. CONFIGURATION & STATE TRACKING
local CORE_IP = device.address 
local SAFE_VOL_LIMIT = 60
local LAST_KNOWN_VOL = 0 
local CURRENT_SOURCE = ""
local error_count = 0
local CURRENT_FM_PRESET = 1 

-- 2. PARAMETER HELPERS
function get_itach_ip()
    local ip = device:get_data("itach_ip")
    return (ip and ip ~= "") and ip or "0.0.0.0"
end

function get_primary_core()
    local path = device:get_data("primary_core_path")
    return (path and path ~= "") and path or "Main/Living Room/AV renderer/BS Core 5"
end

function get_party_zones()
    local zones_str = device:get_data("party_zone_paths") or ""
    local zones = {}
    for z in string.gmatch(zones_str, "([^,]+)") do
        local clean_z = z:match("^%s*(.-)%s*$")
        if clean_z and clean_z ~= "" then table.insert(zones, clean_z) end
    end
    return zones
end

-- 3. IR COMMAND LIBRARY (Global Caché Format)

-- Topping D90 DAC (Port 1:1) - Captured from iLearn
local IR_D90_ARROW_RIGHT   = "sendir,1:1,1,37764,1,1,341,170,22,21,22,21,22,21,22,63,22,21,22,21,22,21,22,63,22,63,22,63,22,63,22,21,22,63,22,63,22,63,22,21,22,63,22,21,22,63,22,21,22,63,22,21,22,21,22,21,22,21,22,63,22,21,22,63,22,21,22,63,22,63,22,63,22,1517,341,85,22,3645,341,85,22,3645,341,85,22,3700"
local IR_D90_ARROW_LEFT    = "sendir,1:1,1,37764,1,1,341,170,22,21,22,21,22,21,22,63,22,21,22,21,22,21,22,63,22,63,22,63,22,63,22,21,22,63,22,63,22,63,22,21,22,63,22,63,22,63,22,21,22,21,22,21,22,63,22,21,22,21,22,21,22,21,22,63,22,63,22,63,22,21,22,63,22,1515,341,85,22,3644,341,85,22,3700"
local IR_D90_FIR           = "sendir,1:1,1,37764,1,1,341,170,22,21,22,21,22,21,22,63,22,21,22,21,22,21,22,63,22,63,22,63,22,63,22,21,22,63,22,63,22,63,22,21,22,21,22,21,22,63,22,21,22,63,22,21,22,63,22,21,22,63,22,63,22,21,22,63,22,21,22,63,22,21,22,63,22,1515,341,85,22,3643,341,85,22,3700"

-- Topping A90 Discrete (Port 1:2) - Captured from iLearn
local IR_A90_CENTER        = "sendir,1:2,1,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,1525,343,85,22,3800"
local IR_A90_VOL_UP        = "sendir,1:2,2,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,64,22,64,22,21,22,21,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,64,22,64,22,21,22,64,22,1526,343,85,22,3800"
local IR_A90_VOL_DOWN      = "sendir,1:2,1,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,21,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,64,22,64,22,1526,343,85,22,3800"
local IR_A90_OUTPUT_TOGGLE = "sendir,1:2,1,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,21,22,21,22,21,22,21,22,64,22,64,22,21,22,64,22,64,22,64,22,64,22,64,22,1525,343,85,22,3666,343,85,22,3800"
local IR_A90_GAIN_TOGGLE   = "sendir,1:2,1,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,21,22,21,22,21,22,64,22,21,22,21,22,21,22,64,22,64,22,64,22,64,22,21,22,64,22,64,22,64,22,1525,343,85,22,3666,343,85,22,3666,343,85,22,3666,343,85,22,3800"
local IR_A90_POWER         = "sendir,1:2,1,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,21,22,21,22,64,22,64,22,21,22,21,22,21,22,64,22,64,22,64,22,21,22,21,22,64,22,64,22,64,22,1525,343,85,22,3665,343,85,22,3800"
local IR_A90_XLR           = "sendir,1:2,1,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,3800" -- C1
local IR_A90_RCA           = "sendir,1:2,2,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,21,22,21,22,21,22,64,22,21,22,64,22,21,22,64,22,64,22,64,22,64,22,21,22,64,22,21,22,64,22,1526,343,85,22,3800" -- C2
local IR_A90_MUTE          = "sendir,1:2,1,38226,1,1,343,171,22,21,22,64,22,21,22,64,22,64,22,21,22,64,22,21,22,64,22,21,22,64,22,21,22,21,22,64,22,21,22,64,22,21,22,64,22,64,22,21,22,21,22,21,22,21,22,21,22,64,22,21,22,21,22,64,22,64,22,64,22,64,22,64,22,1525,343,85,22,3800"

-- Beomaster 8000 / Beolab Terminal (Port 1:3)
local IR_BM8000_DATALINK_PHONO_ON = "sendir,1:3,1,40983,1,1,256,512,256,1024,256,512,256,1024,256,512,256,4000"
local IR_BM8000_DATALINK_TAPE_ON  = "sendir,1:3,1,40983,1,1,128,128,256,128,384,1024,128,128,256,128,384,1024,128,128,256,128,384,4000"
local IR_BM8000_RADIO = "sendir,1:3,1,40983,1,1,128,640,256,1024,128,640,256,1024,128,640,256,4000"
local IR_BM8000_SCAN_UP = "sendir,1:3,1,40983,1,1,128,128,256,384,128,1024,128,128,256,384,128,1024,128,128,256,384,128,4000"
local IR_BM8000_SCAN_DN = "sendir,1:3,1,40983,1,1,128,128,128,128,512,1024,128,128,128,128,512,1024,128,128,128,128,512,4000"
local IR_BM8000_FINE_UP = "sendir,1:3,1,40983,1,1,128,128,128,512,128,1024,128,128,128,512,128,1024,128,128,128,512,128,4000"
local IR_BM8000_FINE_DN = "sendir,1:3,1,40983,1,1,128,128,128,384,256,1024,128,128,128,384,256,1024,128,128,128,384,256,4000"
local IR_BM8000_FILTER = "sendir,1:3,1,40983,1,1,128,256,384,128,128,1024,128,256,384,128,128,1024,128,256,384,128,128,4000"
local IR_BM8000_STOP = "sendir,1:3,1,40983,1,1,128,128,256,128,128,128,128,1024,128,128,256,128,128,128,128,1024,128,128,256,128,128,128,128,4000"
local IR_BM8000_KEYS = {
    ["P1"] = "sendir,1:3,1,40983,1,1,128,640,256,1024,128,640,256,1024,128,640,256,4000",
    ["P2"] = "sendir,1:3,1,40983,1,1,128,512,128,128,128,1024,128,512,128,128,128,1024,128,512,128,128,128,4000",
    ["P3"] = "sendir,1:3,1,40983,1,1,128,512,384,1024,128,512,384,1024,128,512,384,4000",
    ["P4"] = "sendir,1:3,1,40983,1,1,128,384,128,256,128,1024,128,384,128,256,128,1024,128,384,128,256,128,4000",
    ["P5"] = "sendir,1:3,1,40983,1,1,128,384,128,128,256,1024,128,384,128,128,256,1024,128,384,128,128,256,4000",
    ["P6"] = "sendir,1:3,1,40983,1,1,128,384,256,128,128,1024,128,384,256,128,128,1024,128,384,256,128,128,4000",
    ["P7"] = "sendir,1:3,1,40983,1,1,128,384,512,1024,128,384,512,1024,128,384,512,4000",
    ["P8"] = "sendir,1:3,1,40983,1,1,128,256,128,384,128,1024,128,256,128,384,128,1024,128,256,128,384,128,4000",
    ["P9"] = "sendir,1:3,1,40983,1,1,128,256,128,256,256,1024,128,256,128,256,256,1024,128,256,128,256,256,4000",
    ["P0"] = "sendir,1:3,1,40983,1,1,128,768,128,1024,128,768,128,1024,128,768,128,4000"
}

-- 4. LIFECYCLE
function on_init()
    print("Naim-Topping Master Driver v3.8.0 Starting...")
    discover_upnp_port()
    
    local run_auto_diag = device:get_data("run_diag_on_boot")
    if run_auto_diag == true or run_auto_diag == "true" then
        run_full_system_test()
    end
end

function process()
    while true do
        heartbeat_and_status()
        poll_upnp_metadata_and_progress()
        os.sleep(3) 
    end
end

-- 5. UTILITIES
function to_seconds(hms)
    if not hms then return 0 end
    local h, m, s = hms:match("(%d+):(%d+):(%d+)")
    return (tonumber(h or 0) * 3600) + (tonumber(m or 0) * 60) + tonumber(s or 0)
end

function send_ir(payload)
    if not payload then return end
    local ITACH_IP = get_itach_ip()
    if ITACH_IP == "0.0.0.0" then return end
    local client = tcp.new()
    client:connect(ITACH_IP, 4998, function(res, err)
        if not err then client:send(payload .. "\r") client:close() end
    end)
end

function wake_a90()
    send_ir(IR_A90_CENTER)
    os.sleep(0.3) 
end

function sync_topping_volume(target_vol)
    local diff = target_vol - LAST_KNOWN_VOL
    if diff == 0 then return end
    wake_a90()
    local cmd = ""
    if diff > 0 then
        cmd = IR_A90_VOL_UP
    else
        cmd = IR_A90_VOL_DOWN
    end
    for i = 1, math.abs(diff) do
        send_ir(cmd)
        os.sleep(0.05) 
    end
    LAST_KNOWN_VOL = target_vol
    print("Topping A90 Hardware Synced to: " .. target_vol)
end

function reset_a90_hardware()
    print("CRITICAL: Executing A90 Hardware Sync...")
    wake_a90()
    send_ir(IR_A90_RCA)
    os.sleep(0.5)
    send_ir(IR_A90_XLR)
    os.sleep(0.5)
    device:set_state("VOLUME", 0)
    LAST_KNOWN_VOL = 0
    print("A90 Hardware Zero Sync Complete.")
end

-- 6. POLLING LOGIC
function heartbeat_and_status()
    http.get("http://" .. CORE_IP .. ":15081/nowplaying", function(res, err)
        if err then
            error_count = error_count + 1
            if error_count >= 3 then device:set_state("ONLINE_STATUS", "OFFLINE") end
        else
            error_count = 0
            device:set_state("ONLINE_STATUS", "ONLINE")
            local status, d = pcall(json.decode, res.body)
            if status and d then
                local state = "STOPPED"
                if d.transportState == "2" then state = "PLAYING"
                elseif d.transportState == "1" then state = "PAUSED"
                elseif d.transportState == "3" then state = "BUFFERING" end
                
                device:set_state("TRANSPORT_STATE", state)
                
                -- AUDIO QUALITY PARSING
                if d.sampleRate and d.bitDepth then
                    local sr = tonumber(d.sampleRate) or 44100
                    local bd = tostring(d.bitDepth)
                    device:set_state("AUDIO_QUALITY", string.format("%.1f kHz / %sbit", sr/1000, bd))
                else
                    device:set_state("AUDIO_QUALITY", "Unknown Quality")
                end
            end
        end
    end)
end

function poll_upnp_metadata_and_progress()
    local port = device:get_data("upnp_port") or "16000"
    local url = "http://" .. CORE_IP .. ":" .. port .. "/xml/AVTransport"
    local soap_info = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:GetMediaInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID></u:GetMediaInfo></s:Body></s:Envelope>]]
    local soap_pos = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID></u:GetPositionInfo></s:Body></s:Envelope>]]

    http.request(url, {method="POST", body=soap_info, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:AVTransport:1#GetMediaInfo"', ["Content-Type"]="text/xml"}}, function(res, err)
        if not err and res.body then
            device:set_state("TRACK_TITLE", res.body:match("<dc:title>(.-)</dc:title>") or "Naim Core")
            device:set_state("TRACK_ARTIST", res.body:match("<upnp:artist>(.-)</upnp:artist>") or "WAV CD")
            device:set_state("TRACK_DURATION", to_seconds(res.body:match("<Duration>(.-)</Duration>")))
            local art = res.body:match("<upnp:albumArtURI>(.-)</upnp:albumArtURI>")
            if art then device:set_state("ALBUM_ART_URL", (art:sub(1,4)=="http") and art or "http://"..CORE_IP..":"..port..art) end
        end
    end)

    http.request(url, {method="POST", body=soap_pos, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:AVTransport:1#GetPositionInfo"', ["Content-Type"]="text/xml"}}, function(res, err)
        if not err and res.body then
            device:set_state("TRACK_PROGRESS", to_seconds(res.body:match("<RelTime>(.-)</RelTime>")))
        end
    end)
end

-- 7. COMMAND EXECUTIONS
function on_resource_command(res_id, cmd_id, params)
    local primary_core = get_primary_core()

    if cmd_id == "run_diagnostics" then
        print("🛠️ Manual Diagnostic Run Triggered via UI...")
        run_full_system_test()

    elseif cmd_id == "set_volume" then
        local requested_vol = params.volume or 0
        local safe_vol = math.min(requested_vol, SAFE_VOL_LIMIT)
        device:set_state("VOLUME", safe_vol)
        sync_topping_volume(safe_vol) 
  
    elseif res_id == "source_selector" then
        CURRENT_SOURCE = params.value
        reset_a90_hardware()
        
        if params.value == "Naim Core" then
            wake_a90()
            send_ir(IR_A90_XLR)
            print("⚡ Waking Naim Core (Source Selected)...")
            http.request("http://" .. CORE_IP .. ":15081/power?system=on", {method="PUT"})
            
            local current_state = device:get_state("TRANSPORT_STATE") or "STOPPED"
            if current_state == "PAUSED" then
                http.get("http://"..CORE_IP..":15081/nowplaying?cmd=resume")
            end
        elseif params.value == "B&O Streaming" then
            wake_a90()
            send_ir(IR_A90_XLR)
            engine.fire(primary_core .. "/Select source?Connector=&Origin=local&Source Type=MUSIC", {})
        elseif params.value == "Beogram Vinyl" then
            wake_a90()
            send_ir(IR_A90_RCA)
            send_ir(IR_BM8000_DATALINK_PHONO_ON)
        elseif params.value == "Beocord Tape" then
            wake_a90()
            send_ir(IR_A90_RCA)
            send_ir(IR_BM8000_DATALINK_TAPE_ON)
        elseif params.value == "FM Radio" then
            wake_a90()
            send_ir(IR_A90_RCA)
            send_ir(IR_BM8000_RADIO)
        end

    elseif cmd_id == "next" or cmd_id == "search_fwd" then
        if CURRENT_SOURCE == "Naim Core" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=next")
        elseif CURRENT_SOURCE == "B&O Streaming" then engine.fire(primary_core .. "/Send command?Command=NEXT&Continue type=short_press", {}) 
        elseif CURRENT_SOURCE == "Beogram Vinyl" or CURRENT_SOURCE == "Beocord Tape" then send_ir(IR_BM8000_SCAN_UP)
        elseif CURRENT_SOURCE == "FM Radio" then
            CURRENT_FM_PRESET = CURRENT_FM_PRESET + 1
            if CURRENT_FM_PRESET > 9 then CURRENT_FM_PRESET = 1 end
            send_ir(IR_BM8000_KEYS["P"..CURRENT_FM_PRESET])
        end
    
    elseif cmd_id == "prev" or cmd_id == "search_rew" then
        if CURRENT_SOURCE == "Naim Core" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=prev")
        elseif CURRENT_SOURCE == "B&O Streaming" then engine.fire(primary_core .. "/Send command?Command=PREV&Continue type=short_press", {}) 
        elseif CURRENT_SOURCE == "Beogram Vinyl" or CURRENT_SOURCE == "Beocord Tape" then send_ir(IR_BM8000_SCAN_DN)
        elseif CURRENT_SOURCE == "FM Radio" then
            CURRENT_FM_PRESET = CURRENT_FM_PRESET - 1
            if CURRENT_FM_PRESET < 1 then CURRENT_FM_PRESET = 9 end
            send_ir(IR_BM8000_KEYS["P"..CURRENT_FM_PRESET])
        end

    elseif cmd_id == "NAIM_POWER" then
        local pwr_state = params.state
        if pwr_state == "ON" then
            http.request("http://" .. CORE_IP .. ":15081/power?system=on", {method="PUT"})
        elseif pwr_state == "STANDBY" then
            http.request("http://" .. CORE_IP .. ":15081/power?system=lona", {method="PUT"})
        end

    elseif cmd_id == "SHUFFLE" then
        if CURRENT_SOURCE == "Naim Core" then
            local s_mode = params.mode or "1"
            http.request("http://" .. CORE_IP .. ":15081/nowplaying?shuffle=" .. s_mode, {method="PUT"})
        end

    elseif cmd_id == "REPEAT" then
        if CURRENT_SOURCE == "Naim Core" then
            local r_mode = params.mode or "2" 
            http.request("http://" .. CORE_IP .. ":15081/nowplaying?repeat=" .. r_mode, {method="PUT"})
        end
        
    elseif cmd_id == "step_fwd" then send_ir(IR_BM8000_FINE_UP)
    elseif cmd_id == "step_rev" then send_ir(IR_BM8000_FINE_DN)

    elseif cmd_id == "play" then
        if CURRENT_SOURCE == "Naim Core" then 
            http.request("http://" .. CORE_IP .. ":15081/power?system=on", {method="PUT"})
            local current_state = device:get_state("TRANSPORT_STATE") or "STOPPED"
            if current_state == "PAUSED" then
                http.get("http://"..CORE_IP..":15081/nowplaying?cmd=resume")
            else
                http.get("http://"..CORE_IP..":15081/nowplaying?cmd=play")
            end
        elseif CURRENT_SOURCE == "B&O Streaming" then 
            engine.fire(primary_core .. "/Send command?Command=PLAY&Continue type=short_press", {})
        elseif CURRENT_SOURCE == "Beocord Tape" then 
            send_ir(IR_BM8000_DATALINK_TAPE_ON) 
        end
        
    elseif cmd_id == "pause" or cmd_id == "stop" then
        if CURRENT_SOURCE == "Naim Core" then 
            http.get("http://"..CORE_IP..":15081/nowplaying?cmd=pause")
        elseif CURRENT_SOURCE == "B&O Streaming" then 
            engine.fire(primary_core .. "/Send command?Command=PAUSE&Continue type=short_press", {})
        elseif CURRENT_SOURCE == "Beocord Tape" or CURRENT_SOURCE == "Beogram Vinyl" or CURRENT_SOURCE == "FM Radio" then 
            send_ir(IR_BM8000_STOP) 
        end
        
    elseif cmd_id == "play_pause_toggle" then
        if CURRENT_SOURCE == "Naim Core" then
            local current_state = device:get_state("TRANSPORT_STATE") or "STOPPED"
            if current_state == "PLAYING" then
                http.get("http://"..CORE_IP..":15081/nowplaying?cmd=pause")
            else
                http.request("http://" .. CORE_IP .. ":15081/power?system=on", {method="PUT"})
                http.get("http://"..CORE_IP..":15081/nowplaying?cmd=resume")
            end
        end

    elseif cmd_id == "mute" then
        print("🔇 Toggling Mute via Topping A90...")
        wake_a90()
        send_ir(IR_A90_MUTE)
        -- Quick UI state toggle based on current state (Note: Topping lacks true discrete Mute ON/OFF)
        local current_mute = device:get_state("MUTE") or false
        device:set_state("MUTE", not current_mute)

    elseif cmd_id == "a90_power" then
        print("⚡ Toggling Topping A90 Power...")
        wake_a90()
        send_ir(IR_A90_POWER)

    elseif cmd_id == "d90_fir" then
        print("🎛️ Toggling D90 FIR Filter...")
        send_ir(IR_D90_FIR)
    elseif cmd_id == "d90_input_next" then
        print("➡️ Manually skipping D90 Input...")
        send_ir(IR_D90_ARROW_RIGHT)
    elseif cmd_id == "d90_input_prev" then
        print("⬅️ Manually reversing D90 Input...")
        send_ir(IR_D90_ARROW_LEFT)

    elseif res_id == "a90_gain" then 
        wake_a90()
        send_ir(IR_A90_GAIN_TOGGLE) 
    elseif res_id == "a90_output" then 
        wake_a90()
        send_ir(IR_A90_OUTPUT_TOGGLE) 
    
    -- BEOMASTER 8000 DROPDOWN SELECTOR LOGIC
    elseif res_id == "bm8000_presets" then
        local preset_id = params.value 
        local ir_payload = IR_BM8000_KEYS[preset_id]
        if ir_payload then
            local p_num = tonumber(preset_id:match("%d"))
            if p_num and p_num >= 1 and p_num <= 9 then CURRENT_FM_PRESET = p_num end
            if preset_id == "P0" then CURRENT_FM_PRESET = 10 end
            
            -- Pulls the custom name you set in the Parameters to print nicely in the log
            local user_label = device:get_data(string.lower(preset_id) .. "_label") or preset_id
            print("📻 BM8000: Tuning to " .. user_label .. " (" .. preset_id .. ")")
            
            send_ir(ir_payload)
        end
        
    elseif res_id == "bm8000_filter" then send_ir(IR_BM8000_FILTER)

    elseif cmd_id == "play_bo_playlist" then
        local tidal_url = device:get_resource_data(res_id, "playlist_address")
        if CURRENT_SOURCE == "B&O Streaming" then
            engine.fire(primary_core .. "/Play URI?URI=" .. tostring(tidal_url), {})
        end

    elseif res_id == "party_mode" then
        if cmd_id == "set" then
            local is_active = (params.state == true or params.state == "ON" or params.state == "on")
            local party_zones = get_party_zones() 
            if is_active then
                if CURRENT_SOURCE == "Naim Core" then
                    engine.fire(primary_core .. "/Select source?Connector=&Origin=local&Source Type=LINE_IN", {})
                    os.sleep(1) 
                end
                for _, z in ipairs(party_zones) do engine.fire(z .. "/Send command?Command=JOIN", {}) end
            else
                for _, z in ipairs(party_zones) do engine.fire(z .. "/Send command?Command=STANDBY", {}) end
                if CURRENT_SOURCE == "Naim Core" then engine.fire(primary_core .. "/Send command?Command=STANDBY", {}) end
            end
        end
    end 
end 

-- 8. DISCOVERY PORT MAPPING
function discover_upnp_port()
    local msearch = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nST: urn:schemas-upnp-org:service:AVTransport:1\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\n\r\n"
    local socket = udp.new()
    socket:sendto(msearch, "239.255.255.250", 1900)
    socket:receive(function(data, ip)
        if data and ip == CORE_IP then
            local p = data:match(":(%d+)/")
            if p then device:set_data("upnp_port", p) end
        end
    end)
end

-- 9. DIAGNOSTIC TEST BLOCK
function run_full_system_test()
    print("--- 🚀 STARTING FULL HYBRID SYSTEM DIAGNOSTICS ---")

    http.get("http://" .. CORE_IP .. ":15081/nowplaying", function(res, err)
        if not err then print("✅ PASS: Naim REST API (Port 15081) is responding.")
        else print("❌ FAIL: Naim REST API unreachable. Check Power/Network.") end
    end)

    local upnp_port = device:get_data("upnp_port") or "16000"
    http.get("http://" .. CORE_IP .. ":" .. upnp_port .. "/xml/AVTransport", function(res, err)
        if not err then print("✅ PASS: Naim WAV Metadata (Port " .. upnp_port .. ") is active.")
        else print("❌ FAIL: UPnP Port not discovered. SSDP might be blocked.") end
    end)

    local ITACH_IP = get_itach_ip()
    local client = tcp.new()
    client:connect(ITACH_IP, 4998, function(res, err)
        if not err then print("✅ PASS: Global Caché iTach (" .. ITACH_IP .. ") is online.") client:close()
        else print("❌ FAIL: iTach unreachable. Check IP in BLI Resource Data.") end
    end)

    local primary_core = get_primary_core()
    if engine.resource(primary_core) then print("✅ PASS: Primary Core found at: " .. primary_core)
    else print("⚠️ WARNING: Primary Core not found. Check parameter path: " .. primary_core) end

    local party_zones = get_party_zones()
    if #party_zones == 0 then
        print("⚠️ WARNING: No secondary Party Zones configured in BLI parameters.")
    else
        for _, z in ipairs(party_zones) do
            if engine.resource(z) then print("✅ PASS: Secondary Zone found at: " .. z)
            else print("⚠️ WARNING: Secondary Zone not found. Check parameter path: " .. z) end
        end
    end
    print("--- 🏁 DIAGNOSTICS COMPLETE ---")
end
