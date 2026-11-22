-- Eye options through the target provider's client exports (no manifest dependency): "Revive" and "Treat"
-- on players, "Trauma Team" (the open calls) on yourself. Shown only to an on-duty member (UX only: the
-- server checks everything). Registered again whenever the provider (re)starts.

local OPX = assert(require('@opx_core'))

local Target = {}

-- Whether the local character is a Trauma Team member on duty (opx_core's PlayerData mirror).
function Target.onDuty()
	local job = OPX.GetJob()
	return type(job) == 'table' and job.name == Config.job and job.onDuty == true
end

-- The player id of an eye context, or nil.
function Target.playerOf(ctx)
	local id = type(ctx) == 'table' and type(ctx.target) == 'table' and math.tointeger(tonumber(ctx.target.playerId))
	return id and id >= 1 and id or nil
end

function Target.register(text)
	local provider = OPX.GetProvider('target')
	if not provider then return end
	local pending = Open77.exports.call(provider, 'addPlayer', {
		{ name = 'opx_traumateam_revive', label = text('target_revive'), icon = 'medical', group = text('title'),
		  description = text('target_revive_desc'), distance = tonumber(Config.revive.distance) or 3.0,
		  canInteract = 'ttCanCare', onSelect = 'ttRevive' },
		{ name = 'opx_traumateam_treat', label = text('target_treat'), icon = 'heart', group = text('title'),
		  description = text('target_treat_desc'), distance = tonumber(Config.treat.distance) or 3.0,
		  canInteract = 'ttCanCare', onSelect = 'ttTreat' },
	})
	if pending then
		local id, reason = pending:await()
		if not id then print('[opx_traumateam] eye options refused: ' .. tostring(reason)) end
	end
	pending = Open77.exports.call(provider, 'addSelf', {
		{ name = 'opx_traumateam_dispatch', label = text('target_dispatch'), icon = 'list',
		  canInteract = 'ttCanCare', onSelect = 'ttDispatch' },
	})
	if pending then
		local id, reason = pending:await()
		if not id then print('[opx_traumateam] eye option refused: ' .. tostring(reason)) end
	end
end

return Target
