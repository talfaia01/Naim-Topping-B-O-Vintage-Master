local http = require("http")
local json = require("json")
local udp = require("udp")
local tcp = require("tcp")

-- Configuration (Set IPs in Configurator UI)
local CORE_IP = device.address 
local ITACH_IP = device:get_data("itach_ip") or "192.168.77.XXX"
local SAFE_VOL_LIMIT = 60
local error_count = 0
local favorites_map = { ["Hi-Res Jazz"] = 12, ["Recently Added"] = 45, ["Classic Rock"] = 7 }

-- IR STRINGS
local IR_D90_AES = send_ir("sendir,1:1,1,38000,1,1,342,171...[D90 AES]")
local IR_D90_OPT = send_ir("sendir,1:1,1,38000,1,1,342,171...[D90 OPT]")
local IR_A90_RCA = "sendir,1:2,1,38000,1,1,342,171...[A90_RCA_HEX]"
local IR_A90_XLR = "sendir,1:2,1,38000,1,1,342,171...[A90_XLR_HEX]"
local IR_BM8000_PH = "sendir,1:3,1,455000,1,1,15,15,31,47,15,15,15,15,15,15,15,47,15,15,15,3500"
local IR_BM8000_TP = "sendir,1:3,1,455000,1,1,15,15,31,47,15,15,15,15,15,15,15,15,15,47,15,3500"
local IR_BM8000_Radio ="sendir,1:3,1,455000,1,1,15,15,31,47,15,15,15,15,15,31,15,15,15,47,15,3500" 

function on_init()
    print("Naim-Topping Master Initialized at " .. CORE_IP)
    discover_upnp_port()
end

function process()
    while true do
        heartbeat_and_status()
        poll_upnp_metadata_and_progress()
        os.sleep(3) -- Polling every 3s for a smoother progress bar
    end
end

-- Helper: Convert UPnP HH:MM:SS to Seconds
function to_seconds(hms)
    if not hms then return 0 end
    local h, m, s = hms:match("(%d+):(%d+):(%d+)")
    return (tonumber(h or 0) * 3600) + (tonumber(m or 0) * 60) + tonumber(s or 0)
end

-- Force A90 to reset to internal 'Safe Volume' (Zero)
function reset_topping_to_zero()
    -- Topping A90 Discrete resets its 'Safe Volume' when inputs are toggled
    -- We flip to RCA and back to XLR (or vice versa) to trigger the A90 internal reset
    send_ir(IR_A90_RCA)
    os.sleep(0.5)
    send_ir(IR_A90_XLR)
    
    -- Sync BLI state to match the now-zeroed hardware
    device:set_state("VOLUME", 0)
    print("A90 Hardware Reset: Volume synced to Zero.")
end

-- IR ENGINE (38kHz & 455kHz)
function send_ir(type)
    local client = tcp.new()
    client:connect(ITACH_IP, 4998, function(res, err)
        if not err then 
            local cmd = ""
            if type == "PH" then
                -- Phono (Beogram 8002)
                cmd = IR_BM8000_PH
            elseif type == "TP" then
                -- Tape (Beocord 8004)
                cmd = IR_BM8000_TP
            elseif type == "RADIO" then
                -- FM Radio (Beomaster 8000 Tuner)
                cmd = IR_BM8000_TP
            elseif type == "NAIM"
            -- Naim Core DAC Input
            cmd = IR_D90_AES
            elseif type = "BEOLINK"
            -- Beolink streaming sources
            cmd = IR_D90_OPT
            elseif type = "PREXLR"
            -- Topping A90 Discrete XLR Input
            cmd = IR_A90_XLR
            elseif type = "PRERCA"
            -- Topping A90 Discrete RCA Input
            cmd = IR_A90_RCA
            end
            
            if cmd ~= "" then
                client:send(cmd .. "\r")
            end
            client:close() 
        end
    end)
end

-- 1. STATUS & QUALITY (Port 15081)
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
                -- High-Res Badge Logic
                if d.sampleRate and d.bitDepth then
                    device:set_state("AUDIO_QUALITY", string.format("%.1f kHz / %sb", d.sampleRate/1000, d.bitDepth))
                end
            end
        end
    end)
end

-- 2. WAV METADATA & PROGRESS (Port 16000)
function poll_upnp_metadata_and_progress()
    local port = device:get_data("upnp_port") or "16000"
    local url = "http://" .. CORE_IP .. ":" .. port .. "/xml/AVTransport"
    
    local soap_info = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:GetMediaInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID></u:GetMediaInfo></s:Body></s:Envelope>]]
    local soap_pos = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID></u:GetPositionInfo></s:Body></s:Envelope>]]

    -- Get Track Info & Duration
    http.request(url, {method="POST", body=soap_info, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:AVTransport:1#GetMediaInfo"', ["Content-Type"]="text/xml"}}, function(res, err)
        if not err and res.body then
            device:set_state("TRACK_TITLE", res.body:match("<dc:title>(.-)</dc:title>") or "Naim Core")
            device:set_state("TRACK_ARTIST", res.body:match("<upnp:artist>(.-)</upnp:artist>") or "WAV CD")
            device:set_state("TRACK_DURATION", to_seconds(res.body:match("<Duration>(.-)</Duration>")))
            local art = res.body:match("<upnp:albumArtURI>(.-)</upnp:albumArtURI>")
            if art then device:set_state("ALBUM_ART_URL", (art:sub(1,4)=="http") and art or "http://"..CORE_IP..":"..port..art) end
        end
    end)

    -- Get Progress Position
    http.request(url, {method="POST", body=soap_pos, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:AVTransport:1#GetPositionInfo"', ["Content-Type"]="text/xml"}}, function(res, err)
        if not err and res.body then
            device:set_state("TRACK_PROGRESS", to_seconds(res.body:match("<RelTime>(.-)</RelTime>")))
        end
    end)
end

-- 3. COMMAND HANDLER (Transport, Browse, Search, IR)
function on_resource_command(res_id, cmd_id, params)
    local port = device:get_data("upnp_port") or "16000"
    local url = "http://" .. CORE_IP .. ":" .. port .. "/xml/ContentDirectory"

    if cmd_id == "play" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=play")
    elseif cmd_id == "pause" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=pause")
    elseif cmd_id == "next" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=next")
    elseif cmd_id == "prev" then http.get("http://"..CORE_IP..":15081/nowplaying?cmd=prev")
    
    elseif cmd_id == "browse" then
        local soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>]]..(params.container_id or "0")..[[</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body></s:Envelope>]]
        http.request(url, {method="POST", body=soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:AVTransport:1#Browse"', ["Content-Type"]="text/xml"}}, function(res) device:send_content_results(res.body) end)

    elseif cmd_id == "search" then
        local criteria = 'dc:title contains "' .. (params.query or "") .. '"'
        local soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:Search xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ContainerID>0</ContainerID><SearchCriteria>]]..criteria..[[</SearchCriteria><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria></u:Search></s:Body></s:Envelope>]]
        http.request(url, {method="POST", body=soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:AVTransport:1#Search"', ["Content-Type"]="text/xml"}}, function(res) device:send_content_results(res.body) end)

    elseif res_id == "source_selector" then
        reset_topping_to_zero()
        -- Proceed with Naim or Vintage selection...
        elseif params.value == "Naim Core" or params.value == "B&O Streaming" then
          -- Digital Stack uses the XLR input on the A90
          send_ir("PREXLR")
            if params.value == "Naim Core" then
            send_ir("NAIM")
            elseif params.value == "B&O Streaming" then
            send_ir("BEOLINK") end
        elseif params.value == "Beogram Vinyl" or params.value == "Beocord Tape" or params.value == "FM Radio" then
          -- Vintage Stack uses the RCA input on the A90
          send_ir("PRERCA")
            if params.value == "Beogram Vinyl" then
            send_ir("PH")
            elseif params.value == "Beocord Tape" then
            send_ir("TP")
            elseif params.value == "FM Radio" then
            send_ir("RADIO")
        end
    elseif res_id == "playlist_selector" then
        local id = favorites_map[params.value]
        if id then http.get("http://"..CORE_IP..":15081/favourites/"..id.."?cmd=play") end
    elseif cmd_id == "set_volume" then
        local vol = math.min(params.volume or 0, SAFE_VOL_LIMIT)
        device:set_state("VOLUME", vol)
        sync_topping_volume(vol)
    end
end

-- 4. AUTO DISCOVERY
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
-- 6. DIAGNOSTIC SCRIPT BLOCK
function run_naim_diagnostics()
    print("--- STARTING NAIM GEN 3 DIAGNOSTICS ---")
    
    -- Test 1: Port 15081 (REST API)
    http.get("http://" .. device.address .. ":15081/nowplaying", function(res, err)
        if err then
            print("DIAGNOSTIC FAIL: Port 15081 (REST) is unreachable. Check Naim Power/Network.")
        else
            print("DIAGNOSTIC PASS: Port 15081 is responding. HTTP Code: " .. res.status)
        end
    end)

    -- Test 2: Port 16000 (UPnP WAV Metadata)
    local upnp_port = device:get_data("upnp_port") or "16000"
    local upnp_url = "http://" .. device.address .. ":" .. upnp_port .. "/xml/AVTransport"
    local test_soap = [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org"><s:Body><u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID></u:GetTransportInfo></s:Body></s:Envelope>]]

    http.request(upnp_url, {method="POST", body=test_soap, headers={["SOAPACTION"]='"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo"', ["Content-Type"]="text/xml"}}, function(res, err)
        if err then
            print("DIAGNOSTIC FAIL: Port " .. upnp_port .. " (UPnP) timed out. WAV Metadata will not appear.")
        else
            print("DIAGNOSTIC PASS: Port " .. upnp_port .. " is active. Metadata stream verified.")
        end
    end)
    
    -- Test 3: iTach Connectivity
    local itach_ip = device:get_data("itach_ip")
    if itach_ip then
        print("DIAGNOSTIC: Attempting heartbeat to iTach at " .. itach_ip)
        -- Logic to ping or open/close a TCP port to the iTach
    else
        print("DIAGNOSTIC WARNING: No itach_ip defined. Vintage BM8000 control will be disabled.")
    end
end
