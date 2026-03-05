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
local CURRENT_FM_PRESET = 1 -- FM State Tracker for Next/Prev loops

-- Naim Playlist IDs (Audit via Naim device IP)
local favorites_map = { ["Hi-Res Jazz"] = 12, ["Recently Added"] = 45, ["Classic Rock"] = 7 }

function get_itach_ip()
    local ip = device:get_data("itach_ip")
    return (ip and ip ~= "") and ip or "0.0.0.0"
end

-- 2. IR COMMAND LIBRARY (Global Caché Format)
-- Topping D90 (38kHz)
local IR_D90_AES = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_D90_OPT = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,1514"
-- Topping A90 (38kHz)
local IR_A90_XLR = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_RCA = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_VOL_UP = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_VOL_DOWN = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_GAIN_TOGGLE = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_OUTPUT_TOGGLE = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"

-- Beomaster 8000 (40.983kHz on Port 3)
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

-- 3. LIFECYCLE
function on_init()
    print("Naim-Topping Master Driver v3.3.2 Starting...")
    discover_upnp_port()
    run_full_system_test()
end

function process()
    while true do
        heartbeat_and_status()
        poll_upnp_metadata_and_progress()
        os.sleep(3) -- Smooth progress bar polling
    end
end

-- 4. UTILITIES
function to_seconds(hms)
    if not hms then return 0 end
    local h, m, s = hms:match("(%d+):(%d+):(%d+)")
    return (tonumber(h or 0) * 3600) + (tonumber(m or 0) * 60) + tonumber(s or 0)
end

function send_ir(payload)
    local ITACH_IP = get_itach_ip()
    if ITACH_IP == "0.0.0.0" then return end
    local client = tcp.new()
    client:connect(ITACH_IP, 4998, function(res, err)
        if not err then client:send(payload .. "\r") client:close() end
    end)
end

function sync_topping_volume(target_vol)
    local diff = target_vol - LAST_KNOWN_VOL
    if diff == 0 then return end
    local cmd = ""
    if diff > 0 then
        cmd = IR_A90_VOL_UP
    else
        cmd = IR_A90_VOL_DOWN
    end
    for i = 1, math.abs(diff) do
        send_ir(cmd)
        os.sleep(0.04) 
    end
    LAST_KNOWN_VOL = target_vol
    print("Topping A90 Hardware Synced to: " .. target_vol)
end

function reset_a90_hardware()
    print("CRITICAL: Executing A90 Hardware Volume Sync...")
    send_ir(IR_A90_RCA)
    os.sleep(0.5)
    send_ir(IR_A90_XLR)
    os.sleep(0.5)
    device:set_state("VOLUME", 0)
    LAST_KNOWN_VOL = 0
    print("A90 Hardware Zero Sync Complete. Ready for session.")
end

-- 5. POLLING LOGIC
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
                local state = (d.transportState == "2") and "PLAYING" or (d.transportState == "3" and "PAUSED" or "STOPPED")
                device:set_state("TRANSPORT_STATE", state)
                if d.sampleRate and d.bitDepth then
                    device:set_state("AUDIO_QUALITY", string.format("%.1f kHz / %sb", d.sampleRate/1000, d.bitDepth))
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

-- 6. COMMANDS
function on_resource_command(res_id, cmd_id, params)
    local port = device:get_data("upnp_port") or "16000"
    local url = "http://" .. CORE_IP .. ":" .. port .. "/xml/ContentDirectory"

    if cmd_id == "set_volume" then
        local requested_vol = params.volume or 0
        local safe_vol = math.min(requested_vol, SAFE_VOL_LIMIT)
        device:set_state("VOLUME", safe_vol)
        sync_topping_volume(safe_vol) 
  
    elseif res_id == "source_selector" then
        CURRENT_SOURCE = params.value
        reset_a90_hardware()
        
        if params.value == "Naim Core" then
            send_ir(IR_A90_XLR)
            send_ir(IR_D90_AES)
            http.get("http://"..CORE_IP..":15081/nowplaying?cmd=play")
            
        elseif params.value == "B&O Streaming" then
            send_ir(IR_A90_XLR)
            send_ir(IR_D90_OPT)
            engine.fire("Main/Living Room/AV renderer/BS Core 5/Select source?Connector=&Origin=local&Source Type=MUSIC", {})
            
        elseif params.value == "Beogram Vinyl" then
            send_ir(IR_A90_RCA)
            send_ir(IR_BM8000_DATALINK_PHONO_ON)
            
        elseif params.value == "Beocord Tape" then
            send_ir(IR_A90_RCA)
            send_ir(IR_BM8000_DATALINK_TAPE_ON)
            
        elseif params.value == "FM Radio" then
            send_ir(IR_A90_RCA)
            send_ir(IR_BM8000_RADIO)
        end

    -- TUNING BRIDGE (NEXT/SEARCH_FWD)
    elseif cmd_id == "next" or cmd_id == "search_fwd" then
        if CURRENT_SOURCE == "Naim Core" then 
            http.get("http://"..CORE_IP..":15081/nowplaying?cmd=next")
        elseif CURRENT_SOURCE == "B&O Streaming" then 
            engine.fire("Main/Living Room/AV renderer/BS Core 5/Send command?Command=NEXT&Continue type=short_press", {}) 
        elseif CURRENT_SOURCE == "Beogram Vinyl" or CURRENT_SOURCE == "Beocord Tape" then
            send_ir(IR_BM8000_SCAN_UP)
        elseif CURRENT_SOURCE == "FM Radio" then
            CURRENT_FM_PRESET = CURRENT_FM_PRESET + 1
            if CURRENT_FM_PRESET > 9 then CURRENT_FM_PRESET = 1 end
            local target_preset = "P" .. CURRENT_FM_PRESET
            print("FM Radio: Scanning Forward to " .. target_preset)
            send_ir(IR_BM8000_KEYS[target_preset])
        end
    
    -- TUNING BRIDGE (PREV/SEARCH_REW)
    elseif cmd_id == "prev" or cmd_id == "search_rew" then
        if CURRENT_SOURCE == "Naim Core" then 
            http.get("http://"..CORE_IP..":15081/nowplaying?cmd=prev")
        elseif CURRENT_SOURCE == "B&O Streaming" then 
            engine.fire("Main/Living Room/AV renderer/BS Core 5/Send command?Command=PREV&Continue type=short_press", {}) 
        elseif CURRENT_SOURCE == "Beogram Vinyl" or CURRENT_SOURCE == "Beocord Tape" then
            send_ir(IR_BM8000_SCAN_DN)
        elseif CURRENT_SOURCE == "FM Radio" then
            CURRENT_FM_PRESET = CURRENT_FM_PRESET - 1
            if CURRENT_FM_PRESET < 1 then CURRENT_FM_PRESET = 9 end
            local target_preset = "P" .. CURRENT_FM_PRESET
            print("FM Radio: Scanning Backward to " .. target_preset)
            send_ir(IR_BM8000_KEYS[target_preset])
        end

    -- TUNING BRIDGE (BM8000 Ch Balance Settings)
    elseif cmd_id == "step_fwd" then send_ir(IR_BM8000_FINE_UP)
    elseif cmd_id == "step_rev" then send_ir(IR_BM8000_FINE_DN)

    -- PLAY/PAUSE
    elseif cmd_id == "play" then
        if CURRENT_SOURCE == "Naim Core" then 
            http.get("http://"..CORE_IP..":15081/nowplaying?cmd=play")
        elseif CURRENT_SOURCE == "B&O Streaming" then 
            engine.fire("Main/Living Room/AV renderer/BS Core 5/Send command?Command=PLAY&Continue type=short_press", {})
        elseif CURRENT_SOURCE == "Beocord Tape" then 
            send_ir(IR_BM8000_DATALINK_TAPE_ON) 
        end
        
    elseif cmd_id == "pause" or cmd_id == "stop" then
        if CURRENT_SOURCE == "Naim Core" then 
            http.get("http://"..CORE_IP..":15081/nowplaying?cmd=pause")
        elseif CURRENT_SOURCE == "B&O Streaming" then 
            engine.fire("Main/Living Room/AV renderer/BS Core 5/Send command?Command=PAUSE&Continue type=short_press", {})
        elseif CURRENT_SOURCE == "Beocord Tape" or CURRENT_SOURCE == "Beogram Vinyl" or CURRENT_SOURCE == "FM Radio" then 
            send_ir(IR_BM8000_STOP) 
        end
        
    -- TOPPING/BM8000 SELECTORS
    elseif res_id == "a90_gain" then send_ir(IR_A90_GAIN_TOGGLE) 
    elseif res_id == "a90_output" then send_ir(IR_A90_OUTPUT_TOGGLE) 
    
    elseif res_id == "bm8000_presets" then
        local preset_id = params.value 
        local ir_payload = IR_BM8000_KEYS[preset_id]
        if ir_payload then
            local p_num = tonumber(preset_id:match("%d"))
            if p_num and p_num >= 1 and p_num <= 9 then
                CURRENT_FM_PRESET = p_num
            end
            local user_label = device:get_data(string.lower(preset_id) .. "_label") or preset_id
            print("BM8000: Tuning to " .. user_label .. " (" .. preset_id .. ")")
            send_ir(ir_payload)
        else
            print("⚠️ ERROR: Preset " .. (params.value or "nil") .. " not mapped.")
        end
        
    elseif res_id == "bm8000_filter" then 
        send_ir(IR_BM8000_FILTER)
    
    elseif res_id == "playlist_selector" then
        local id = favorites_map[params.value]
        if id then http.get("http://"..CORE_IP..":15081/favourites/"..id.."?cmd=play") end

    elseif cmd_id == "browse" then
        local soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>]]..(params.container_id or "0")..[[</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body></s:Envelope>]]
        -- FIXED: Changed AVTransport to ContentDirectory in the SOAPACTION header
        http.request(url, {method="POST", body=soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"', ["Content-Type"]="text/xml"}}, function(res) device:send_content_results(res.body) end)

    elseif cmd_id == "search" then
        local criteria = 'dc:title contains "' .. (params.query or "") .. '" or upnp:artist contains "' .. (params.query or "") .. '"'
        local soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:Search xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ContainerID>0</ContainerID><SearchCriteria>]]..criteria..[[</SearchCriteria><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria></u:Search></s:Body></s:Envelope>]]
        http.request(url, {method="POST", body=soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:ContentDirectory:1#Search"', ["Content-Type"]="text/xml"}}, function(res) device:send_content_results(res.body) end)
    
-- HOUSE PARTY MODE
    elseif res_id == "party_mode" then
        if cmd_id == "set" then
            -- SAFETY FIX: Explicitly check for both boolean and string "ON" states from the BLI
            local is_active = (params.state == true or params.state == "ON" or params.state == "on")
            local rooms = {"Kitchen", "Bedroom", "Office", "Theater", "Family"}
            
            if is_active then
                if CURRENT_SOURCE == "Naim Core" then
                    print("🎉 House Party Mode ON: Activating Line-In Broadcast for Naim...")
                    -- 1. Force the Living Room Core to open its Line-In
                    engine.fire("Main/Living Room/AV renderer/BS Core 5/Select source?Connector=&Origin=local&Source Type=LINE_IN", {})
                    -- Give the Beosound Core 1 second to establish the broadcast stream
                    os.sleep(1) 
                else
                    print("🎉 House Party Mode ON: Distributing native Beolink stream...")
                    -- If B&O Streaming (or another source) is active, do nothing to the Living Room Core. 
                    -- It is already the active source on the Network Link.
                end
                
                print("📡 Distributing to secondary zones...")
                for _, r in ipairs(rooms) do
                    -- 2. Fire the 'Join' command to each secondary Core
                    engine.fire(r .. "/AV renderer/BS_Core/Send command?Command=JOIN", {})
                end
            else
                print("🛑 House Party Mode OFF: Isolating Living Room...")
                
                for _, r in ipairs(rooms) do
                    -- Drop the secondary rooms by putting them in Standby
                    engine.fire(r .. "/AV renderer/BS_Core/Send command?Command=STANDBY", {})
                end
                
                -- Only stop the Living Room Core's broadcast if it was acting as a dummy loop for the Naim.
                -- If we are on B&O Streaming, we want the Living Room music to keep playing!
                if CURRENT_SOURCE == "Naim Core" then
                    engine.fire("Main/Living Room/AV renderer/BS Core 5/Send command?Command=STANDBY", {})
                end
            end
        end
    end 

end 

-- 7. DISCOVERY
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

-- 8. DIAGNOSTIC SCRIPT BLOCK
function run_full_system_test()
    print("--- 🚀 STARTING FULL HYBRID SYSTEM DIAGNOSTICS ---")

    -- 1. Verify Naim Connectivity (Transport & Metadata)
    http.get("http://" .. CORE_IP .. ":15081/nowplaying", function(res, err)
        if not err then 
            print("✅ PASS: Naim REST API (Port 15081) is responding.")
        else 
            print("❌ FAIL: Naim REST API unreachable. Check Power/Network.")
        end
    end)

    local upnp_port = device:get_data("upnp_port") or "16000"
    http.get("http://" .. CORE_IP .. ":" .. upnp_port .. "/xml/AVTransport", function(res, err)
        if not err then 
            print("✅ PASS: Naim WAV Metadata (Port " .. upnp_port .. ") is active.")
        else 
            print("❌ FAIL: UPnP Port not discovered. SSDP might be blocked.")
        end
    end)

    -- 2. Verify iTach Connectivity (Preamps & Vintage)
    local ITACH_IP = get_itach_ip()
    local client = tcp.new()
    client:connect(ITACH_IP, 4998, function(res, err)
        if not err then 
            print("✅ PASS: Global Caché iTach (" .. ITACH_IP .. ") is online.")
            client:close()
        else 
            print("❌ FAIL: iTach unreachable. Check IP in BLI Resource Data.")
        end
    end)

    -- 3. Verify B&O Multiroom Names
    local rooms = {"Kitchen", "Bedroom", "Office", "Theater", "Family"}
    for _, r in ipairs(rooms) do
        if engine.resource(r .. "/BS_Core") then
            print("✅ PASS: " .. r .. " Core found in BLI network.")
        else
            print("⚠️ WARNING: " .. r .. " Core not found. Check system naming.")
        end
    end
    
    print("--- 🏁 DIAGNOSTICS COMPLETE ---")
end
