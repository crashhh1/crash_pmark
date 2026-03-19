local panelOpen = false

local function setPanelState(state)
    panelOpen = state
    SetNuiFocus(state, state)
    SendNUIMessage({
        action = 'panel',
        open = state
    })
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end
    if panelOpen then
        setPanelState(false)
    else
        SendNUIMessage({
            action = 'panel',
            open = false
        })
    end
end)

local function formatLocation(coords)
    if not coords then
        return 'Unknown'
    end
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x + 0.0, coords.y + 0.0, (coords.z or 0.0) + 0.0)
    local street = GetStreetNameFromHashKey(streetHash or 0)
    local crossing = GetStreetNameFromHashKey(crossingHash or 0)
    if crossing and crossing ~= '' then
        return street .. ' / ' .. crossing
    end
    if street and street ~= '' then
        return street
    end
    return 'Unknown'
end

RegisterCommand('setcallsign', function(source, args, rawCommand)
    TriggerServerEvent('crash_pmark:setcallsign', args[1] and table.concat(args, ' ') or '')
end, false)

RegisterCommand('status', function(source, args, rawCommand)
    TriggerServerEvent('crash_pmark:setstatus', args[1] and table.concat(args, ' ') or '')
end, false)

RegisterCommand('pmark', function(source, args, rawCommand)
    local input = args[1] and table.concat(args, ' ') or ''
    if input == '' then
        if panelOpen then
            setPanelState(false)
            TriggerServerEvent('crash_pmark:closePanel')
        else
            setPanelState(true)
            TriggerServerEvent('crash_pmark:openPanel')
        end
        return
    end
    TriggerServerEvent('crash_pmark:pmarkByCallsign', input)
end, false)

RegisterNetEvent('crash_pmark:openPanel', function()
    if not panelOpen then
        setPanelState(true)
    end
end)

RegisterNetEvent('crash_pmark:uiData', function(units, trackedSource)
    local payload = {}
    for i = 1, #units do
        local row = units[i]
        payload[#payload + 1] = {
            source = row.source,
            callsign = row.callsign or 'unknown',
            unit = row.unit or ('ID ' .. tostring(row.source)),
            status = row.status or 'Available',
            location = formatLocation(row.coords)
        }
    end
    SendNUIMessage({
        action = 'units',
        units = payload,
        trackedSource = trackedSource
    })
end)

RegisterNetEvent('crash_pmark:updateWaypoint', function(x, y, z)
    SetNewWaypoint(x, y)
end)

RegisterNetEvent('crash_pmark:clearWaypoint', function()
    SetWaypointOff()
end)

RegisterNetEvent('crash_pmark:remindCallsign', function()
    TriggerEvent('chat:addMessage', {
        color = { 66, 135, 245 },
        multiline = true,
        args = { 'PD', 'Set your callsign with /setcallsign [callsign] so other units can track you on the map.' }
    })
end)

RegisterNetEvent('crash_pmark:showStatusOptions', function(list)
    TriggerEvent('chat:addMessage', {
        color = { 66, 135, 245 },
        multiline = true,
        args = { 'STATUS', 'Valid statuses: ' .. tostring(list) }
    })
end)

RegisterNUICallback('close', function(_, cb)
    if panelOpen then
        setPanelState(false)
        TriggerServerEvent('crash_pmark:closePanel')
    end
    cb('ok')
end)

RegisterNUICallback('toggleTrack', function(data, cb)
    TriggerServerEvent('crash_pmark:pmarkBySource', data and data.source or nil)
    cb('ok')
end)

RegisterNUICallback('setStatusForUnit', function(data, cb)
    TriggerServerEvent('crash_pmark:setstatusForUnit', data and data.source or nil, data and data.value or '')
    cb('ok')
end)

RegisterNUICallback('setCallsignForUnit', function(data, cb)
    TriggerServerEvent('crash_pmark:setcallsignForUnit', data and data.source or nil, data and data.value or '')
    cb('ok')
end)

RegisterNUICallback('updateUnitMeta', function(data, cb)
    TriggerServerEvent(
        'crash_pmark:updateUnitMetaForUnit',
        data and data.source or nil,
        data and data.callsign or '',
        data and data.status or ''
    )
    cb('ok')
end)
