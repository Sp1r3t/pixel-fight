--!strict
-- Weapon-linked signatures for the approved concepts. Bosses keep their tower progression.
local Types = require(script.Parent.Parent.Types)
local Profiles = require(script.Parent.CombatProfiles)
export type Signature = {
	specialName: string,
	superName: string,
	kind: string?,
	delivery: string?,
	params: Types.MoveParams?,
	duration: number?,
	hits: number?,
}
local data: { [string]: Signature } = {
	rook = { specialName = "Pulse Palm", superName = "Vanguard Breaker" },
	mira = { specialName = "Cyclone Heel", superName = "Thousand Step Storm" },
	brakk = { specialName = "Iron Hug", superName = "Tectonic Drop", delivery = "Grab" },
	juno = { specialName = "Orbit Disc", superName = "Satellite Storm" },
	sable = { specialName = "Shade Step", superName = "Eclipse Execution" },
	dax = { specialName = "Bulldozer Jab", superName = "Knockout Countdown" },
	wren = { specialName = "Talon Dive", superName = "Skyfall Talons" },
	sorren = { specialName = "Horizon Counter", superName = "Horizon Pierce" },
	pike = { specialName = "Longreach Lunge", superName = "Royal Phalanx" },
	zip = { specialName = "Rocket Rush", superName = "Afterburner" },
	ashka = { specialName = "Phoenix Rise", superName = "Solar Coronation" },
	glacia = { specialName = "Frost Line", superName = "Absolute Zero" },
	tempest = { specialName = "Thunderfall", superName = "Storm Sever" },
	byte = { specialName = "Glitch Mine", superName = "System Overload" },
	morrow = { specialName = "Soul Hook", superName = "Last Rites" },
	astra = { specialName = "Comet Lob", superName = "Supernova" },
	pip = {
		specialName = "Rattle Feint",
		superName = "Alley Riot",
		kind = "RushStrike",
		delivery = "Rush",
		duration = 2.8,
		hits = 8,
		params = { travelDistance = 5 },
	},
	ned = {
		specialName = "Root Breaker",
		superName = "Old Growth",
		kind = "GroundWave",
		delivery = "Barrage",
		duration = 3.2,
		hits = 5,
		params = { projectileSpeed = 19, projectileLifetime = 1.1 },
	},
	tally = {
		specialName = "Courier Loop",
		superName = "Express Disaster",
		kind = "Boomerang",
		delivery = "Barrage",
		duration = 2.8,
		hits = 8,
		params = { projectileSpeed = 25, travelDistance = 12 },
	},
	farrow = {
		specialName = "Veteran Bait",
		superName = "Last Watch",
		kind = "LongThrust",
		delivery = "Beam",
		duration = 2.8,
		hits = 8,
		params = { travelDistance = 2 },
	},
	kessa = {
		specialName = "Ring Parry",
		superName = "Clockwork Orbit",
		kind = "Boomerang",
		delivery = "Barrage",
		duration = 3.2,
		hits = 5,
		params = { projectileSpeed = 25, travelDistance = 12 },
	},
	vane = {
		specialName = "Corvid Dive",
		superName = "Black Parliament",
		kind = "DiveKick",
		delivery = "Rush",
		duration = 2.8,
		hits = 8,
		params = { travelDistance = 8, arcHeight = 8 },
	},
	grist = {
		specialName = "Forge Charge",
		superName = "World Forge",
		kind = "ArmorCharge",
		delivery = "Beam",
		duration = 3.2,
		hits = 5,
		params = { travelDistance = 5, armorHits = 2 },
	},
	juniper = {
		specialName = "Mountain Dive",
		superName = "Emerald Updraft",
		kind = "DiveKick",
		delivery = "Launcher",
		duration = 2.8,
		hits = 8,
		params = { travelDistance = 8, arcHeight = 8 },
	},
	oru = {
		specialName = "Shell Counter",
		superName = "Mountain Sutra",
		kind = "Counter",
		delivery = "Counter",
		duration = 3.2,
		hits = 5,
		params = {},
	},
	lise = {
		specialName = "Static Step",
		superName = "Ion Symphony",
		kind = "ArcProjectile",
		delivery = "Barrage",
		duration = 2.8,
		hits = 8,
		params = { projectileSpeed = 20, arcHeight = 4 },
	},
	cinder = {
		specialName = "Cinder Coil",
		superName = "Ashen Ouroboros",
		kind = "RisingStrike",
		delivery = "Launcher",
		duration = 2.8,
		hits = 8,
		params = { invincibleFrames = 6 },
	},
	rime = {
		specialName = "Glacial Bulwark",
		superName = "Frozen Bastion",
		kind = "GroundWave",
		delivery = "Beam",
		duration = 3.2,
		hits = 5,
		params = { projectileSpeed = 19, projectileLifetime = 1.1 },
	},
	hex = {
		specialName = "False Pixel Mine",
		superName = "Malware Cathedral",
		kind = "Trap",
		delivery = "Barrage",
		duration = 2.8,
		hits = 8,
		params = { trapLifetime = 5 },
	},
	tidebreaker = {
		specialName = "Abyss Hook",
		superName = "Sovereign Tide",
		kind = "Hook",
		delivery = "Grab",
		duration = 3.2,
		hits = 5,
		params = { pullDistance = 5 },
	},
	mae = {
		specialName = "Thunder Mark",
		superName = "Storm Court",
		kind = "OverheadLeap",
		delivery = "Launcher",
		duration = 3.2,
		hits = 5,
		params = { travelDistance = 5, arcHeight = 5 },
	},
	nocturne = {
		specialName = "Shadow Constellation",
		superName = "Night Parliament",
		kind = "ArcProjectile",
		delivery = "Beam",
		duration = 2.8,
		hits = 8,
		params = { projectileSpeed = 20, arcHeight = 4 },
	},
	abbot = {
		specialName = "Bell Ram",
		superName = "Iron Liturgy",
		kind = "ArmorCharge",
		delivery = "Rush",
		duration = 3.2,
		hits = 5,
		params = { travelDistance = 5, armorHits = 2 },
	},
	wraith = {
		specialName = "Mirror Reply",
		superName = "Broken Reflection",
		kind = "Counter",
		delivery = "Counter",
		duration = 2.8,
		hits = 8,
		params = {},
	},
	sovereign = {
		specialName = "Shadow Decree",
		superName = "Crown of Night",
		kind = "GroundWave",
		delivery = "Beam",
		duration = 2.8,
		hits = 8,
		params = { projectileSpeed = 19, projectileLifetime = 1.1 },
	},
	null = {
		specialName = "Null Axis",
		superName = "Event Horizon",
		kind = "LongThrust",
		delivery = "Beam",
		duration = 2.8,
		hits = 8,
		params = { travelDistance = 2 },
	},
}
local Signatures = {}
local cache: { [string]: Types.MoveData } = {}
function Signatures.get(id: string): Signature?
	local profile = Profiles.get(id)
	return data[if profile then profile.id else id]
end
function Signatures.move(id: string, moveId: string, original: Types.MoveData): Types.MoveData
	local signature = Signatures.get(id)
	if signature == nil then
		return original
	end
	local key = id .. ":" .. moveId .. ":" .. original.name
	local prior = cache[key]
	if prior then
		return prior
	end
	local move = table.clone(original)
	move.hitbox = table.clone(original.hitbox)
	move.name = if moveId == "Super" then signature.superName else signature.specialName
	if signature.kind and moveId == "Special" then
		local kind = signature.kind
		move.guard = if kind == "GroundWave" or kind == "Trap"
			then "Low"
			elseif kind == "DiveKick" or kind == "OverheadLeap" then "Overhead"
			else "Mid"
		move.hits = if kind == "ArmorCharge" then 2 else 1
		move.startup = if kind == "GroundWave" or kind == "ArmorCharge" then 22 elseif kind == "Counter" then 8 else 14
		move.active = if kind == "Counter"
				or kind == "ArmorCharge"
				or kind == "DiveKick"
			then 12
			elseif kind == "GroundWave" or kind == "Trap" or kind == "ArcProjectile" or kind == "Boomerang" then 2
			else 5
		move.recovery = if kind == "Counter" then 24 else 22
		if kind == "GroundWave" then
			move.hitbox = { x = 3, y = 1, w = 3, h = 2 }
		elseif kind == "LongThrust" or kind == "Hook" then
			move.hitbox = { x = 5, y = 3.3, w = 7, h = 1.8 }
		elseif kind == "Trap" then
			move.hitbox = { x = 4, y = 0.8, w = 2, h = 1.6 }
		elseif kind == "ArcProjectile" or kind == "Boomerang" then
			move.hitbox = { x = 2, y = 3.8, w = 1.8, h = 1.8 }
		else
			move.hitbox = { x = 2.5, y = 3, w = 4, h = 4 }
		end
	elseif signature.delivery and moveId == "Super" then
		local delivery = signature.delivery
		move.guard = if delivery == "Grab" then "Unblockable" else "Mid"
		move.startup = if delivery == "Beam" or delivery == "Barrage" then 18 else 12
		move.active = if delivery == "Counter" then 18 elseif delivery == "Barrage" then 40 else 5
		move.hits = if delivery == "Barrage" then 6 else 1
		if delivery == "Beam" or delivery == "Barrage" then
			move.hitbox = { x = 9, y = 3, w = 17, h = 6 }
		elseif delivery == "Grab" then
			local profile = Profiles.get(id)
			move.hitbox = if profile and profile.id == "brakk"
				then { x = 4.5, y = 3, w = 7, h = 3 }
				else { x = 2, y = 3, w = 3, h = 5 }
		else
			move.hitbox = { x = 2.5, y = 3, w = 4, h = 5 }
		end
	end
	cache[key] = move
	return move
end
return Signatures
