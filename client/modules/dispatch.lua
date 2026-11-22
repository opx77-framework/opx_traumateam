-- The medic's side of a call he took: a routable map pin with the native GPS route (Open77.blips), removed
-- when he drops the call, the call closes or the character is unloaded. Station and kiosk pins live here too.

local Dispatch = {}

local route = nil -- blip id of the current route
local pins = {}   -- blip ids of the stations and kiosks

local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end

function Dispatch.clearRoute()
	if route then pcall(Open77.blips.remove, route) end
	route = nil
end

-- position = { x, y, z } or false (clear).
function Dispatch.setRoute(position, title)
	Dispatch.clearRoute()
	if type(position) ~= 'table' or not finite(position.x) or not finite(position.y) or not finite(position.z) then return end
	local ok, id, reason = pcall(Open77.blips.create, {
		position = { x = position.x, y = position.y, z = position.z }, routable = true, title = title,
	})
	if not ok or not id then
		return print(('[opx_traumateam] route pin refused: %s'):format(tostring(ok and reason or id)))
	end
	route = id
	local tracked, why = pcall(Open77.blips.track, id)
	if not tracked then print(('[opx_traumateam] route not tracked: %s'):format(tostring(why))) end
end

-- Pins of Config.stations and Config.kiosks (Config.blips).
function Dispatch.showPins(stationTitle, kioskTitle)
	Dispatch.hidePins()
	if not Config.blips then return end
	local function add(point, title)
		local ok, id = pcall(Open77.blips.create, {
			position = { x = point.x, y = point.y, z = point.z }, sprite = 'meds',
			title = title, description = tostring(point.label or ''),
		})
		if ok and id then pins[#pins + 1] = id end
	end
	for _, point in ipairs(Config.stations) do add(point, stationTitle) end
	for _, point in ipairs(Config.kiosks) do add(point, kioskTitle) end
end

function Dispatch.hidePins()
	for _, id in ipairs(pins) do pcall(Open77.blips.remove, id) end
	pins = {}
end

return Dispatch
