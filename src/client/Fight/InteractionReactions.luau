--!strict
-- Each victim supplies its own poses. These timelines select poses; staging
-- remains attacker-specific and never bakes a generic victim into an atlas.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
type Phase = { number | Types.AnimationName }
local timelines: { [string]: { Phase } } = {
	brakk = {
		{ 0.15, "Hit" },
		{ 0.33, "Pulled" },
		{ 0.45, "Grabbed" },
		{ 0.65, "Lifted" },
		{ 0.84, "Thrown" },
		{ 1, "Slammed" },
	},
	morrow = { { 0.36, "Pulled" }, { 0.68, "Suspended" }, { 0.87, "Launched" }, { 1, "Slammed" } },
	tidebreaker = { { 0.35, "Pulled" }, { 0.49, "Grabbed" }, { 0.75, "Lifted" }, { 1, "Slammed" } },
	glacia = { { 0.48, "Bound" }, { 0.79, "Suspended" }, { 1, "Slammed" } },
	byte = { { 0.7, "Bound" }, { 1, "Launched" } },
	kessa = { { 0.55, "Bound" }, { 1, "Suspended" } },
	hex = { { 0.68, "Bound" }, { 1, "Launched" } },
	astra = { { 0.62, "Suspended" }, { 0.85, "Launched" }, { 1, "Slammed" } },
	nocturne = { { 0.62, "Suspended" }, { 0.85, "Launched" }, { 1, "Slammed" } },
	sovereign = { { 0.44, "Bound" }, { 0.8, "Suspended" }, { 1, "Slammed" } },
	null = { { 0.6, "Suspended" }, { 0.86, "Launched" }, { 1, "Slammed" } },
}
local Reactions = {}
local defaultTimeline: { Phase } = { { 0.35, "Hit" }, { 0.85, "Launched" }, { 1, "Slammed" } }
function Reactions.sample(attacker: string, progress: number): (Types.AnimationName?, number?)
	local phases = timelines[attacker] or defaultTimeline
	local start = 0
	for _, phase in phases do
		local finish = phase[1] :: number
		if progress <= finish then
			return phase[2] :: Types.AnimationName, math.clamp((progress - start) / (finish - start), 0, 1)
		end
		start = finish
	end
	return phases[#phases][2] :: Types.AnimationName, 1
end
return Reactions
