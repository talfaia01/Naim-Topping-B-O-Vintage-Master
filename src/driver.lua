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
local IR_D90_AES = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_D90_OPT = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_XLR = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_RCA = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_VOL_UP = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_VOL_DOWN = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_GAIN_TOGGLE = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_OUTPUT_TOGGLE = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"

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
    print("Naim-Topping Master Driver v3.4.0 Starting...")
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

-- 7. COMMAND EXECUTIONS
function on_resource_command(res_id, cmd_id, params)
    local port = device:get_data("upnp_port") or "16000"
    local url = "http://" .. CORE_IP .. ":" .. port .. "/xml/ContentDirectory"
    local primary_core = get_primary_core()

    -- ON-DEMAND DIAGNOSTICS
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
            send_ir(IR_A90_XLR)
            send_ir(IR_D90_AES)
            http.get("http://"..CORE_IP..":15081/nowplaying?cmd=play")
        elseif params.value == "B&O Streaming" then
            send_ir(IR_A90_XLR)
            send_ir(IR_D90_OPT)
            engine.fire(primary_core .. "/Select source?Connector=&Origin=local&Source Type=MUSIC", {})
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
            engine.fire(primary_core .. "/Send command?Command=NEXT&Continue type=short_press", {}) 
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
            engine.fire(primary_core .. "/Send command?Command=PREV&Continue type=short_press", {}) 
        elseif CURRENT_SOURCE == "Beogram Vinyl" or CURRENT_SOURCE == "Beocord Tape" then
            send_ir(IR_BM8000_SCAN_DN)
        elseif CURRENT_SOURCE == "FM Radio" then
            CURRENT_FM_PRESET = CURRENT_FM_PRESET - 1
            if CURRENT_FM_PRESET < 1 then CURRENT_FM_PRESET = 9 end
            local target_preset = "P" .. CURRENT_FM_PRESET
            print("FM Radio: Scanning Backward to " .. target_preset)
            send_ir(IR_BM8000_KEYS[target_preset])
        end

    -- TUNING BRIDGE (BM8000 Settings)
    elseif cmd_id == "step_fwd" then send_ir(IR_BM8000_FINE_UP)
    elseif cmd_id == "step_rev" then send_ir(IR_BM8000_FINE_DN)

    -- PLAY/PAUSE
    elseif cmd_id == "play" then
        if CURRENT_SOURCE == "Naim Core" then 
            http.get("http://"..CORE_IP..":15081/nowplaying?cmd=play")
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
        
    -- TOPPING/BM8000 SELECTORS
    elseif res_id == "a90_gain" then send_ir(IR_A90_GAIN_TOGGLE) 
    elseif res_id == "a90_output" then send_ir(IR_A90_OUTPUT_TOGGLE) 
    
    elseif res_id == "bm8000_presets" then
        local preset_id = params.value 
        local ir_payload = IR_BM8000_KEYS[preset_id]
        if ir_payload then
            local p_num = tonumber(preset_id:match("%d"))
            if p_num and p_num >= 1 and p_num <= 9 then CURRENT_FM_PRESET = p_num end
            local user_label = device:get_data(string.lower(preset_id) .. "_label") or preset_id
            print("BM8000: Tuning to " .. user_label .. " (" .. preset_id .. ")")
            send_ir(ir_payload)
        else
            print("⚠️ ERROR: Preset not mapped.")
        end
        
    elseif res_id == "bm8000_filter" then send_ir(IR_BM8000_FILTER)
    
    -- DYNAMIC PLAYLISTS
    elseif cmd_id == "play_naim_playlist" then
        local pl_address = device:get_resource_data(res_id, "playlist_address")
        if CURRENT_SOURCE == "Naim Core" then
            print("▶️ Playing Naim Playlist ID: " .. tostring(pl_address))
            http.get("http://"..CORE_IP..":15081/favourites/" .. pl_address .. "?cmd=play")
        else
            print("⚠️ Ignored: Naim Playlists are only accessible when the 'Naim Core' source is active.")
        end

    elseif cmd_id == "play_bo_playlist" then
        local tidal_url = device:get_resource_data(res_id, "playlist_address")
        if CURRENT_SOURCE == "B&O Streaming" then
            print("▶️ Playing B&O Playlist: " .. tostring(tidal_url))
            engine.fire(primary_core .. "/Play URI?URI=" .. tostring(tidal_url), {})
        else
            print("⚠️ Ignored: B&O Playlists are only accessible when the 'B&O Streaming' source is active.")
        end

    -- BROWSE & SEARCH
    elseif cmd_id == "browse" then
        local soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>]]..(params.container_id or "0")..[[</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body></s:Envelope>]]
        http.request(url, {method="POST", body=soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"', ["Content-Type"]="text/xml"}}, function(res) device:send_content_results(res.body) end)

    elseif cmd_id == "search" then
        local criteria = 'dc:title contains "' .. (params.query or "") .. '" or upnp:artist contains "' .. (params.query or "") .. '"'
        local soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:Search xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ContainerID>0</ContainerID><SearchCriteria>]]..criteria..[[</SearchCriteria><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria></u:Search></s:Body></s:Envelope>]]
        http.request(url, {method="POST", body=soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:ContentDirectory:1#Search"', ["Content-Type"]="text/xml"}}, function(res) device:send_content_results(res.body) end)
    
    -- HOUSE PARTY MODE
    elseif res_id == "party_mode" then
        if cmd_id == "set" then
            local is_active = (params.state == true or params.state == "ON" or params.state == "on")
            local party_zones = get_party_zones() 
            
            if is_active then
                if CURRENT_SOURCE == "Naim Core" then
                    print("🎉 House Party Mode ON: Activating Line-In Broadcast for Naim...")
                    engine.fire(primary_core .. "/Select source?Connector=&Origin=local&Source Type=LINE_IN", {})
                    os.sleep(1) 
                else
                    print("🎉 House Party Mode ON: Distributing native Beolink stream...")
                end
                
                print("📡 Distributing to secondary zones...")
                for _, z in ipairs(party_zones) do
                    engine.fire(z .. "/Send command?Command=JOIN", {})
                end
            else
                print("🛑 House Party Mode OFF: Isolating Living Room...")
                for _, z in ipairs(party_zones) do
                    engine.fire(z .. "/Send command?Command=STANDBY", {})
                end
                
                if CURRENT_SOURCE == "Naim Core" then
                    engine.fire(primary_core .. "/Send command?Command=STANDBY", {})
                end
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

-- 9. RESOURCE CAPTURE (Dynamic Naim Playlists)
function discover_resources()
    print("🔍 Discovering Naim Playlists...")
    local url = "http://" .. CORE_IP .. ":15081/favourites"
    
    http.get(url, function(res, err)
        if not err and res.body then
            local status, data = pcall(json.decode, res.body)
            if status and type(data) == "table" then
                for _, item in ipairs(data) do
                    local id = tostring(item.id or "")
                    local name = item.title or item.name or ("Naim Playlist " .. id) 
                    
                    if id ~= "" then
                        device:add_discovered_resource("naim_playlist", "naim_" .. id, name, { playlist_address = id })
                    end
                end
                print("✅ Discovery Complete: Found " .. #data .. " playlists.")
            end
        else
            print("❌ Discovery failed: Naim Core unreachable on port 15081.")
        end
    end)
end

-- 10. DIAGNOSTIC TEST BLOCK
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
