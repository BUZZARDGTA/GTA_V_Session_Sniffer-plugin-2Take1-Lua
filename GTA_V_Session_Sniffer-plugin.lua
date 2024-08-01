-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for GTA V Session Sniffer project on GitHub.
-- Allows you to automatically have every usernames showing up on GTA V Session Sniffer project, by logging all players from your sessions to "scripts/GTA_V_Session_Sniffer-plugin/log.txt".
-- Additionally, there's a feature that if you encounter a user flagged as a "Fake Friend" with "Join Timeout" flag, it automatically "Bail/Netsplit" you from the session.
-- GitHub Repository: https://github.com/Illegal-Services/GTA_V_Session_Sniffer-plugin-2Take1-Lua


-- Globals START
---- Global variables START
local scriptExitEventListener
local playerLeaveEventListener
local mainLoopThread
local player_join__timestamps = {}
---- Global variables END

---- Global constants 1/2 START
local SCRIPT_NAME <const> = "GTA_V_Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "GTA V Session Sniffer"
local SCRIPT_SETTINGS__PATH <const> = "scripts\\GTA_V_Session_Sniffer-plugin\\Settings.ini"
local SCRIPT_LOG__PATH <const> = "scripts\\GTA_V_Session_Sniffer-plugin\\log.txt"
local HOME_PATH <const> = utils.get_appdata_path("PopstarDevs", "2Take1Menu")
local FAKE_FRIENDS__PATH <const> = "cfg\\scid.cfg"
local FAKE_FRIENDS__ENTRY_PATTERN <const> = "^([%w._-]+):(%x+):(%x+)"
local FAKE_FRIENDS__MASKS <const> = {
    STALK = { hexValue = 0x01, name = "Stalk"},
    JOIN_TIMEOUT = { hexValue = 0x04, name = "Join Timeout"},
    HIDE = { hexValue = 0x08, name = "Hide" },
    FRIEND_LIST = { hexValue = 0x10, name = "Friend List" }
}
local BAIL_FEAT <const> = menu.get_feature_by_hierarchy_key("online.lobby.bail_netsplit")
local TRUSTED_FLAGS <const> = {
    { name = "LUA_TRUST_STATS", menuName = "Trusted Stats", bitValue = 1 << 0, isRequiered = false },
    { name = "LUA_TRUST_SCRIPT_VARS", menuName = "Trusted Globals / Locals", bitValue = 1 << 1, isRequiered = false },
    { name = "LUA_TRUST_NATIVES", menuName = "Trusted Natives", bitValue = 1 << 2, isRequiered = false },
    { name = "LUA_TRUST_HTTP", menuName = "Trusted Http", bitValue = 1 << 3, isRequiered = false },
    { name = "LUA_TRUST_MEMORY", menuName = "Trusted Memory", bitValue = 1 << 4, isRequiered = false }
}
---- Global constants 1/2 END

---- Global functions 1/2 START
local function rgb_to_int(R, G, B, A)
    A = A or 255
    return ((R&0x0ff)<<0x00)|((G&0x0ff)<<0x08)|((B&0x0ff)<<0x10)|((A&0x0ff)<<0x18)
end
---- Global functions 1/2 END

---- Global constants 2/2 START
local COLOR <const> = {
    RED = rgb_to_int(255, 0, 0, 255),
    ORANGE = rgb_to_int(255, 165, 0, 255),
    GREEN = rgb_to_int(0, 255, 0, 255)
}
---- Global constants 2/2 END

---- Global functions 2/2 START
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

local function dec_to_ipv4(ip)
    return string.format("%i.%i.%i.%i", ip >> 24 & 255, ip >> 16 & 255, ip >> 8 & 255, ip & 255)
end

local function checkBit(hexFlag, mask)
    local flagValue = tonumber(hexFlag, 16)
    return flagValue ~= nil and (flagValue & mask == mask)
end

local function pluralize(word, count)
    return word .. (count > 1 and "s" or "")
end

local function ends_with_newline(str)
    if string.sub(str, -1) == "\n" then
        return true
    end
    return false
end

function read_file(file_path)
    local file, err = io.open(file_path, "r")
    if err then
        return nil, err
    end

    local content = file:read("*a")

    file:close()

    return content, nil
end

local function get_collection_custom_value(collection, inputKey, inputValue, outputKey)
    --[[
    This function retrieves a specific value (or checks existence) from a collection based on a given input key-value pair.

    Parameters:
    collection (table): The collection to search within.
    inputKey (string): The key within each item of the collection to match against `inputValue`.
    inputValue (any): The value to match against `inputKey` within the collection.
    outputKey (string or nil): Optional. The key within the matched item to retrieve its value.
                                If nil, function returns true if item is found; false otherwise.

    Returns:
    If `outputKey` is provided and the item is resolved, it returns its value or nil;
    otherwise, it returns true or false depending on whether the item was found within the collection.
    ]]
    for _, item in ipairs(collection) do
        if item[inputKey] == inputValue then
            if outputKey == nil then
                return true
            else
                return item[outputKey]
            end
        end
    end

    if outputKey == nil then
        return false
    else
        return nil
    end
end

local function create_tick_handler(handler)
    return menu.create_thread(function()
        while true do
            handler()
            system.yield()
        end
    end)
end

local function is_thread_running(threadId)
    if threadId and not menu.has_thread_finished(threadId) then
        return true
    end

    return false
end

local function remove_event_listener(eventType, listener)
    if listener and event.remove_event_listener(eventType, listener) then
        return
    end

    return listener
end

local function delete_thread(threadId)
    if threadId and menu.delete_thread(threadId) then
        return nil
    end

    return threadId
end

local function handle_script_exit(params)
    params = params or {}
    if params.clearAllNotifications == nil then
        params.clearAllNotifications = false
    end
    if params.hasScriptCrashed == nil then
        params.hasScriptCrashed = false
    end

    scriptExitEventListener = remove_event_listener("exit", scriptExitEventListener)
    playerLeaveEventListener = remove_event_listener("exit", playerLeaveEventListener)

    if is_thread_running(scriptsListThread) then
        scriptsListThread = delete_thread(scriptsListThread)
    end

    -- This will delete notifications from other scripts too.
    -- Suggestion is open: https://discord.com/channels/1088976448452304957/1092480948353904752/1253065431720394842
    if params.clearAllNotifications then
        menu.clear_all_notifications()
    end

    if params.hasScriptCrashed then
        menu.notify("Oh no... Script crashed:(\nYou gotta restart it manually.", SCRIPT_NAME, 6, COLOR.RED)
    end

    menu.exit()
end

local function create_empty_file(filename)
    local file, err = io.open(filename, "w")
    if err then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    file:close()
end

local function handle_player_leave(f)
    player_join__timestamps[f.player] = nil
end

local function save_settings(params)
    params = params or {}
    if params.wasSettingsCorrupted == nil then
        params.wasSettingsCorrupted = false
    end

    local file, err = io.open(SCRIPT_SETTINGS__PATH, "w")
    if err then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    local settingsContent = ""

    for _, setting in ipairs(ALL_SETTINGS) do
        settingsContent = settingsContent .. setting.key .. "=" .. tostring(setting.feat.on) .. "\n"
    end

    file:write(settingsContent)

    file:close()

    if params.wasSettingsCorrupted then
        menu.notify("Settings file were corrupted but have been successfully restored and saved.", SCRIPT_TITLE, 6, COLOR.ORANGE)
    else
        menu.notify("Settings successfully saved.", SCRIPT_TITLE, 6, COLOR.GREEN)
    end
end

local function load_settings(params)
    local function custom_str_to_bool(string, only_match_against)
        --[[
        This function returns the boolean value represented by the string for lowercase or any case variation;
        otherwise, nil.

        Args:
            string (str): The boolean string to be checked.
            (optional) only_match_against (bool | None): If provided, the only boolean value to match against.
        ]]
        local need_rewrite_current_setting = false
        local resolved_value = nil

        if string == nil then
            return nil, true -- Input is not a valid string
        end

        local string_lower = string:lower()

        if string_lower == "true" then
            resolved_value = true
        elseif string_lower == "false" then
            resolved_value = false
        end

        if resolved_value == nil then
            return nil, true -- Input is not a valid boolean value
        end

        if (
            only_match_against ~= nil
            and only_match_against ~= resolved_value
        ) then
            return nil, true -- Input does not match the specified boolean value
        end

        if string ~= tostring(resolved_value) then
            need_rewrite_current_setting = true
        end

        return resolved_value, need_rewrite_current_setting
    end

    params = params or {}
    if params.settings_to_load == nil then
        params.settings_to_load = {}

        for _, setting in ipairs(ALL_SETTINGS) do
            params.settings_to_load[setting.key] = setting.feat
        end
    end
    if params.isScriptStartup == nil then
        params.isScriptStartup = false
    end

    local settings_loaded = {}
    local areSettingsLoaded = false
    local hasResetSettings = false
    local needRewriteSettings = false
    local settingFileExisted = false

    if utils.file_exists(SCRIPT_SETTINGS__PATH) then
        settingFileExisted = true

        local settings_content, err = read_file(SCRIPT_SETTINGS__PATH)
        if err then
            menu.notify("Settings could not be loaded.", SCRIPT_TITLE, 6, COLOR.RED)
            handle_script_exit({ hasScriptCrashed = true })
            return areSettingsLoaded
        end

        for line in settings_content:gmatch("[^\r\n]+") do
            local key, value = line:match("^(.-)=(.*)$")
            if key then
                if get_collection_custom_value(ALL_SETTINGS, "key", key) then
                    if params.settings_to_load[key] ~= nil then
                        settings_loaded[key] = value
                    end
                else
                    needRewriteSettings = true
                end
            else
                needRewriteSettings = true
            end
        end

        if not ends_with_newline(settings_content) then
            needRewriteSettings = true
        end

        areSettingsLoaded = true
    else
        hasResetSettings = true

        if not params.isScriptStartup then
            menu.notify("Settings file not found.", SCRIPT_TITLE, 6, COLOR.RED)
        end
    end

    for setting, _ in pairs(params.settings_to_load) do
        local resolvedSettingValue = get_collection_custom_value(ALL_SETTINGS, "key", setting, "defaultValue")

        local settingLoadedValue, needRewriteCurrentSetting = custom_str_to_bool(settings_loaded[setting])
        if settingLoadedValue ~= nil then
            resolvedSettingValue = settingLoadedValue
        end
        if needRewriteCurrentSetting then
            needRewriteSettings = true
        end

        params.settings_to_load[setting].on = resolvedSettingValue
    end

    if not params.isScriptStartup then
        if hasResetSettings then
            menu.notify("Settings have been loaded and applied to their default values.", SCRIPT_TITLE, 6, COLOR.ORANGE)
        else
            menu.notify("Settings successfully loaded and applied.", SCRIPT_TITLE, 6, COLOR.GREEN)
        end
    end

    if needRewriteSettings then
        local wasSettingsCorrupted = settingFileExisted or false
        save_settings({ wasSettingsCorrupted = wasSettingsCorrupted })
    end

    return areSettingsLoaded
end
---- Global functions 2/2 END

---- Global event listeners START
scriptExitEventListener = event.add_event_listener("exit", function()
    handle_script_exit({ clearAllNotifications = true })
end)
playerLeaveEventListener = event.add_event_listener("player_leave", function(f)
    handle_player_leave(f)
end)
---- Global event listeners END
-- Globals END


-- Permissions Startup Checking START
local unnecessaryPermissions = {}
local missingPermissions = {}

for _, flag in ipairs(TRUSTED_FLAGS) do
    if menu.is_trusted_mode_enabled(flag.bitValue) then
        if not flag.isRequiered then
            table.insert(unnecessaryPermissions, flag.menuName)
        end
    else
        if flag.isRequiered then
            table.insert(missingPermissions, flag.menuName)
        end
    end
end

if #unnecessaryPermissions > 0 then
    menu.notify("You do not require the following " .. pluralize("permission", #unnecessaryPermissions) .. ":\n" .. table.concat(unnecessaryPermissions, "\n"),
        SCRIPT_NAME, 6, COLOR.ORANGE)
end
if #missingPermissions > 0 then
    menu.notify(
        "You need to enable the following " .. pluralize("permission", #missingPermissions) .. ":\n" .. table.concat(missingPermissions, "\n"),
        SCRIPT_NAME, 6, COLOR.RED)
    handle_script_exit()
end
-- Permissions Startup Checking END


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

menu.add_feature("       " .. string.rep(" -", 23), "action", settingsMenu.id)

ALL_SETTINGS = {
    {key = "settingBailOnFakeFriendJoinTimeout", defaultValue = false, feat = settingBailOnFakeFriendJoinTimeout}
}

local loadSettings = menu.add_feature('Load Settings', "action", settingsMenu.id, function()
    load_settings()
end)
loadSettings.hint = 'Load saved settings from your file: "' .. HOME_PATH .. "\\" .. SCRIPT_SETTINGS__PATH .. '".\n\nDeleting this file will apply the default settings.'

local saveSettings = menu.add_feature('Save Settings', "action", settingsMenu.id, function()
    save_settings()
end)
saveSettings.hint = 'Save your current settings to the file: "' .. HOME_PATH .. "\\" .. SCRIPT_SETTINGS__PATH .. '".'


load_settings({ isScriptStartup = true })


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
        if not utils.file_exists(SCRIPT_LOG__PATH) then
            create_empty_file(SCRIPT_LOG__PATH)
        end

        local log_file, err = io.open(SCRIPT_LOG__PATH, "a")
        if err then
            handle_script_exit({ hasScriptCrashed = true })
            return
        end

        local combined_entries = table.concat(player_entries_to_log, "\n")
        log_file:write(combined_entries .. "\n")
        log_file:close()
    end

    if network.is_session_started() and player.get_host() ~= -1 then
        local player_entries_to_log = {}
        local bailFromSession = false

        local fake_friends__content, err = read_file(FAKE_FRIENDS__PATH)
        if err then
            handle_script_exit({ hasScriptCrashed = true })
            return
        end

        local log__content, err = read_file(SCRIPT_LOG__PATH)
        if err then
            handle_script_exit({ hasScriptCrashed = true })
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
            BAIL_FEAT:toggle()
        end
    else
        player_join__timestamps = {}
    end
end, 100)
