local ESX = nil
local Tracking = {}
local UiWatchers = {}
local CallsignByIdentifier = {}
local StatusByIdentifier = {}
local AllowedStatuses = {
    AVAILABLE = 'Available',
    UNAVAILABLE = 'Unavailable',
    BUSY = 'Busy',
    ONCALL = 'On-Call',
    ONSCENE = 'On Scene',
    ENROUTE = 'Enroute'
}

local function normalizeStatus(status)
    if type(status) ~= 'string' then
        return nil
    end
    status = string.gsub(status, '^%s*(.-)%s*$', '%1')
    status = status and status or ''
    if status == '' then
        return nil
    end
    status = string.upper(status)
    status = status:gsub('[%s%-]+', '')
    return AllowedStatuses[status]
end

local function showStatusOptions(source)
    local list = 'Available | Unavailable | Busy | On-Call | On Scene | Enroute'
    TriggerClientEvent('crash_pmark:showStatusOptions', source, list)
end

CreateThread(function()
    while ESX == nil do
        local ok, result = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and result then
            ESX = result
            break
        end
        Wait(100)
    end
end)

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return string.gsub(value, '^%s*(.-)%s*$', '%1')
end

local function notify(source, message)
    TriggerClientEvent('esx:showNotification', source, message)
end

local function isPolice(xPlayer)
    if not xPlayer then
        return false
    end
    local job = xPlayer.getJob()
    return job and job.name == Config.PoliceJobName
end

local function getCallsignByIdentifier(identifier, cb)
    if not MySQL then return cb(nil) end
    MySQL.single('SELECT callsign FROM callsigns WHERE identifier = ?', { identifier }, function(row)
        cb(row and row.callsign or nil)
    end)
end

local function getIdentifierByCallsign(callsign, cb)
    if not MySQL then return cb(nil) end
    MySQL.single('SELECT identifier FROM callsigns WHERE LOWER(callsign) = LOWER(?)', { callsign }, function(row)
        cb(row and row.identifier or nil)
    end)
end

local function setCallsignForIdentifier(identifier, callsign, cb)
    if not MySQL then return cb(false) end
    MySQL.execute('DELETE FROM callsigns WHERE identifier = ?', { identifier }, function()
        MySQL.execute('INSERT INTO callsigns (identifier, callsign) VALUES (?, ?)', { identifier, callsign }, function()
            CallsignByIdentifier[identifier] = callsign
            cb(true)
        end)
    end)
end

local function isCallsignTaken(callsign, excludeIdentifier, cb)
    getIdentifierByCallsign(callsign, function(identifier)
        cb(identifier and identifier ~= excludeIdentifier)
    end)
end

local function getTargetSourceByCallsign(callsign, cb)
    getIdentifierByCallsign(callsign, function(identifier)
        if not identifier then
            return cb(nil)
        end
        local xPlayer = ESX and ESX.GetPlayerFromIdentifier(identifier)
        if not isPolice(xPlayer) then
            return cb(nil)
        end
        cb(xPlayer.source)
    end)
end

local function clearTrackingForTarget(targetSource)
    for trackerSource, tgt in pairs(Tracking) do
        if tgt == targetSource then
            Tracking[trackerSource] = nil
            TriggerClientEvent('crash_pmark:clearWaypoint', trackerSource)
        end
    end
end

local function validateAndGetOfficer(source)
    if source == 0 or not ESX then
        return nil
    end
    local xPlayer = ESX.GetPlayerFromId(source)
    if not isPolice(xPlayer) then
        return nil
    end
    return xPlayer
end

local function setStatusBySource(targetSource, status)
    if not ESX then
        return false
    end
    local xTarget = ESX.GetPlayerFromId(targetSource)
    if not isPolice(xTarget) then
        return false
    end
    local identifier = xTarget.getIdentifier()
    if not identifier then
        return false
    end
    StatusByIdentifier[identifier] = status
    return true
end

local function toggleTrackingBySource(trackerSource, targetSource)
    if targetSource == trackerSource then
        notify(trackerSource, '~r~You cannot track yourself.')
        return
    end
    local xTarget = ESX.GetPlayerFromId(targetSource)
    if not isPolice(xTarget) then
        notify(trackerSource, '~r~Unit not found or not on duty.')
        return
    end
    if Tracking[trackerSource] == targetSource then
        Tracking[trackerSource] = nil
        TriggerClientEvent('crash_pmark:clearWaypoint', trackerSource)
        notify(trackerSource, '~b~Tracking cleared.')
        return
    end
    Tracking[trackerSource] = targetSource
    notify(trackerSource, '~g~Tracking enabled.')
end

local function buildOnDutySnapshot()
    local snapshot = {}
    local players = GetPlayers()
    for i = 1, #players do
        local source = tonumber(players[i])
        local xPlayer = ESX.GetPlayerFromId(source)
        if isPolice(xPlayer) then
            local identifier = xPlayer.getIdentifier()
            local callsign = identifier and CallsignByIdentifier[identifier] or nil
            local status = (identifier and StatusByIdentifier[identifier]) or 'Available'
            local ped = GetPlayerPed(source)
            local coords = nil
            if ped and ped ~= 0 then
                local c = GetEntityCoords(ped)
                coords = { x = c.x, y = c.y, z = c.z }
            end
            snapshot[#snapshot + 1] = {
                source = source,
                callsign = callsign and callsign ~= '' and callsign or 'unknown',
                unit = xPlayer.getName() or GetPlayerName(source) or ('ID ' .. tostring(source)),
                status = status,
                coords = coords
            }
        end
    end
    return snapshot
end

local function pushSnapshotToWatchers(snapshot)
    for watcherSource in pairs(UiWatchers) do
        TriggerClientEvent('crash_pmark:uiData', watcherSource, snapshot, Tracking[watcherSource])
    end
end

local function primeMissingCallsigns(cb)
    local missing = {}
    local players = GetPlayers()
    for i = 1, #players do
        local source = tonumber(players[i])
        local xPlayer = ESX.GetPlayerFromId(source)
        if isPolice(xPlayer) then
            local identifier = xPlayer.getIdentifier()
            if identifier and CallsignByIdentifier[identifier] == nil then
                missing[#missing + 1] = identifier
                CallsignByIdentifier[identifier] = '' -- prevent duplicates while priming
            end
        end
    end

    if #missing == 0 then
        cb()
        return
    end

    local pending = #missing
    for i = 1, #missing do
        local identifier = missing[i]
        getCallsignByIdentifier(identifier, function(dbCallsign)
            CallsignByIdentifier[identifier] = dbCallsign or ''
            pending = pending - 1
            if pending <= 0 then
                cb()
            end
        end)
    end
end

local function pushRosterToWatchers()
    if next(UiWatchers) == nil then
        return
    end
    pushSnapshotToWatchers(buildOnDutySnapshot())
end

CreateThread(function()
    if not MySQL then
        return
    end
    MySQL.query('SELECT identifier, callsign FROM callsigns', {}, function(rows)
        if not rows then
            return
        end
        for i = 1, #rows do
            local row = rows[i]
            CallsignByIdentifier[row.identifier] = row.callsign
        end
    end)
end)

CreateThread(function()
    while true do
        local hasTracking = next(Tracking) ~= nil
        local hasWatchers = next(UiWatchers) ~= nil
        if not hasTracking and not hasWatchers then
            Wait(2000)
        else
            Wait(Config.TrackingIntervalMs)
            if hasTracking then
                for trackerSource, targetSource in pairs(Tracking) do
                    local xTarget = ESX.GetPlayerFromId(targetSource)
                    if not isPolice(xTarget) then
                        Tracking[trackerSource] = nil
                        TriggerClientEvent('crash_pmark:clearWaypoint', trackerSource)
                    else
                        local ped = GetPlayerPed(targetSource)
                        if not ped or ped == 0 then
                            Tracking[trackerSource] = nil
                            TriggerClientEvent('crash_pmark:clearWaypoint', trackerSource)
                        else
                            local coords = GetEntityCoords(ped)
                            TriggerClientEvent('crash_pmark:updateWaypoint', trackerSource, coords.x, coords.y, coords.z)
                        end
                    end
                end
            end
            if hasWatchers then
                pushSnapshotToWatchers(buildOnDutySnapshot())
            end
        end
    end
end)

RegisterNetEvent('crash_pmark:setcallsign', function(callsign)
    local source = source
    local xPlayer = validateAndGetOfficer(source)
    if not xPlayer then
        notify(source, '~r~You must be on duty as police.')
        return
    end
    callsign = trim(callsign)
    if callsign == '' then
        notify(source, '~r~Callsign cannot be empty.')
        return
    end
    if #callsign < Config.CallsignMinLength or #callsign > Config.CallsignMaxLength then
        notify(source, '~r~Callsign length invalid.')
        return
    end
    local identifier = xPlayer.getIdentifier()
    if not identifier then
        notify(source, '~r~Could not get your identifier.')
        return
    end
    isCallsignTaken(callsign, identifier, function(taken)
        if taken then
            notify(source, '~r~That callsign is already in use.')
            return
        end
        setCallsignForIdentifier(identifier, callsign, function(ok)
            if ok then
                notify(source, '~g~Callsign set to: ' .. callsign)
                pushRosterToWatchers()
            else
                notify(source, '~r~Failed to save callsign.')
            end
        end)
    end)
end)

RegisterNetEvent('crash_pmark:setcallsignForUnit', function(targetSource, callsign)
    local source = source
    local xOfficer = validateAndGetOfficer(source)
    if not xOfficer then
        notify(source, '~r~You must be on duty as police.')
        return
    end
    targetSource = tonumber(targetSource)
    local xTarget = targetSource and ESX.GetPlayerFromId(targetSource) or nil
    if not isPolice(xTarget) then
        notify(source, '~r~Target unit is not on duty.')
        return
    end
    callsign = trim(callsign)
    if callsign == '' then
        notify(source, '~r~Callsign cannot be empty.')
        return
    end
    if #callsign < Config.CallsignMinLength or #callsign > Config.CallsignMaxLength then
        notify(source, '~r~Callsign length invalid.')
        return
    end
    local identifier = xTarget.getIdentifier()
    isCallsignTaken(callsign, identifier, function(taken)
        if taken then
            notify(source, '~r~That callsign is already in use.')
            return
        end
        setCallsignForIdentifier(identifier, callsign, function(ok)
            if ok then
                notify(source, '~g~Unit callsign updated.')
                notify(targetSource, '~b~Your callsign was updated to: ' .. callsign)
                pushRosterToWatchers()
            else
                notify(source, '~r~Failed to save callsign.')
            end
        end)
    end)
end)

RegisterNetEvent('crash_pmark:setstatus', function(status)
    local source = source
    local xPlayer = validateAndGetOfficer(source)
    if not xPlayer then
        notify(source, '~r~You must be on duty as police.')
        return
    end
    if status == nil or status == '' then
        showStatusOptions(source)
        return
    end
    status = trim(status)
    if status == '' then
        showStatusOptions(source)
        return
    end
    if #status > Config.StatusMaxLength then
        notify(source, '~r~Status is too long.')
        return
    end
    local normalized = normalizeStatus(status)
    if not normalized then
        notify(source, '~r~Invalid status option.')
        return
    end
    local identifier = xPlayer.getIdentifier()
    StatusByIdentifier[identifier] = normalized
    notify(source, '~g~Status set to: ' .. normalized)
    pushRosterToWatchers()
end)

RegisterNetEvent('crash_pmark:setstatusForUnit', function(targetSource, status)
    local source = source
    local xOfficer = validateAndGetOfficer(source)
    if not xOfficer then
        notify(source, '~r~You must be on duty as police.')
        return
    end
    status = trim(status)
    if status == '' then
        notify(source, '~r~Status cannot be empty.')
        return
    end
    if #status > Config.StatusMaxLength then
        notify(source, '~r~Status is too long.')
        return
    end
    local normalized = normalizeStatus(status)
    if not normalized then
        notify(source, '~r~Invalid status option.')
        return
    end
    targetSource = tonumber(targetSource)
    if not targetSource or not setStatusBySource(targetSource, normalized) then
        notify(source, '~r~Target unit is not on duty.')
        return
    end
    notify(source, '~g~Unit status updated.')
    notify(targetSource, '~b~Your status was updated to: ' .. normalized)
    pushRosterToWatchers()
end)

RegisterNetEvent('crash_pmark:updateUnitMetaForUnit', function(targetSource, callsign, status)
    local source = source
    local xOfficer = validateAndGetOfficer(source)
    if not xOfficer then
        notify(source, '~r~You must be on duty as police.')
        return
    end

    targetSource = tonumber(targetSource)
    local xTarget = targetSource and ESX.GetPlayerFromId(targetSource) or nil
    if not isPolice(xTarget) then
        notify(source, '~r~Target unit is not on duty.')
        return
    end

    callsign = type(callsign) == 'string' and trim(callsign) or ''
    if callsign == '' then
        notify(source, '~r~Callsign cannot be empty.')
        return
    end
    if #callsign < Config.CallsignMinLength or #callsign > Config.CallsignMaxLength then
        notify(source, '~r~Callsign length invalid.')
        return
    end

    local normalizedStatus = normalizeStatus(status)
    if not normalizedStatus then
        notify(source, '~r~Invalid status option.')
        return
    end

    local identifier = xTarget.getIdentifier()
    isCallsignTaken(callsign, identifier, function(taken)
        if taken then
            notify(source, '~r~That callsign is already in use.')
            return
        end

        setCallsignForIdentifier(identifier, callsign, function(ok)
            if not ok then
                notify(source, '~r~Failed to save callsign.')
                return
            end

            StatusByIdentifier[identifier] = normalizedStatus
            notify(source, '~g~Unit updated.')
            notify(targetSource, '~b~Your callsign/status was updated.')
            pushRosterToWatchers()
        end)
    end)
end)

RegisterNetEvent('crash_pmark:pmarkByCallsign', function(callsign)
    local source = source
    local xPlayer = validateAndGetOfficer(source)
    if not xPlayer then
        notify(source, '~r~You must be on duty as police.')
        return
    end
    callsign = trim(callsign)
    if callsign == '' then
        TriggerClientEvent('crash_pmark:openPanel', source)
        UiWatchers[source] = true
        primeMissingCallsigns(function()
            TriggerClientEvent('crash_pmark:uiData', source, buildOnDutySnapshot(), Tracking[source])
        end)
        return
    end
    getTargetSourceByCallsign(callsign, function(targetSource)
        if not targetSource then
            notify(source, '~r~Unit not found or not on duty.')
            return
        end
        toggleTrackingBySource(source, targetSource)
    end)
end)

RegisterNetEvent('crash_pmark:pmarkBySource', function(targetSource)
    local source = source
    local xPlayer = validateAndGetOfficer(source)
    if not xPlayer then
        notify(source, '~r~You must be on duty as police.')
        return
    end
    targetSource = tonumber(targetSource)
    if not targetSource then
        return
    end
    toggleTrackingBySource(source, targetSource)
end)

RegisterNetEvent('crash_pmark:openPanel', function()
    local source = source
    local xPlayer = validateAndGetOfficer(source)
    if not xPlayer then
        notify(source, '~r~You must be on duty as police.')
        return
    end
    UiWatchers[source] = true
    primeMissingCallsigns(function()
        TriggerClientEvent('crash_pmark:uiData', source, buildOnDutySnapshot(), Tracking[source])
    end)
end)

RegisterNetEvent('crash_pmark:closePanel', function()
    UiWatchers[source] = nil
end)

AddEventHandler('playerDropped', function(reason)
    local source = source
    Tracking[source] = nil
    UiWatchers[source] = nil
    clearTrackingForTarget(source)
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer, isNew)
    if not playerId or not xPlayer or not isPolice(xPlayer) then return end
    local identifier = xPlayer.getIdentifier()
    local callsign = identifier and CallsignByIdentifier[identifier] or nil
    if not callsign or callsign == '' then
        getCallsignByIdentifier(identifier, function(dbCallsign)
            CallsignByIdentifier[identifier] = dbCallsign
            if not dbCallsign or dbCallsign == '' then
                TriggerClientEvent('crash_pmark:remindCallsign', playerId)
            end
        end)
    end
end)
