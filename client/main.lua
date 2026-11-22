-- opx_traumateam client: the help line and the key at stations and kiosks, the menus, the eye options, the
-- care bar and the route to a call. It only asks; the server decides (and checks place, job and time).

local OPX = assert(require('@opx_core'))
local Ui = assert(require('client.modules.ui'))
local Target = assert(require('client.modules.target'))
local Dispatch = assert(require('client.modules.dispatch'))

local MAPPING = 'opx_traumateam.open'
local inside = false -- the player stands at a station or kiosk (help line shown)
local caring = false -- a care bar runs

-- Calls the HUD provider (opx_core Config.providers.hud) under pcall: it may be absent or lack ShowHelp.
local function hud(name, ...)
	local provider = OPX.GetProvider('hud')
	if not provider then return end
	pcall(Open77.exports.callSync, provider, name, ...)
end

local function near(list, x, y, z)
	for _, point in ipairs(list) do
		local dx, dy, r = x - point.x, y - point.y, point.radius or 2.5
		if dx * dx + dy * dy <= r * r and math.abs(z - point.z) <= Config.heightTolerance then return true end
	end
	return false
end

local function atPoint()
	local x, y, z = Open77.character.position()
	if type(x) ~= 'number' then return false end
	return near(Config.stations, x, y, z) or near(Config.kiosks, x, y, z)
end

CreateThread(function()
	local ok, reason = RegisterKeyMapping(MAPPING, Ui.text('key_name'), Config.key or 'E', function()
		if inside and OPX.IsLoaded() and not Ui.isOpen() then TriggerServerEvent('opx_traumateam:open') end
	end)
	if not ok then print(('[opx_traumateam] key mapping refused: %s'):format(tostring(reason))) end

	Target.register(Ui.text)

	while true do
		local now = OPX.IsLoaded() and atPoint()
		if now and not inside then
			hud('ShowHelp', Ui.text('help'), Open77.input.keyFor(MAPPING) or Config.key)
		elseif inside and not now then
			hud('HideHelp')
			Ui.close() -- walked away: the server would refuse the actions anyway
		end
		inside = now
		Wait(inside and 250 or 750)
	end
end)

-- Pins while a character is loaded; everything closes and the route goes on unload.
OPX.OnPlayerLoaded(function() Dispatch.showPins(Ui.text('blip_station'), Ui.text('blip_kiosk')) end)
OPX.OnPlayerUnloaded(function()
	Dispatch.hidePins()
	Dispatch.clearRoute()
	Ui.closeAll()
end)

-- Care: runs the progress provider's bar (pacing only), then tells the server how it ended.
local function progress(options)
	local provider = OPX.GetProvider('progress')
	if not provider then
		Wait(options.duration)
		return true
	end
	local pending, err = Open77.exports.call(provider, 'Start', options)
	if not pending then return false, err end
	return pending:await()
end

RegisterNetEvent('opx_traumateam:careGo', function(token, kind, seconds, animation)
	if not math.tointeger(token) or (kind ~= 'revive' and kind ~= 'treat') or type(seconds) ~= 'number' then return end
	if caring then return TriggerServerEvent('opx_traumateam:careCancel', token) end
	caring = true
	CreateThread(function()
		local ok = progress({
			label = Ui.text(kind == 'revive' and 'bar_revive' or 'bar_treat'),
			duration = math.floor(seconds * 1000), canCancel = true,
			disableMovement = true, disableCombat = true, disableVehicle = true,
			animation = type(animation) == 'string' and { profile = animation } or nil,
		})
		caring = false
		TriggerServerEvent(ok == true and 'opx_traumateam:careDone' or 'opx_traumateam:careCancel', token)
	end)
end)

RegisterNetEvent('opx_traumateam:station', function(state, open) Ui.station(state, open == true) end)
RegisterNetEvent('opx_traumateam:dispatch', function(list, open) Ui.dispatch(list, open == true) end)
RegisterNetEvent('opx_traumateam:notify', function(key, kind, params) Ui.notify(key, kind, params) end)
RegisterNetEvent('opx_traumateam:route', function(position) Dispatch.setRoute(position, Ui.text('route_title')) end)

-- Eye callbacks (export names given to the target provider) ---------------------------------------------

-- canInteract: exactly true to show.
exports('ttCanCare', function() return Target.onDuty() == true end)

exports('ttRevive', function(ctx)
	local id = Target.playerOf(ctx)
	if id then TriggerServerEvent('opx_traumateam:careStart', 'revive', id) end
	return true
end)

exports('ttTreat', function(ctx)
	local id = Target.playerOf(ctx)
	if id then TriggerServerEvent('opx_traumateam:careStart', 'treat', id) end
	return true
end)

exports('ttDispatch', function()
	TriggerServerEvent('opx_traumateam:dispatchOpen')
	return true
end)

-- The target provider (re)started: its registry is empty, register again.
AddEventHandler('onClientResourceStart', function(name)
	CreateThread(function()
		Wait(500)
		if name == OPX.GetProvider('target') then Target.register(Ui.text) end
	end)
end)
