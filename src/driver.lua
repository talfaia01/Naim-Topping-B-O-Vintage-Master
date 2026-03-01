local http = require("http")
local json = require("json")
local udp = require("udp")
local tcp = require("tcp")

-- 1. CONFIGURATION & STATE TRACKING
local CORE_IP = device.address 
local ITACH_IP = device:get_data("itach_ip") or "192.168.77.XXX"
local SAFE_VOL_LIMIT = 60
local LAST_KNOWN_VOL = 0 
local CURRENT_SOURCE = ""
local error_count = 0
-- Naim Playlist IDs (Audit via Naim device IP)
local favorites_map = { ["Hi-Res Jazz"] = 12, ["Recently Added"] = 45, ["Classic Rock"] = 7 }

-- 2. IR COMMAND LIBRARY (Global Caché Format)
-- Topping D90 (38kHz)
local IR_D90_AES = "sendir,1:1,1,38000,1,1,342,171...[D90 AES]"
local IR_D90_OPT = "sendir,1:1,1,38000,1,1,342,171...[D90 OPT]"
-- Topping A90 (38kHz)
local IR_A90_XLR = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_RCA = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_VOL_UP = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_VOL_DOWN = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_GAIN_TOGGLE = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,21,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,64,21,64,21,64,21,1514"
local IR_A90_OUTPUT_TOGGLE = "sendir,1:2,1,38000,1,1,342,171,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,21,21,64,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,21,21,64,21,21,21,21,21,21,21,21,21,21,21,64,21,21,21,64,21,64,21,64,21,64,21,64,21,64,21,1514"
-- Beomaster 8000 (455kHz on Port 3)
local IR_BM8000_PH = "sendir,1:3,1,455000,1,1,15,15,31,47,15,15,15,15,15,15,15,47,15,15,15,3500"
local IR_BM8000_TP = "sendir,1:3,1,455000,1,1,15,15,31,47,15,15,15,15,15,15,15,15,15,47,15,3500"
local IR_BM8000_RADIO = "sendir,1:3,1,455000,1,1,15,15,31,47,15,15,15,15,15,31,15,15,15,47,15,3500"

-- 3. LIFECYCLE
function on_init()
    print("Naim-Topping Master Driver v3.2.0 Starting...")
    discover_upnp_port()
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
    local client = tcp.new()
    client:connect(ITACH_IP, 4998, function(res, err)
        if not err then client:send(payload .. "\r") client:close() end
    end)
end

function sync_topping_volume(target_vol) -- 'target_vol' is defined here as the argument
    local diff = target_vol - LAST_KNOWN_VOL
    if diff == 0 then return end -- No movement needed
    local cmd = ""
    if diff > 0 then
        cmd = IR_A90_VOL_UP
    else
        cmd = IR_A90_VOL_DOWN
    end
    -- Loop the IR pulses based on the difference
    for i = 1, math.abs(diff) do
        send_ir(cmd)
        -- 40ms delay to let the A90 Discrete relays click safely
        os.sleep(0.04) 
    end
    -- Update our internal tracker so the next move is accurate
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

    if cmd_id == "play" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=play")
    elseif cmd_id == "pause" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=pause")
    elseif cmd_id == "next" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=next")
    elseif cmd_id == "prev" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=prev")

    elseif cmd_id == "set_volume" then
        -- We take the value directly from the BLI 'params'
        local requested_vol = params.volume or 0
        -- Apply the Safety Hook
        local safe_vol = math.min(requested_vol, SAFE_VOL_LIMIT)
        -- Update the BLI State UI
        device:set_state("VOLUME", safe_vol)
        -- Pass the safe volume to the IR Sync Engine
        sync_topping_volume(safe_vol)
  
    elseif res_id == "source_selector" then
        reset_a90_hardware()
        -- Proceed with Naim or Vintage selection...
        elseif params.value == "Naim Core" or params.value == "B&O Streaming" then
          -- Digital Stack uses the XLR input on the A90
          send_ir(IR_A90_XLR)
            if params.value == "Naim Core" then send_ir(IR_D90_AES)
            elseif params.value == "B&O Streaming" then send_ir(IR_D90_OPT) end
        elseif params.value == "Beogram Vinyl" or params.value == "Beocord Tape" or params.value == "FM Radio" then
          -- Vintage Stack uses the RCA input on the A90
          send_ir(IR_A90_XLR)
            if params.value == "Beogram Vinyl" then send_ir(IR_BM8000_PH)
            elseif params.value == "Beocord Tape" then send_ir(IR_BM8000_TP)
            elseif params.value == "FM Radio" then send_ir(IR_BM8000_RADIO) end
        
        elseif res_id == "playlist_selector" then
            local id = favorites_map[params.value]
            if id then http.get("http://"..CORE_IP..":15081/favourites/"..id.."?cmd=play") end

        elseif cmd_id == "browse" then
            local soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>]]..(params.container_id or "0")..[[</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body></s:Envelope>]]
            http.request(url, {method="POST", body=soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:AVTransport:1#Browse"', ["Content-Type"]="text/xml"}}, function(res) device:send_content_results(res.body) end)

        elseif cmd_id == "search" then
            local url = "http://" .. CORE_IP .. ":" .. port .. "/xml/ContentDirectory"
            -- The SearchCriteria must be properly escaped for XML
            local criteria = 'dc:title contains "' .. (params.query or "") .. '" or upnp:artist contains "' .. (params.query or "") .. '"'
            local soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:Search xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ContainerID>0</ContainerID><SearchCriteria>]]..criteria..[[</SearchCriteria><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria></u:Search></s:Body></s:Envelope>]]
            http.request(url, {method="POST", body=soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:ContentDirectory:1#Search"', ["Content-Type"]="text/xml"}}, function(res) device:send_content_results(res.body) end)
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

-- 6. DIAGNOSTIC SCRIPT BLOCK
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
        -- We check if the resource exists in the BLI engine
        if engine.resource(r .. "/BS_Core") then
            print("✅ PASS: " .. r .. " Core found in BLI network.")
        else
            print("⚠️ WARNING: " .. r .. " Core not found. Check system naming.")
        end
    end
    
    print("--- 🏁 DIAGNOSTICS COMPLETE ---")
end

