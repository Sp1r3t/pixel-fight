--!strict
--[[
	FightController — клиентская сторона боя.

	  • MatchStart → строит арену и бойцов, включает камеру боя и отправку ввода, открывает экран боя;
	  • Snapshot   → кладёт снапшоты в буфер интерполяции;
	  • Events     → проигрывает эффекты в тот кадр, когда их «видно» на экране;
	  • каждый кадр → интерполирует состояние, обновляет бойцов, камеру и данные HUD;
	  • MatchEnd   → убирает всё и возвращает в меню.
	Клиент ничего не решает в бою — только показывает то, что прислал сервер.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local Types = require(ReplicatedStorage.Shared.Types)
local Snapshot = require(ReplicatedStorage.Shared.Combat.Snapshot)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local Arena = require(script.Parent.Parent.Fight.Arena)
local FighterView = require(script.Parent.Parent.Fight.FighterView)
local SnapshotBuffer = require(script.Parent.Parent.Fight.SnapshotBuffer)
local AppState = require(script.Parent.Parent.UI.AppState)
local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local InputController = require(script.Parent.InputController)
local SparkStyles = require(script.Parent.Parent.Fight.SparkStyles)
local ProjectileView = require(script.Parent.Parent.Fight.ProjectileView)
local Cinematics = require(script.Parent.Parent.Fight.Cinematics)
local CosmeticStyles = require(script.Parent.Parent.Fight.CosmeticStyles)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local UIController = require(script.Parent.UIController)

local peek = Fusion.peek

type NetEvent = {
	k: string,
	s: number,
	f: number,
	x: number?,
	y: number?,
	v: number?,
	a: number?,
	t: string?,
	r: number?,
	w: { number }?,
	fin: boolean?,
	ms: { number }?,
}

local TICK = 60
local BANNER_WHITE = Color3.new(1, 1, 1)
local BANNER_GOLD = Color3.fromHex("#FFC845")
local BANNER_RED = Color3.fromHex("#FF4D6D")
local BANNER_GREEN = Color3.fromHex("#5BD17A")

local RESULT_TEXT: { [string]: { text: string, color: Color3 } } = {
	KO = { text = "K.O.", color = BANNER_RED },
	Perfect = { text = "PERFECT", color = BANNER_GOLD },
	Time = { text = "TIME", color = BANNER_WHITE },
	Draw = { text = "DRAW", color = BANNER_WHITE },
	DoubleKO = { text = "DOUBLE K.O.", color = BANNER_RED },
}

local FightController = {
	Name = "FightController",
}

local matchId: number? = nil
local battleInfo: AppState.BattleInfo? = nil
local arena: Arena.Arena? = nil
local views: { [number]: FighterView.FighterView } = {}
local buffer = SnapshotBuffer.new()
local pendingEvents: { NetEvent } = {}
local lastSample: SnapshotBuffer.Sample? = nil
local projectileViews: ProjectileView.ProjectileViews? = nil
-- Deluxe-косметика: накопители частиц ауры и шлейфа по слотам.
local auraCarry: { [number]: number } = {}
local trailCarry: { [number]: number } = {}
local cosmeticRng = Rng.new(31)

local function cleanup()
	Cinematics.stop()
	if projectileViews then
		projectileViews.destroy()
		projectileViews = nil
	end
	table.clear(auraCarry)
	table.clear(trailCarry)
	for _, view in views do
		view.destroy()
	end
	table.clear(views)
	if arena then
		arena.destroy()
		arena = nil
	end
	buffer.reset()
	table.clear(pendingEvents)
	lastSample = nil
	EffectsController.clear()
	InputController.setActive(false)
	CameraController.exitFight()
	matchId = nil
	battleInfo = nil
end

local function isHex(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

-- Свои цвета бойца (боссы). Данные из сети — проверяем формат.
local function readPalette(value: any): Types.Palette?
	if type(value) ~= "table" or not (isHex(value.primary) and isHex(value.secondary) and isHex(value.accent)) then
		return nil
	end
	return { primary = value.primary, secondary = value.secondary, accent = value.accent }
end

local function readBoss(value: any): AppState.BattleBoss?
	if type(value) ~= "table" or type(value.id) ~= "string" then
		return nil
	end
	local def = BossRegistry.get(value.id)
	if def == nil then
		return nil
	end
	return { id = def.id, order = def.order, name = def.name, title = def.title }
end

-- Описание персонажа для отрисовки с учётом своих цветов (боссы).
local function viewDefinition(def: Types.CharacterDef, palette: Types.Palette?): Types.CharacterDef
	if palette == nil then
		return def
	end
	local copy = table.clone(def) :: any
	copy.palette = palette
	return copy
end

-- Составы команд эстафеты (слот = команда).
local function readTeams(value: any): { { AppState.BattleMember } }?
	if type(value) ~= "table" or #value ~= 2 then
		return nil
	end
	local teams: { { AppState.BattleMember } } = {}
	for slot = 1, 2 do
		local team = value[slot]
		if type(team) ~= "table" or #team == 0 then
			return nil
		end
		local members: { AppState.BattleMember } = {}
		for _, member in team do
			if type(member) ~= "table" or type(member.characterId) ~= "string" then
				return nil
			end
			if CharacterRegistry.get(member.characterId) == nil then
				return nil
			end
			table.insert(members, {
				characterId = member.characterId,
				playerName = if type(member.playerName) == "string" then member.playerName else nil,
			})
		end
		teams[slot] = members
	end
	return teams
end

local function readSetup(payload: any): AppState.BattleInfo?
	if type(payload) ~= "table" or type(payload.matchId) ~= "number" or type(payload.fighters) ~= "table" then
		return nil
	end
	local fighters: { AppState.BattleFighter } = {}
	for _, fighter in payload.fighters do
		if
			type(fighter) == "table"
			and type(fighter.characterId) == "string"
			and CharacterRegistry.get(fighter.characterId)
		then
			table.insert(fighters, {
				slot = tonumber(fighter.slot) or #fighters + 1,
				characterId = fighter.characterId,
				playerName = if type(fighter.playerName) == "string" then fighter.playerName else nil,
				maxHealth = tonumber(fighter.maxHealth) or 1000,
				displayName = if type(fighter.displayName) == "string"
					then string.sub(fighter.displayName, 1, 40)
					else nil,
				palette = readPalette(fighter.palette),
			})
		end
	end
	if #fighters ~= 2 then
		return nil
	end
	return {
		matchId = payload.matchId,
		mode = if type(payload.mode) == "string" then payload.mode else "Training",
		arenaId = if type(payload.arenaId) == "string" then payload.arenaId else "dojo",
		localSlot = if type(payload.localSlot) == "number" then payload.localSlot else nil,
		fighters = fighters,
		roundsToWin = if type(payload.roundsToWin) == "number" then payload.roundsToWin else 0,
		boss = readBoss(payload.boss),
		teams = readTeams(payload.teams),
		localMember = if type(payload.localMember) == "number" then payload.localMember else nil,
	}
end

-- Управляет ли игрок бойцом сейчас (в эстафете — только когда на арене его участник).
local function isControlling(info: AppState.BattleInfo, members: { number }): boolean
	local localSlot = info.localSlot
	if localSlot == nil then
		return false
	end
	return info.teams == nil or members[localSlot] == info.localMember
end

--[[
	Эстафета: на арену вышли участники members (по командам). Меняем бойцов на экране,
	данные HUD и включаем/выключаем отправку ввода.
]]
local function applyMembers(members: { number })
	local info = battleInfo
	local teams = if info then info.teams else nil
	if info == nil or teams == nil then
		return
	end
	local fighters = table.clone(info.fighters)
	for index, fighter in fighters do
		local team = teams[fighter.slot]
		local member = if team then team[members[fighter.slot]] else nil
		if member and member.characterId ~= fighter.characterId then
			local updated = table.clone(fighter)
			updated.characterId = member.characterId
			updated.playerName = member.playerName
			fighters[index] = updated
			local def = CharacterRegistry.get(member.characterId)
			local folder = if arena then arena.folder else nil
			if def and folder then
				local old = views[fighter.slot]
				if old then
					old.destroy()
				end
				views[fighter.slot] = FighterView.new(folder, def, fighter.slot)
			end
		end
	end
	local updatedInfo = table.clone(info)
	updatedInfo.fighters = fighters
	battleInfo = updatedInfo
	local controlling = isControlling(updatedInfo, members)
	InputController.setActive(controlling)
	local state = UIController.getState()
	if state then
		state.battle:set(updatedInfo)
		state.hud.members:set(table.clone(members))
		state.hud.controlling:set(controlling)
	end
end

local function readMembers(value: any): { number }?
	if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
		return { value[1], value[2] }
	end
	return nil
end

local function onMatchStart(payload: any)
	local info = readSetup(payload)
	if info == nil then
		warn("[FightController] Некорректные данные начала матча")
		return
	end
	cleanup()
	matchId = info.matchId
	battleInfo = info
	local built = Arena.build(info.arenaId, Workspace)
	arena = built
	projectileViews = ProjectileView.new(built.folder)
	for _, fighter in info.fighters do
		local def = CharacterRegistry.get(fighter.characterId)
		if def then
			views[fighter.slot] = FighterView.new(built.folder, viewDefinition(def, fighter.palette), fighter.slot)
		end
	end
	CameraController.enterFight()
	InputController.setActive(isControlling(info, { 1, 1 }))
	local state = UIController.getState()
	if state then
		AppState.resetHud(state, info)
		AppState.enterBattle(state, info)
		if info.roundsToWin == 0 then
			AppState.showBanner(state, "TRAINING", 1.2, BANNER_GOLD)
		elseif info.boss then
			AppState.showBanner(state, `BOSS {info.boss.order}: {string.upper(info.boss.name)}`, 1.4, BANNER_RED)
		end
	end
end

local function onMatchEnd(payload: any)
	if type(payload) == "table" and payload.matchId ~= matchId then
		return -- конец уже неактуального матча
	end
	cleanup()
	local state = UIController.getState()
	if state then
		AppState.exitBattle(state)
		if type(payload) == "table" then
			local reason = payload.reason
			local won = payload.winner ~= nil and payload.winner ~= 0 and payload.winner == payload.localSlot
			if (reason == "PlayerLeft" or reason == "Left") and won then
				AppState.notify(state, "Соперник покинул бой — победа за вами")
			elseif reason == "Finished" and payload.localSlot ~= nil then
				AppState.notify(state, if won then "Победа!" else "Поражение")
			end
		end
	end
end

-- Итог боя с боссом (приходит после MatchEnd): награда и открытие следующего босса.
local function onBossResult(payload: any)
	local state = UIController.getState()
	if state == nil or type(payload) ~= "table" or type(payload.bossId) ~= "string" then
		return
	end
	local boss = BossRegistry.get(payload.bossId)
	if boss == nil then
		return
	end
	if payload.won ~= true then
		AppState.notify(state, `{boss.name} оказался сильнее. Попробуйте ещё раз!`, 4)
		return
	end
	local text = `{boss.name} повержен!`
	local reward = tonumber(payload.reward) or 0
	if reward > 0 then
		text ..= ` +{reward} монет.`
	end
	local unlocked = if type(payload.unlocked) == "string" then BossRegistry.get(payload.unlocked) else nil
	if unlocked then
		text ..= ` Открыт босс {unlocked.order}: {unlocked.name}`
	elseif boss.order == BossRegistry.count() and payload.firstClear == true then
		text ..= " Башня пройдена!"
	end
	AppState.notify(state, text, 5)
end

local function onEvents(events: any)
	if matchId == nil or type(events) ~= "table" then
		return
	end
	for _, event in events do
		if type(event) == "table" and type(event.k) == "string" and type(event.f) == "number" then
			table.insert(pendingEvents, event)
		end
	end
end

-- События раундов: надписи и счёт побед в HUD.
local function playFlowEvent(event: NetEvent)
	local state = UIController.getState()
	if state == nil then
		return
	end
	local hud = state.hud
	if event.w then
		hud.wins:set(table.clone(event.w))
	end
	local kind = event.k
	local members = readMembers(event.ms)
	if kind == "RoundStart" then
		hud.round:set(event.r or 1)
		local text = if event.fin then "FINAL ROUND" else `ROUND {event.r or 1}`
		AppState.showBanner(state, text, 1, BANNER_WHITE)
		if members then
			hud.eliminated:set({ {}, {} })
			applyMembers(members)
		end
	elseif kind == "DuelEnd" then
		-- Эстафета: дуэль окончена, проигравший выбывает до конца раунда.
		local result = RESULT_TEXT[event.t or "KO"] or RESULT_TEXT.KO
		AppState.showBanner(state, result.text, 1.5, result.color)
		local current = peek(hud.members)
		local eliminated = table.clone(peek(hud.eliminated))
		for slot = 1, 2 do
			if event.s == 0 or event.s == 3 - slot then
				local set = table.clone(eliminated[slot] or {})
				set[current[slot]] = true
				eliminated[slot] = set
			end
		end
		hud.eliminated:set(eliminated)
	elseif kind == "Relay" then
		if members then
			applyMembers(members)
		end
		local characterId: string? = nil
		local fighters: { AppState.BattleFighter } = if battleInfo then battleInfo.fighters else {}
		for _, fighter in fighters do
			if fighter.slot == event.s then
				characterId = fighter.characterId
			end
		end
		local def = if characterId then CharacterRegistry.get(characterId) else nil
		if def then
			AppState.showBanner(state, `NEXT: {string.upper(def.displayName)}`, 1.2, BANNER_GOLD)
		end
	elseif kind == "Fight" then
		AppState.showBanner(state, "FIGHT!", 0.8, BANNER_GOLD)
	elseif kind == "RoundEnd" then
		local result = RESULT_TEXT[event.t or "KO"] or RESULT_TEXT.KO
		AppState.showBanner(state, result.text, 1.8, result.color)
	elseif kind == "MatchEnd" then
		local localSlot = if battleInfo then battleInfo.localSlot else nil
		if localSlot ~= nil then
			local won = event.s == localSlot
			AppState.showBanner(
				state,
				if won then "YOU WIN!" else "YOU LOSE",
				3,
				if won then BANNER_GREEN else BANNER_RED
			)
		else
			local winnerName = "PLAYER"
			if battleInfo then
				for _, fighter in battleInfo.fighters do
					if fighter.slot == event.s then
						local def = CharacterRegistry.get(fighter.characterId)
						local name = fighter.displayName or (if def then def.displayName else fighter.characterId)
						winnerName = string.upper(name)
					end
				end
			end
			AppState.showBanner(state, `{winnerName} WINS`, 3, BANNER_GOLD)
		end
	end
end

-- Сила эффекта удара: 0.3 (лёгкий) … 1.5+ (супер).
local function strengthOf(damage: number?): number
	return math.clamp((damage or 30) / 60, 0.3, 1.6)
end

local function playEvent(event: NetEvent)
	local x, y = event.x or 0, event.y or 0
	local kind = event.k
	if kind == "Jump" or kind == "Land" then
		EffectsController.dust(x, y, nil)
	elseif kind == "Dash" or kind == "Backdash" then
		local facing = if lastSample and lastSample.fighters[event.s] then lastSample.fighters[event.s].facing else 1
		-- Пыль летит назад от направления рывка.
		EffectsController.dust(x, y, if kind == "Dash" then -facing else facing)
	elseif kind == "Knockdown" then
		EffectsController.dust(x, y, nil)
		CameraController.shake(0.25, 0.15)
	elseif kind == "Hit" or kind == "CinematicHit" then
		local attackerView = if event.a then views[event.a] else nil
		local defenderView = views[event.s]
		local style = SparkStyles.get(if attackerView then attackerView.def.cosmetics.hitSpark else "Impact")
		local defenderX = if lastSample and lastSample.fighters[event.s] then lastSample.fighters[event.s].x else x
		local direction = if defenderX >= x then 1 else -1
		local strength = if event.t == "Super" then 1.4 else strengthOf(event.v)
		local hitX, hitY = x, y
		if kind == "CinematicHit" and defenderView then
			-- В ролике противник смещён постановкой — искры там, где его видно.
			local position = defenderView.anchor.CFrame.Position
			hitX, hitY = position.X, position.Y
			Cinematics.hit()
		end
		EffectsController.hitSpark(hitX, hitY, strength, style.primary, style.secondary, direction)
		if defenderView then
			defenderView.flash(1)
		end
		CameraController.shake(0.15 + 0.35 * strength, 0.12 + 0.1 * strength)
		if event.t == "Counter" then
			EffectsController.screenFlash(style.secondary, 0.12, 0.25)
		end
	elseif kind == "Block" then
		local style = SparkStyles.block()
		local defenderX = if lastSample and lastSample.fighters[event.s] then lastSample.fighters[event.s].x else x
		EffectsController.hitSpark(x, y, 0.35, style.primary, style.secondary, if defenderX >= x then 1 else -1)
		CameraController.shake(0.08, 0.08)
	elseif kind == "Armor" then
		EffectsController.hitSpark(x, y, 0.6, Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 240, 200), 1)
		CameraController.shake(0.2, 0.12)
	elseif kind == "KO" then
		EffectsController.screenFlash(Color3.new(1, 1, 1), 0.5, 0.7)
		CameraController.shake(0.9, 0.5)
	elseif kind == "SuperFlash" then
		local view = views[event.s]
		local color = if view then Color3.fromHex(view.def.cosmetics.superFlash) else Color3.new(1, 1, 1)
		EffectsController.screenFlash(color, 0.45, 0.55)
		CameraController.shake(0.3, 0.3)
	elseif kind == "CinematicStart" then
		EffectsController.screenFlash(Color3.new(1, 1, 1), 0.25, 0.8)
		local attackerView = views[event.s]
		local defenderView = views[3 - event.s]
		local sample = lastSample
		if attackerView and defenderView and arena and sample then
			local def = attackerView.def
			Cinematics.start({
				folder = arena.folder,
				attacker = attackerView,
				defender = defenderView,
				attackerX = sample.fighters[event.s].x,
				defenderX = sample.fighters[3 - event.s].x,
				duration = (event.v or 120) / TICK,
				hits = def.super.cinematic.hits,
			})
			local state = UIController.getState()
			if state then
				AppState.showBanner(
					state,
					string.upper(def.super.move.name),
					1.2,
					Color3.fromHex(def.cosmetics.superFlash)
				)
			end
		end
	elseif kind == "CinematicEnd" then
		Cinematics.stop()
		CameraController.shake(0.7, 0.35)
	elseif kind == "Parry" then
		-- Контратака: белая вспышка, «звон» и надпись.
		EffectsController.screenFlash(Color3.new(1, 1, 1), 0.15, 0.5)
		EffectsController.hitSpark(x, y, 1, Color3.new(1, 1, 1), Color3.fromRGB(150, 220, 255), 1)
		CameraController.shake(0.3, 0.2)
		local state = UIController.getState()
		if state then
			AppState.showBanner(state, "COUNTER!", 0.8, BANNER_GOLD)
		end
	elseif kind == "Vanish" or kind == "Appear" then
		-- Телепорт: облачко дыма, боец исчезает до появления.
		local view = views[event.s]
		if view then
			view.setVisible(kind == "Appear")
			local color = Color3.fromHex(view.def.palette.accent)
			EffectsController.burst(Vector3.new(x, y + 3, 0), {
				count = 14,
				color = color,
				secondary = Color3.fromRGB(40, 30, 60),
				speed = 7,
				size = 0.5,
				life = 0.35,
				spread = 360,
			})
		end
	elseif kind == "Projectile" then
		local view = views[event.s]
		if view then
			local color = Color3.fromHex(view.def.palette.accent)
			EffectsController.burst(Vector3.new(x, y, 0), {
				count = 6,
				color = color,
				secondary = Color3.new(1, 1, 1),
				speed = 6,
				size = 0.3,
				life = 0.2,
				spread = 360,
			})
		end
	elseif kind == "ProjectileEnd" then
		if event.t == "Clash" or event.t == "Swept" or event.t == "Ground" or event.t == "Wall" then
			local strong = event.t == "Clash" or event.t == "Swept"
			EffectsController.burst(Vector3.new(x, y, 0), {
				count = if strong then 16 else 6,
				color = Color3.new(1, 1, 1),
				secondary = Color3.fromRGB(255, 214, 90),
				speed = if strong then 14 else 6,
				size = 0.35,
				life = 0.3,
				gravity = 6,
				spread = 360,
			})
			if strong then
				CameraController.shake(0.15, 0.1)
			end
		end
	elseif kind == "Mechanic" then
		-- Механика босса сработала (ярость): красная вспышка и надпись.
		EffectsController.screenFlash(BANNER_RED, 0.4, 0.35)
		CameraController.shake(0.35, 0.3)
		local state = UIController.getState()
		if state and event.t == "Enrage" then
			AppState.showBanner(state, "RAGE!", 1, BANNER_RED)
		end
	else
		playFlowEvent(event)
	end
end

local function onSnapshot(data: any)
	if matchId == nil or typeof(data) ~= "buffer" then
		return
	end
	local decoded = Snapshot.decode(data)
	if decoded then
		buffer.push(decoded, os.clock())
	end
end

-- Живые данные HUD из интерполированного снапшота.
local function updateHud(sample: SnapshotBuffer.Sample)
	local state = UIController.getState()
	if state == nil then
		return
	end
	local hud = state.hud
	for slot, fighter in sample.latest.fighters do
		local hudFighter = hud.fighters[slot]
		if hudFighter then
			hudFighter.health:set(fighter.health)
			hudFighter.maxHealth:set(fighter.maxHealth)
			hudFighter.meter:set(fighter.meter)
			hudFighter.combo:set(fighter.combo)
		end
	end
	if battleInfo and battleInfo.roundsToWin > 0 then
		hud.timer:set(math.ceil(sample.latest.timer / TICK))
	end
end

-- Deluxe-косметика: аура вокруг бойца и шлейф при рывках.
local function updateCosmetics(slot: number, view: FighterView.FighterView, fighter: any, dt: number)
	local cosmetics = view.def.cosmetics
	local aura = CosmeticStyles.aura(cosmetics.aura)
	local position = view.anchor.CFrame.Position
	if aura and fighter.state ~= "KO" then
		auraCarry[slot] = (auraCarry[slot] or 0) + dt * aura.rate
		while (auraCarry[slot] or 0) >= 1 do
			auraCarry[slot] -= 1
			local color = aura.colors[Rng.integer(cosmeticRng, 1, #aura.colors)]
			EffectsController.burst(
				Vector3.new(
					position.X + Rng.range(cosmeticRng, -aura.spread, aura.spread),
					fighter.y + Rng.range(cosmeticRng, 0.3, 5),
					-0.2
				),
				{
					count = 1,
					color = color,
					speed = math.abs(aura.rise) + 0.5,
					size = aura.size,
					life = aura.life,
					spread = 40,
					direction = if aura.rise >= 0 then 90 else -90,
				}
			)
		end
	end
	local trail = CosmeticStyles.trail(cosmetics.trail)
	local dashing = fighter.state == "Dash" or fighter.state == "Backdash" or math.abs(fighter.vx) > 14
	if trail and dashing then
		trailCarry[slot] = (trailCarry[slot] or 0) + dt * 40
		while (trailCarry[slot] or 0) >= 1 do
			trailCarry[slot] -= 1
			EffectsController.burst(Vector3.new(position.X, fighter.y + Rng.range(cosmeticRng, 1, 4.5), -0.1), {
				count = 2,
				color = trail.colors[1],
				secondary = trail.colors[2],
				speed = 1,
				size = trail.size,
				life = 0.3,
				spread = 360,
			})
		end
	end
end

local function onRenderStep(dt: number)
	if matchId == nil then
		return
	end
	local sample = buffer.sample(os.clock())
	if sample == nil then
		return
	end
	lastSample = sample

	local minX, maxX, topY = math.huge, -math.huge, 0
	Cinematics.update(dt)
	for slot, fighter in sample.fighters do
		local view = views[slot]
		if view then
			view.update(fighter, dt)
			updateCosmetics(slot, view, fighter, dt)
		end
		minX = math.min(minX, fighter.x)
		maxX = math.max(maxX, fighter.x)
		topY = math.max(topY, fighter.y + 5.6)
	end
	if minX <= maxX then
		CameraController.setFocus(minX, maxX, topY)
	end
	local projectiles = projectileViews
	if projectiles then
		projectiles.update(sample.projectiles, function(owner: number): Types.Palette?
			local view = views[owner]
			return if view then view.def.palette else nil
		end)
	end
	updateHud(sample)

	-- События показываем тогда, когда до них «дошла» интерполированная картинка.
	local index = 1
	while index <= #pendingEvents do
		local event = pendingEvents[index]
		if event.f <= sample.frame + 0.5 then
			table.remove(pendingEvents, index)
			playEvent(event)
		else
			index += 1
		end
	end
end

-- Текущий кадр отображения (для тестов и HUD).
function FightController.getSample(): SnapshotBuffer.Sample?
	return lastSample
end

function FightController.getViews(): { [number]: FighterView.FighterView }
	return views
end

function FightController.Init()
	Transport.onClientEvent("Snapshot", onSnapshot)
	Transport.onClientEvent("MatchEvent", function(kind: any, payload: any)
		if kind == "MatchStart" then
			onMatchStart(payload)
		elseif kind == "MatchEnd" then
			onMatchEnd(payload)
		elseif kind == "Events" then
			onEvents(payload)
		elseif kind == "BossResult" then
			onBossResult(payload)
		end
	end)
end

function FightController.Start()
	RunService:BindToRenderStep("PixelFightRender", Enum.RenderPriority.Camera.Value, onRenderStep)
end

return FightController
