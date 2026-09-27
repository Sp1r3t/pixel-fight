--[[
	Прогон «ИИ против ИИ» для настройки сложности боссов (без Roblox, в Lune):

	    lune run tests/tools/ai-duel.luau <уровень A> <уровень B> [матчей=10] [персонаж A=rook] [персонаж B=A]

	Уровень — номер босса 1..20 (профиль мастерства по кривой сложности, стиль «Универсал»);
	уровень 0 — простой «напористый» бот (идёт вперёд и часто бьёт), модель игрока-новичка.
	Матч — до одной победы в раунде. Печатает счёт и статистику событий боя.
]]

local process = require("@lune/process")
local RobloxRequire = require("../lib/RobloxRequire")

local loader = RobloxRequire.new()
local function shared(...)
	return loader.require(loader.get("ReplicatedStorage", "Shared", ...))
end
local function server(...)
	return loader.require(loader.get("ServerScriptService", "Server", ...))
end

local Simulation = shared("Combat", "Simulation")
local MatchFlow = shared("Combat", "MatchFlow")
local InputBits = shared("Combat", "InputBits")
local BossRegistry = shared("Characters", "BossRegistry")
local Rng = shared("Util", "Rng")
local BossAI = server("AI", "BossAI")

local levelA = tonumber(process.args[1]) or 1
local levelB = tonumber(process.args[2]) or 20
local matches = tonumber(process.args[3]) or 10
local character = process.args[4] or "rook"
local characterB = process.args[5] or character

-- «Новичок»: идёт вперёд, вблизи жмёт случайные кнопки, почти не блокирует.
local function rushBot(seed: number)
	local rng = Rng.new(seed)
	local cooldown, blocking = 0, 0
	return function(sim, slot)
		local me, opponent = sim.fighters[slot], sim.fighters[3 - slot]
		local forward = if opponent.x > me.x then InputBits.Right else InputBits.Left
		local back = if opponent.x > me.x then InputBits.Left else InputBits.Right
		local distance = math.abs(opponent.x - me.x)
		cooldown -= 1
		blocking -= 1
		if opponent.state == "Attack" and distance < 5 and blocking <= 0 and Rng.chance(rng, 0.03) then
			blocking = 20
		end
		if blocking > 0 then
			return { held = back, pressed = 0 }
		elseif distance > 3 then
			return { held = forward, pressed = 0 }
		elseif cooldown <= 0 then
			cooldown = Rng.integer(rng, 8, 20)
			local roll = Rng.next(rng)
			local pressed = if roll < 0.5
				then InputBits.Light
				elseif roll < 0.8 then InputBits.Heavy
				elseif roll < 0.95 then InputBits.Special
				else InputBits.Super
			return { held = if Rng.chance(rng, 0.2) then InputBits.Down else 0, pressed = pressed }
		end
		return { held = 0, pressed = 0 }
	end
end

local function controller(level: number, seed: number)
	if level == 0 then
		return rushBot(seed)
	end
	local brain = BossAI.new(BossRegistry.profileForLevel(level), seed)
	return function(sim, slot)
		return BossAI.think(brain, sim, slot)
	end
end

local wins = { 0, 0 }
local stats: { [string]: number } = {}
local frames = 0
local started = os.clock()
for index = 1, matches do
	local sim = Simulation.new({ characters = { character, characterB } })
	sim.fighters[1].tapDash = levelA == 0
	sim.fighters[2].tapDash = levelB == 0
	local flow = MatchFlow.new({ roundsToWin = 1 })
	MatchFlow.start(flow, sim)
	local a = controller(levelA, index * 7919)
	local b = controller(levelB, index * 104729)
	while not flow.finished do
		Simulation.step(sim, { a(sim, 1), b(sim, 2) })
		for _, event in sim.events do
			if event.attacker then
				local key = `{event.kind} by {event.attacker}` .. (if event.tag then `/{event.tag}` else "")
				stats[key] = (stats[key] or 0) + 1
			end
		end
		MatchFlow.step(flow, sim)
		frames += 1
	end
	if flow.matchWinner > 0 then
		wins[flow.matchWinner] += 1
	end
end

print(
	`уровень {levelA} ({character}): {wins[1]} побед · уровень {levelB} ({characterB}): {wins[2]} побед, {matches} матчей`
)
print(`кадров {frames}, {string.format("%.2f", os.clock() - started)} с`)
local keys = {}
for key in stats do
	table.insert(keys, key)
end
table.sort(keys)
for _, key in keys do
	print(`  {key}: {stats[key]}`)
end
