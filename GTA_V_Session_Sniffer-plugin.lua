-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for GTA V Session Sniffer project on GitHub.
-- Allows you to automatically have every usernames showing up on GTA V Session Sniffer project, by logging all players from your sessions to "scripts/GTA_V_Session_Sniffer-plugin/log.txt".
-- Additionally, there's a feature that if you encounter a user flagged as a "Fake Friend" with "Join Timeout" flag, it automatically "Bail/Netsplit" you from the session.
-- GitHub Repository: https://github.com/Illegal-Services/GTA_V_Session_Sniffer-plugin-2Take1-Lua


-- Globals START
---- Global constants 1/2 START
local SCRIPT_NAME <const> = "GTA_V_Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "GTA V Session Sniffer"
local LOG_PATH <const> = "scripts/GTA_V_Session_Sniffer-plugin/log.txt"
local FAKE_FRIENDS__PATH <const> = "cfg/scid.cfg"
local FAKE_FRIENDS__MASKS = {
    STALK = {
        hexValue = 0x01,
        name = "Stalk",
    },
    JOIN_TIMEOUT = {
        hexValue = 0x04,
        name = "Join Timeout",
    },
    HIDE = {
        hexValue = 0x08,
        name = "Hide",
    },
    FRIEND_LIST = {
        hexValue = 0x10,
        name = "Friend List",
    }
}
local FAKE_FRIENDS__ENTRY_PATTERN = "^([%w._-]+):(%x+):(%x+)" -- Define the patterns with capturing groups
---- Global constants 1/2 END

---- Global variables START
local player_join__timestamps = {}
local scriptExitEventListener
local playerLeaveEventListener
local mainLoopThread
---- Global variables END

---- Global functions START
-- Function to escape special characters in a string for Lua patterns
local function escape_magic_characters(string)
    local matches = {
        ["^"] = "%^",
        ["$"] = "%$",
        ["("] = "%(",
        [")"] = "%)",
        ["%"] = "%%",
        ["."] = "%.",
        ["["] = "%[",
        ["]"] = "%]",
        ["*"] = "%*",
        ["+"] = "%+",
        ["-"] = "%-",
        ["?"] = "%?"
    }
    return (string:gsub(".", matches))
end

-- Function to check specific flags in a hexadecimal number
local function checkBit(hexFlag, mask)
    local flagValue = tonumber(hexFlag, 16)
    return flagValue ~= nil and (flagValue & mask == mask)
end

-- Function to read the entire file into a single string
function read_file(file_path)
    local file, err = io.open(file_path, "r")
    if err then
        return nil, err
    end

    local content = file:read("*a")

    file:close()

    return content, nil
end

local function dec_to_ipv4(ip)
	return string.format("%i.%i.%i.%i", ip >> 24 & 255, ip >> 16 & 255, ip >> 8 & 255, ip & 255)
end

local function rgb_to_int(R, G, B, A)
	A = A or 255
	return ((R&0x0ff)<<0x00)|((G&0x0ff)<<0x08)|((B&0x0ff)<<0x10)|((A&0x0ff)<<0x18)
end

local function create_tick_handler(handler, ms)
    return menu.create_thread(function()
        while true do
            handler()
            system.yield(ms)
        end
    end)
end

local function removeEventListener(eventType, listener)
    if listener and event.remove_event_listener(eventType, listener) then
        return nil
    end
end

local function is_thread_runnning(threadId)
    if threadId and not menu.has_thread_finished(threadId) then
        return true
    end

    return false
end

local function create_empty_file(filename)
    local file, err = io.open(filename, "w")
    if err then
        menu.notify("Oh no... Script crashed:(\nYou gotta restart it manually.", SCRIPT_NAME, 6, COLOR.RED)
        handle_script_exit()
        return
    end

    file:close()
end

local function handle_script_exit(params)
    params = params or {}

    scriptExitEventListener = removeEventListener("exit", scriptExitEventListener)
    playerLeaveEventListener = removeEventListener("player_leave", playerLeaveEventListener)

    if is_thread_runnning(mainLoopThread) then
        menu.delete_thread(mainLoopThread)
    end

    -- This will delete notifications from other scripts too.
    -- Suggestion is open: https://discord.com/channels/1088976448452304957/1092480948353904752/1253065431720394842
    if params.clearAllNotifications then
        menu.clear_all_notifications()
    end

    menu.exit()
end
---- Global functions END

---- Global constants 2/2 START
local COLOR <const> = {
    RED = rgb_to_int(255, 0, 0, 255),
}
local bailFeat <const> = menu.get_feature_by_hierarchy_key("online.lobby.bail_netsplit")
---- Global constants 2/2 END

---- Global event listeners START
scriptExitEventListener = event.add_event_listener("exit", function(f)
    handle_script_exit()
end)
playerLeaveEventListener = event.add_event_listener("player_leave", function(f)
    player_join__timestamps[f.player] = nil
end)
---- Global event listeners END
-- Globals END


-- === Main Menu Features === --
local myRootMenu = menu.add_feature(SCRIPT_TITLE, "parent", 0)

local exitScriptFeat = menu.add_feature("#FF0000DD#Stop Script#DEFAULT#", "action", myRootMenu.id, function(feat, pid)
    handle_script_exit({ clearAllNotifications = true })
end)
exitScriptFeat.hint = 'Stop "' .. SCRIPT_NAME .. '"'

menu.add_feature("       " .. string.rep(" -", 23), "action", myRootMenu.id)

local settingsMenu = menu.add_feature("Settings", "parent", myRootMenu.id)
settingsMenu.hint = "Options for the script."

local settingBailOnFakeFriendJoinTimeout = menu.add_feature('"Bail/Netsplit" from Fake Friend "Join Timeout" Users', "toggle", settingsMenu.id)
settingBailOnFakeFriendJoinTimeout.hint = 'When a Fake Friend "Join Timeout" flagged user is met, you will be desync from the rest of players, and thus be left alone in a solo public lobby.'
settingBailOnFakeFriendJoinTimeout.on = false


-- === Main Loop === --
mainLoopThread = create_tick_handler(function()
    local function loggerPreTask(player_entries_to_log, log__content, playerID, playerName, playerSCID, playerIP, currentTimestamp)
        if not player_join__timestamps[playerID] then
            player_join__timestamps[playerID] = os.time()
            return
        end

        if (
            not playerName
            or not playerSCID
            or not playerIP
            or playerIP and playerIP == "255.255.255.255"
        ) and (
            -- ISSUE: If within 1 second under protected IP, they already left, they wont be added in the logs.
            -- ISSUE: Perhaps 1-3 secs doesn't seems enough sometimes. (it's hard to debug that shit)
            currentTimestamp - player_join__timestamps[playerID] <= 1
        ) then
            return
        end

        local entry_pattern = string.format("user:(%s), scid:(%d), ip:(%s), timestamp:(%%d+)", escape_magic_characters(playerName), playerSCID, escape_magic_characters(playerIP))
        if
            not log__content:find("^" .. entry_pattern)
            and not log__content:find("\n" .. entry_pattern)
        then
            table.insert(player_entries_to_log, string.format("user:%s, scid:%d, ip:%s, timestamp:%d", playerName, playerSCID, playerIP, currentTimestamp))
        end
    end

    local function bailPreTask(fake_friends__content, playerName, playerSCID)
        if not utils.file_exists(FAKE_FRIENDS__PATH) then
            return false
        end

        local playerHexSCID = string.format("0x%x", playerSCID)

        for line in fake_friends__content:gmatch("[^\r\n]+") do
            local username, hexSCID, hexFlag = line:match(FAKE_FRIENDS__ENTRY_PATTERN)
            if username then
                if (
                    username == playerName
                    or hexSCID == playerHexSCID
                ) and (
                    checkBit(hexFlag, FAKE_FRIENDS__MASKS.JOIN_TIMEOUT.hexValue)
                ) then
                    return true
                end
            end
        end

        return false
    end

    local function write_to_log_file(log__content, player_entries_to_log)
        if not utils.file_exists(LOG_PATH) then
            create_empty_file(LOG_PATH)
        end

        local log_file, err = io.open(LOG_PATH, "a")
        if err then
            menu.notify("Oh no... Script crashed:(\nYou gotta restart it manually.", SCRIPT_NAME, 6, COLOR.RED)
            handle_script_exit()
            return
        end

        local combined_entries = table.concat(player_entries_to_log, "\n")
        log_file:write(combined_entries .. "\n")
        log_file:close()
    end

    if
        network.is_session_started()
        and player.get_host() ~= -1
    then
        local player_entries_to_log = {}
        local bailFromSession = false

        local fake_friends__content, err = read_file(FAKE_FRIENDS__PATH)
        if err then
            menu.notify("Oh no... Script crashed:(\nYou gotta restart it manually.", SCRIPT_NAME, 6, COLOR.RED)
            handle_script_exit()
            return
        end

        local log__content, err = read_file(LOG_PATH)
        if err then
            menu.notify("Oh no... Script crashed:(\nYou gotta restart it manually.", SCRIPT_NAME, 6, COLOR.RED)
            handle_script_exit()
            return
        end

        for playerID = 0, 31 do
            system.yield()

            if
                player.is_player_valid(playerID)
                and playerID ~= player.player_id()
            then
                local playerName = player.get_player_name(playerID)
                local playerSCID = player.get_player_scid(playerID)
                local playerIP = dec_to_ipv4(player.get_player_ip(playerID))
                local currentTimestamp = os.time()

                loggerPreTask(player_entries_to_log, log__content, playerID, playerName, playerSCID, playerIP, currentTimestamp)
                if
                    settingBailOnFakeFriendJoinTimeout.on
                    and not bailFromSession
                then
                    bailFromSession = bailPreTask(fake_friends__content, playerName, playerSCID)
                end
            end
        end

        if #player_entries_to_log > 0 then
            write_to_log_file(log__content, player_entries_to_log)
        end

        if bailFromSession then
            bailFromSession = false
            bailFeat:toggle()
        end
    else
        player_join__timestamps = {}
    end
end, 100)
