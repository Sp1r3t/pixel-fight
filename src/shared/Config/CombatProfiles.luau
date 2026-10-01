--!strict
-- Approved concept identities: weapon use and body class are gameplay data.
local Types = require(script.Parent.Parent.Types)
local Profiles = {}
export type Profile = {
	id: string,
	weapon: string,
	role: string,
	names: { string },
	heavy: string,
	reach: number,
	tempo: number,
	projectile: string?,
}
local profiles: { [string]: Profile } = {
	rook = {
		id = "rook",
		weapon = "Wraps",
		role = "balanced",
		names = { "lead jab", "rear cross", "rising uppercut" },
		heavy = "chambered pivot roundhouse",
		reach = 1,
		tempo = 1.04,
	},
	mira = {
		id = "mira",
		weapon = "Kickboxer",
		role = "agile",
		names = { "lead jab", "rear cross", "spinning back kick" },
		heavy = "pivoted roundhouse",
		reach = 1.08,
		tempo = 0.87,
	},
	brakk = {
		id = "brakk",
		weapon = "Grappler",
		role = "tank",
		names = { "body hook", "opposite elbow", "shoulder ram" },
		heavy = "two-handed overhead hammerfist",
		reach = 1.08,
		tempo = 1.24,
	},
	juno = {
		id = "juno",
		weapon = "Disc",
		role = "ranged",
		names = { "sidearm disc throw", "backhand disc throw", "rising disc throw" },
		heavy = "double spinning disc launch",
		reach = 1,
		tempo = 1.04,
		projectile = "Boomerang",
	},
	sable = {
		id = "sable",
		weapon = "DualKnives",
		role = "agile",
		names = { "front dagger stab", "rear dagger reverse stab", "crossing knife cuts" },
		heavy = "two-knife overhead diagonal slash",
		reach = 1.13,
		tempo = 0.87,
	},
	dax = {
		id = "dax",
		weapon = "Boxing",
		role = "tank",
		names = { "left jab", "right cross", "left hook" },
		heavy = "rear overhand power punch",
		reach = 0.94,
		tempo = 1.24,
	},
	wren = {
		id = "wren",
		weapon = "DualBatons",
		role = "agile",
		names = { "front baton snap", "rear baton strike", "crossed baton sweep" },
		heavy = "two-baton overhead strike",
		reach = 1.22,
		tempo = 0.87,
	},
	sorren = {
		id = "sorren",
		weapon = "Spear",
		role = "ranged",
		names = { "long two-hand spear thrust", "withdrawing low thrust", "rising spear thrust" },
		heavy = "braced two-hand spear lunge",
		reach = 1.72,
		tempo = 1.04,
	},
	pike = {
		id = "pike",
		weapon = "Spear",
		role = "ranged",
		names = { "measured spear jab", "low spear jab", "full step spear thrust" },
		heavy = "long braced thrust",
		reach = 1.72,
		tempo = 1.04,
	},
	zip = {
		id = "zip",
		weapon = "DualBatons",
		role = "agile",
		names = { "right electric baton", "left electric baton", "crossed electrical cuts" },
		heavy = "rolling two-baton scissor strike",
		reach = 1.22,
		tempo = 0.87,
	},
	ashka = {
		id = "ashka",
		weapon = "Fans",
		role = "balanced",
		names = { "front fan slash", "back fan reverse slash", "crossed fan cuts" },
		heavy = "two-fan rising arc",
		reach = 1.24,
		tempo = 1.04,
	},
	glacia = {
		id = "glacia",
		weapon = "Staff",
		role = "ranged",
		names = { "staff ice shot", "shield-backed staff thrust", "rising staff crystal burst" },
		heavy = "two-hand staff frost blast",
		reach = 1.4,
		tempo = 1.04,
		projectile = "Projectile",
	},
	tempest = {
		id = "tempest",
		weapon = "Katana",
		role = "balanced",
		names = { "draw cut", "reverse upward katana cut", "two-hand diagonal katana slash" },
		heavy = "overhead katana cleave",
		reach = 1.45,
		tempo = 1.04,
	},
	byte = {
		id = "byte",
		weapon = "Drone",
		role = "agile",
		names = { "wrist pulse", "opposite wrist pulse", "drone-guided double shot" },
		heavy = "charged wrist plasma shot",
		reach = 1,
		tempo = 0.87,
		projectile = "Projectile",
	},
	morrow = {
		id = "morrow",
		weapon = "ChainSickle",
		role = "ranged",
		names = { "chain-sickle throw", "reverse chain sweep", "overhead sickle cast" },
		heavy = "full-extension chain hook",
		reach = 1.78,
		tempo = 1.04,
	},
	astra = {
		id = "astra",
		weapon = "Magic",
		role = "ranged",
		names = { "left-hand star toss", "right-hand comet toss", "two-hand orbit release" },
		heavy = "charged star-core projectile",
		reach = 1,
		tempo = 1.04,
		projectile = "Projectile",
	},
	pip = {
		id = "pip",
		weapon = "Wraps",
		role = "agile",
		names = { "short jab", "sneaky reverse jab", "low uppercut" },
		heavy = "leaping dirty hook",
		reach = 1,
		tempo = 0.87,
	},
	ned = {
		id = "ned",
		weapon = "Club",
		role = "tank",
		names = { "club side swing", "reverse club sweep", "club butt thrust" },
		heavy = "overhead log smash",
		reach = 1.45,
		tempo = 1.24,
	},
	tally = {
		id = "tally",
		weapon = "Disc",
		role = "agile",
		names = { "right parcel throw", "left parcel throw", "crossed parcel toss" },
		heavy = "double overhead parcel launch",
		reach = 1,
		tempo = 0.87,
		projectile = "Boomerang",
	},
	farrow = {
		id = "farrow",
		weapon = "Spear",
		role = "ranged",
		names = { "long spear poke", "low shaft sweep", "counter spear thrust" },
		heavy = "stepping braced spear thrust",
		reach = 1.72,
		tempo = 1.04,
	},
	kessa = {
		id = "kessa",
		weapon = "Disc",
		role = "tank",
		names = { "front shield throw", "rear ring throw", "dual ring sweep" },
		heavy = "double orbiting ring launch",
		reach = 1,
		tempo = 1.24,
		projectile = "Boomerang",
	},
	vane = {
		id = "vane",
		weapon = "DualKnives",
		role = "agile",
		names = { "leading knife stab", "opposite reverse stab", "crossed feather cuts" },
		heavy = "wing-assisted overhead knife cut",
		reach = 1.13,
		tempo = 0.87,
	},
	grist = {
		id = "grist",
		weapon = "Hammer",
		role = "tank",
		names = { "short hammer jab", "reverse hammer sweep", "upward hammer scoop" },
		heavy = "overhead forging hammer smash",
		reach = 1.5,
		tempo = 1.24,
	},
	juniper = {
		id = "juniper",
		weapon = "Talons",
		role = "agile",
		names = { "front talon rake", "rear wing slash", "rising claw cut" },
		heavy = "two-wing downward talon strike",
		reach = 1.15,
		tempo = 0.87,
	},
	oru = {
		id = "oru",
		weapon = "Staff",
		role = "tank",
		names = { "staff jab", "staff reverse sweep", "staff-tip counter" },
		heavy = "two-hand staff ground slam",
		reach = 1.4,
		tempo = 1.24,
	},
	lise = {
		id = "lise",
		weapon = "Magic",
		role = "agile",
		names = { "front electric orb", "rear electric orb", "two-hand lightning scatter" },
		heavy = "charged electric sphere",
		reach = 1,
		tempo = 0.87,
		projectile = "Projectile",
	},
	cinder = {
		id = "cinder",
		weapon = "Talons",
		role = "agile",
		names = { "right flaming claw", "left reverse claw", "tail-backed claw uppercut" },
		heavy = "two-claw downward fire slash",
		reach = 1.15,
		tempo = 0.87,
	},
	rime = {
		id = "rime",
		weapon = "Shield",
		role = "tank",
		names = { "shield shove", "ice fist uppercut", "shield edge sweep" },
		heavy = "two-arm shield slam",
		reach = 1.15,
		tempo = 1.24,
	},
	hex = {
		id = "hex",
		weapon = "Drone",
		role = "agile",
		names = { "drone marker shot", "cyberclaw electric swipe", "wrist-drone crossfire" },
		heavy = "charged drone plasma burst",
		reach = 1,
		tempo = 0.87,
		projectile = "Projectile",
	},
	tidebreaker = {
		id = "tidebreaker",
		weapon = "ChainSickle",
		role = "tank",
		names = { "hook cast", "reverse tentacle-hook sweep", "overhead hook throw" },
		heavy = "two-arm hook pull slam",
		reach = 1.78,
		tempo = 1.24,
	},
	mae = {
		id = "mae",
		weapon = "Club",
		role = "tank",
		names = { "club horizontal blow", "reverse club blow", "short club lift" },
		heavy = "overhead thunder club smash",
		reach = 1.45,
		tempo = 1.24,
	},
	nocturne = {
		id = "nocturne",
		weapon = "Magic",
		role = "ranged",
		names = { "left void orb", "right star shard", "twin spectral orbit" },
		heavy = "charged void-mask projectile",
		reach = 1,
		tempo = 1.04,
		projectile = "Projectile",
	},
	abbot = {
		id = "abbot",
		weapon = "Bells",
		role = "tank",
		names = { "front bell ram", "rear bell uppercut", "double bell clap" },
		heavy = "overhead twin-bell smash",
		reach = 1.2,
		tempo = 1.24,
	},
	wraith = {
		id = "wraith",
		weapon = "Magic",
		role = "agile",
		names = { "left shard cast", "right reflected shard cast", "orbiting shard cut" },
		heavy = "large mirror-shard projection",
		reach = 1,
		tempo = 0.87,
		projectile = "Projectile",
	},
	sovereign = {
		id = "sovereign",
		weapon = "Staff",
		role = "ranged",
		names = { "staff soul shot", "staff reverse cut", "staff-tip soul lance" },
		heavy = "two-handed staff curse burst",
		reach = 1.4,
		tempo = 1.04,
		projectile = "Projectile",
	},
	null = {
		id = "null",
		weapon = "OrbitBlades",
		role = "ranged",
		names = { "front orbit blade launch", "rear orbit blade launch", "crossed blade return" },
		heavy = "four-plate spear formation cast",
		reach = 1,
		tempo = 1.04,
		projectile = "Projectile",
	},
}
local visualToId: { [string]: string } = {
	street_champion = "pip",
	iron_brute = "ned",
	swamp_mutant = "tally",
	alien_hunter = "farrow",
	tree_ancient = "kessa",
	bone_warlock = "vane",
	deep_kraken = "grist",
	siege_robot = "juniper",
	horned_beast = "oru",
	tung_sahur = "lise",
	lava_titan = "cinder",
	frost_golem = "rime",
	cyber_alien = "hex",
	abyss_kraken = "tidebreaker",
	arena_champion = "mae",
	void_oracle = "nocturne",
	iron_brute_abbot = "abbot",
	mirror_wraith = "wraith",
	shadow_demon = "sovereign",
	null_emperor = "null",
}
function Profiles.get(id: string): Profile?
	return profiles[visualToId[id] or id]
end
local cache: { [string]: { [string]: Types.MoveData } } = {}
function Profiles.normal(id: string, moveId: string, original: Types.MoveData): Types.MoveData
	local profile = Profiles.get(id)
	if profile == nil then
		return original
	end
	local group = cache[profile.id]
	if group == nil then
		group = {}
		cache[profile.id] = group
	end
	if group[moveId] then
		return group[moveId]
	end
	local move = table.clone(original)
	move.hitbox = table.clone(original.hitbox)
	local step = if moveId == "Light2" then 2 elseif moveId == "Light3" then 3 else 1
	move.name = if moveId == "Heavy"
			or moveId == "AirHeavy"
			or moveId == "CrouchHeavy"
		then profile.heavy
		else profile.names[step]
	move.startup = math.max(3, math.floor(original.startup * profile.tempo + 0.5))
	move.recovery = math.max(4, math.floor(original.recovery * profile.tempo + 0.5))
	-- Reach extends along the weapon. Low/air guard rules remain those of the input.
	move.hitbox.x *= profile.reach
	move.hitbox.w *= profile.reach
	if profile.projectile then
		move.startup = math.max(move.startup, 9 + step)
		move.recovery = math.max(move.recovery, 14)
		move.hitbox.x = 2
		move.hitbox.w = 1.2
		move.hitbox.h = math.min(move.hitbox.h, 1.5)
	end
	if profile.role == "tank" and moveId == "Heavy" then
		move.knockback *= 1.2
	end
	group[moveId] = move
	return move
end
return Profiles
