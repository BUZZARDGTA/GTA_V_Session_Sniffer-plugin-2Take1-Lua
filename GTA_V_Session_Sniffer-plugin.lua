-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for GTA V Session Sniffer project on GitHub.
-- Allows you to have every usernames showing up on GTA V Session Sniffer.
-- It logs every players from your sessions in "scripts/GTA_V_Session_Sniffer-plugin/log.txt".
-- If a Fake Friend "Join Timeout" flagged user is met, automatically "Bail/Netsplit" you from the session.
-- GitHub Repository: https://github.com/Illegal-Services/GTA_V_Session_Sniffer-plugin-2Take1-Lua


-- Globals START
---- Global constants 1/2 START
local SCRIPT_NAME <const> = "GTA_V_Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "GTA V Session Sniffer"
local LOGGING_PATH <const> = "scripts/GTA_V_Session_Sniffer-plugin/log.txt"
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

local settingBailOnBlacklisted = menu.add_feature('"Bail/Netsplit" from Fake Friend "Join Timeout" Users', "toggle", settingsMenu.id)
settingBailOnBlacklisted.hint = 'When a Fake Friend "Join Timeout" flagged user is met, you will be desync from the rest of players, and thus be left alone in a solo public lobby.'
settingBailOnBlacklisted.on = false


-- === Player-Specific Features === --
-- TODO:
-- Add an option that blacklist an user, automatically.


-- === Main Loop === --
mainLoopThread = create_tick_handler(function()
    local function loggerPreTask(players_to_log, playerID, playerName, playerSCID, playerIP, currentTimestamp)
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

        table.insert(players_to_log, {
            ID = playerID,
            Name = playerName,
            IP = playerIP,
            SCID = playerSCID,
            Timestamp = currentTimestamp
        })
    end

    local function bailPreTask(playerName, playerSCID)
        if not utils.file_exists(FAKE_FRIENDS__PATH) then
            return false
        end

        local playerHexSCID = string.format("0x%x", playerSCID)

        -- Read current blacklist file content
        local fakeFriends_file, err = io.open(FAKE_FRIENDS__PATH, "r")
        if err then
            menu.notify("Oh no... Script crashed:(\nYou gotta restart it manually.", SCRIPT_NAME, 6, COLOR.RED)
            handle_script_exit()
            return false
        end

        -- Read all lines into a table
        local lines = {}
        for line in fakeFriends_file:lines() do
            lines[#lines + 1] = line
        end
        fakeFriends_file:close()

        -- Define the patterns with capturing groups
        local ffEntryPattern = "^([%w._-]+):(%x+):(%x+)"

        -- Iterate over each line in the table
        for _, line in ipairs(lines) do
            -- Check if the line matches the pattern
            local username, hexSCID, hexFlag = line:match(ffEntryPattern)
            if (
                username == playerName
                or hexSCID == playerHexSCID
            ) and (
                checkBit(hexFlag, FAKE_FRIENDS__MASKS.JOIN_TIMEOUT.hexValue)
            ) then
                return true
            end
        end

        return false
    end

    local function write_to_log_file(players_to_log)
        if not utils.file_exists(LOGGING_PATH) then
            create_empty_file(LOGGING_PATH)
        end

        -- Read current log file content
        local log_file, err = io.open(LOGGING_PATH, "r")
        if err then
            menu.notify("Oh no... Script crashed:(\nYou gotta restart it manually.", SCRIPT_NAME, 6, COLOR.RED)
            handle_script_exit()
            return
        end

        local log_content = log_file:read("*all")
        log_file:close()

        -- Prepare entries to add
        local entries_to_add = {}
        for _, player in ipairs(players_to_log) do
            local entry = string.format("user:%s, ip:%s, scid:%s, timestamp:", player.Name, player.IP, player.SCID)
            if not log_content or not log_content:find(entry, 1, true) then
                table.insert(entries_to_add, entry .. player.Timestamp)
            end
        end

        -- Check if there are entries to add; if not, exit early
        if #entries_to_add <= 0 then
            return
        end

        -- Write new entries to log file
        local log_file, err = io.open(LOGGING_PATH, "a")
        if err then
            menu.notify("Oh no... Script crashed:(\nYou gotta restart it manually.", SCRIPT_NAME, 6, COLOR.RED)
            handle_script_exit()
            return
        end

        -- Build the log content as a single string
        local combined_entries = table.concat(entries_to_add, "\n")

        -- Write the entire content to the log file
        log_file:write(combined_entries .. "\n")

        -- Close the file
        log_file:close()
    end

    if
        network.is_session_started()
        and player.get_host() ~= -1
    then
        local players_to_log = {}
        local bailFromSession = false

        for playerID = 0, 31 do
            if
                player.is_player_valid(playerID)
                and playerID ~= player.player_id()
            then
                local playerName = player.get_player_name(playerID)
                local playerSCID = player.get_player_scid(playerID)
                local playerIP = dec_to_ipv4(player.get_player_ip(playerID))
                local currentTimestamp = os.time()

                loggerPreTask(players_to_log, playerID, playerName, playerSCID, playerIP, currentTimestamp)
                if not bailFromSession then
                    bailFromSession = bailPreTask(playerName, playerSCID)
                end
            end
        end

        if #players_to_log > 0 then
            write_to_log_file(players_to_log)
        end

        if bailFromSession then
            bailFromSession = false

            if settingBailOnBlacklisted.on then
                bailFeat:toggle()
            end
        end
    else
        player_join__timestamps = {}
    end
end, 100)
