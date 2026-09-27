--!strict
--[[
	Реактивное состояние интерфейса. Всё, что показывает UI, лежит здесь в Fusion Values:
	меняется значение → Fusion сам перерисовывает зависимые части экрана.

	Источники данных:
	  • действия игрока в меню (выбор экрана, персонажа);
	  • FightController — начало/конец боя и живые данные боя (HUD, этап 4);
	  • профиль с сервера (этап 9) — открытые персонажи, валюта, прогресс боссов.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local ControlsLayout = require(ReplicatedStorage.Shared.Config.ControlsLayout)
local Types = require(ReplicatedStorage.Shared.Types)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local Combos = require(ReplicatedStorage.Shared.Config.Combos)

local peek = Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

export type ScreenName =
	"MainMenu"
	| "ModeSelect"
	| "CharacterSelect"
	| "BossMap"
	| "Shop"
	| "ControlsSettings"
	| "Draft"
	| "Battle"
	| "ComboList"

export type BattleFighter = {
	slot: number,
	team: number, -- 1 или 2
	characterId: string,
	playerName: string?,
	maxHealth: number,
	displayName: string?, -- своё имя (боссы)
	palette: Types.Palette?, -- свои цвета (боссы)
}

export type BattleBoss = {
	id: string,
	order: number,
	name: string,
	title: string,
}

export type BattleInfo = {
	matchId: number,
	mode: string,
	arenaId: string,
	localSlot: number?,
	localTeam: number?,
	fighters: { BattleFighter }, -- по слотам: 2 (1 на 1) или 4 (2 на 2)
	stage: string, -- геометрия сцены (Combat/Stage): "Duel" | "TwoFloors"
	roundsToWin: number, -- 0 — без раундов (тренировка)
	boss: BattleBoss?,
}

-- Состояние поиска матча / приватной комнаты (присылает MatchmakingService).
export type QueueStatus = {
	status: string, -- "Idle" | "Searching" | "Found" | "Teleporting" | "Room"
	mode: string?, -- "Versus" | "Team"
	code: string?, -- код комнаты
	host: boolean?,
	members: { { name: string, characterId: string } }?,
	capacity: number?,
	since: number, -- os.clock() начала ожидания (для таймера на экране)
}

-- Подготовка к бою (выбор бойца → голосование за карту), присылает DraftService.
export type DraftSlotInfo = {
	slot: number,
	team: number,
	name: string,
	characterId: string,
	ready: boolean,
	bot: boolean,
	vote: string?,
}

export type DraftInfo = {
	id: number,
	mode: string, -- "Versus" | "Team" | "Cpu"
	phase: string, -- "Character" | "Map" | "Reveal"
	deadline: number, -- os.clock() конца фазы (на этом клиенте)
	localSlot: number?,
	slots: { DraftSlotInfo },
	votes: { [string]: number },
	arenaId: string?,
}

-- Живые данные бойца для HUD (обновляет FightController каждый кадр).
export type HudFighter = {
	health: Fusion.Value<number>,
	maxHealth: Fusion.Value<number>,
	meter: Fusion.Value<number>,
	-- Сколько ударов подряд пропустил боец (счётчик комбо показывается у атакующего).
	combo: Fusion.Value<number>,
}

export type Hud = {
	fighters: { HudFighter }, -- по слотам (4 записи; в 1 на 1 используются первые две)
	timer: Fusion.Value<number>, -- секунды; -1 — без ограничения
	round: Fusion.Value<number>,
	wins: Fusion.Value<{ number }>,
	roundsToWin: Fusion.Value<number>,
	banner: Fusion.Value<string>,
	bannerColor: Fusion.Value<Color3>,
	bannerSerial: Fusion.Value<number>,
	-- Название выполненного комбо у стороны того, кто его сделал.
	comboName: Fusion.Value<string>,
	comboTeam: Fusion.Value<number>,
	comboSerial: Fusion.Value<number>,
}

-- Действия, которые UI может попросить выполнить (реализует UIController).
export type Actions = {
	startTraining: () -> (),
	startBoss: (bossId: string) -> (),
	-- Мультиплеер.
	joinQueue: (mode: string) -> (),
	leaveQueue: () -> (),
	createRoom: (mode: string) -> (),
	joinRoom: (code: string) -> (),
	leaveRoom: () -> (),
	startCpu: (level: number, mode: string) -> (), -- mode: "Versus" (1 на 1) | "Team" (2 на 2 с ботами)
	roomStart: () -> (), -- хозяин комнаты начинает сразу, пустые места займут боты
	-- Подготовка к бою.
	draftPick: (characterId: string) -> (),
	draftReady: () -> (),
	draftVote: (arenaId: string) -> (),
	draftLeave: () -> (),
	-- Покупки.
	buyCharacter: (characterId: string) -> (), -- за монеты
	buyArena: (arenaId: string) -> (), -- премиальная карта за монеты
	promptArenaPass: (arenaId: string) -> (), -- премиальная карта за Robux
	promptPass: (characterId: string) -> (), -- Game Pass за Robux
	promptProduct: (key: string) -> (), -- Developer Product (пропуск босса, монеты)
	leaveMatch: () -> (),
	saveControls: (layout: ControlsLayout.Layout) -> (),
	-- Сенсорное управление в бою → InputController.
	touchPress: (bit: number) -> (),
	touchHeld: (mask: number) -> (),
}

export type AppState = {
	-- Текущий экран. Хранится как string: старый солвер Luau расширяет строковые литералы
	-- внутри Value<T>, поэтому менять экран нужно через AppState.navigate / AppState.back.
	screen: Fusion.Value<string>,
	history: { string },
	selectedCharacterId: Fusion.Value<string>,
	-- Какие персонажи доступны игроку (бесплатные + купленные) — из профиля с сервера.
	ownedCharacters: Fusion.Value<{ [string]: boolean }>,
	-- Доступные карты (бесплатные + купленные премиальные).
	ownedArenas: Fusion.Value<{ [string]: boolean }>,
	-- Найденные комбо (Config/Combos) — из профиля.
	combosFound: Fusion.Value<{ [string]: boolean }>,
	coins: Fusion.Value<number>,
	-- Прогресс боссов: пройдено по порядку (открыт следующий), победы над каждым.
	bossProgress: Fusion.Value<number>,
	bossClears: Fusion.Value<{ [string]: number }>,
	selectedBossId: Fusion.Value<string>,
	queue: Fusion.Value<QueueStatus>,
	-- Подготовка к бою (nil — нет).
	draft: Fusion.Value<DraftInfo?>,
	-- Текущий бой (nil — не в бою).
	battle: Fusion.Value<BattleInfo?>,
	-- Короткое уведомление внизу экрана ("" — нет уведомления).
	notice: Fusion.Value<string>,
	noticeId: number,
	hud: Hud,
	-- Платформа ввода: "Keyboard" | "Touch" | "Gamepad" (обновляет UIController).
	platform: Fusion.Value<string>,
	-- Раскладка сенсорного управления и черновик для экрана настройки.
	controlsLayout: Fusion.Value<ControlsLayout.Layout>,
	controlsDraft: Fusion.Value<ControlsLayout.Layout>,
	controlsSelected: Fusion.Value<string>,
	-- Текущий масштаб интерфейса (логические пиксели → пиксели экрана).
	uiScale: Fusion.Value<number>,
	-- Окно поверх экрана: "" — нет, "Pause" — пауза в бою, "HowToPlay" — памятка по кнопкам.
	modal: Fusion.Value<string>,
	-- Памятку уже показывали в этой сессии (сама открывается только в первой тренировке).
	howToSeen: boolean,
	actions: Actions,
}

local AppState = {}

AppState.MAX_FIGHTERS = 4

local function noop() end

function AppState.new(scope: Scope): AppState
	local owned: { [string]: boolean } = {}
	for _, def in CharacterRegistry.list() do
		if def.unlock == "Free" then
			owned[def.id] = true
		end
	end

	local arenas: { [string]: boolean } = {}
	for _, arena in Arenas.list do
		if not arena.premium then
			arenas[arena.id] = true
		end
	end

	local firstCharacter = CharacterRegistry.list()[1]
	local noBattle: BattleInfo? = nil
	local noDraft: DraftInfo? = nil

	local hudFighters: { HudFighter } = {}
	for _ = 1, AppState.MAX_FIGHTERS do
		table.insert(hudFighters, {
			health = scope:Value(1000),
			maxHealth = scope:Value(1000),
			meter = scope:Value(0),
			combo = scope:Value(0),
		})
	end

	return {
		screen = scope:Value("MainMenu"),
		history = {},
		selectedCharacterId = scope:Value(firstCharacter.id),
		ownedCharacters = scope:Value(owned),
		ownedArenas = scope:Value(arenas),
		combosFound = scope:Value({}),
		coins = scope:Value(0),
		bossProgress = scope:Value(0),
		bossClears = scope:Value({}),
		selectedBossId = scope:Value(BossRegistry.list()[1].id),
		queue = scope:Value({ status = "Idle", since = 0 } :: QueueStatus),
		draft = scope:Value(noDraft),
		battle = scope:Value(noBattle),
		notice = scope:Value(""),
		noticeId = 0,
		hud = {
			fighters = hudFighters,
			timer = scope:Value(-1),
			round = scope:Value(0),
			wins = scope:Value({ 0, 0 }),
			roundsToWin = scope:Value(0),
			banner = scope:Value(""),
			bannerColor = scope:Value(Color3.new(1, 1, 1)),
			bannerSerial = scope:Value(0),
			comboName = scope:Value(""),
			comboTeam = scope:Value(0),
			comboSerial = scope:Value(0),
		},
		platform = scope:Value("Keyboard"),
		controlsLayout = scope:Value(ControlsLayout.default()),
		controlsDraft = scope:Value(ControlsLayout.default()),
		controlsSelected = scope:Value("Light"),
		uiScale = scope:Value(1),
		modal = scope:Value(""),
		howToSeen = false,
		actions = {
			startTraining = noop,
			startBoss = function(_bossId: string) end,
			joinQueue = function(_mode: string) end,
			leaveQueue = noop,
			createRoom = function(_mode: string) end,
			joinRoom = function(_code: string) end,
			leaveRoom = noop,
			startCpu = function(_level: number, _mode: string) end,
			roomStart = noop,
			draftPick = function(_characterId: string) end,
			draftReady = noop,
			draftVote = function(_arenaId: string) end,
			draftLeave = noop,
			buyCharacter = function(_characterId: string) end,
			buyArena = function(_arenaId: string) end,
			promptArenaPass = function(_arenaId: string) end,
			promptPass = function(_characterId: string) end,
			promptProduct = function(_key: string) end,
			leaveMatch = noop,
			saveControls = function(_layout: ControlsLayout.Layout) end,
			touchPress = function(_bit: number) end,
			touchHeld = function(_mask: number) end,
		},
	}
end

-- Профиль с сервера (канал "Profile" или ответ GetProfile). Данные проверяются: это сеть.
function AppState.applyProfile(state: AppState, profile: unknown)
	if type(profile) ~= "table" then
		return
	end
	local raw = profile :: { [string]: any }
	if type(raw.coins) == "number" then
		state.coins:set(raw.coins)
	end
	if type(raw.bossProgress) == "number" then
		local previous = peek(state.bossProgress)
		local progress = math.clamp(math.floor(raw.bossProgress), 0, BossRegistry.count())
		state.bossProgress:set(progress)
		-- Выбор на карте переходит к новому открытому боссу.
		local selected = BossRegistry.get(peek(state.selectedBossId))
		if progress ~= previous and (selected == nil or selected.order <= progress) then
			local nextBoss = BossRegistry.byOrder(math.min(progress + 1, BossRegistry.count()))
			if nextBoss then
				state.selectedBossId:set(nextBoss.id)
			end
		end
	end
	if type(raw.bossClears) == "table" then
		local clears: { [string]: number } = {}
		for id, count in raw.bossClears do
			if type(id) == "string" and type(count) == "number" then
				clears[id] = count
			end
		end
		state.bossClears:set(clears)
	end
	if type(raw.ownedCharacters) == "table" then
		local owned: { [string]: boolean } = {}
		for id, value in raw.ownedCharacters do
			if type(id) == "string" and value == true and CharacterRegistry.get(id) then
				owned[id] = true
			end
		end
		state.ownedCharacters:set(owned)
	end
	if type(raw.ownedArenas) == "table" then
		local arenas: { [string]: boolean } = {}
		for id, value in raw.ownedArenas do
			if type(id) == "string" and value == true and Arenas.byId[id] then
				arenas[id] = true
			end
		end
		for _, arena in Arenas.list do
			if not arena.premium then
				arenas[arena.id] = true
			end
		end
		state.ownedArenas:set(arenas)
	end
	if raw.controls ~= nil then
		state.controlsLayout:set(ControlsLayout.sanitize(raw.controls))
	end
	if type(raw.combos) == "table" then
		local found: { [string]: boolean } = {}
		for id, value in raw.combos do
			if type(id) == "string" and value == true and Combos.byId[id] then
				found[id] = true
			end
		end
		state.combosFound:set(found)
	end
end

function AppState.navigate(state: AppState, screen: ScreenName)
	local current = peek(state.screen)
	if current == screen then
		return
	end
	table.insert(state.history, current)
	state.modal:set("")
	state.screen:set(screen)
end

function AppState.back(state: AppState)
	local previous: string = table.remove(state.history) or "MainMenu"
	state.modal:set("")
	state.screen:set(previous)
end

-- Заменить текущий экран (без записи в историю: «назад» вернёт на предыдущий).
function AppState.replace(state: AppState, screen: ScreenName)
	state.modal:set("")
	state.screen:set(screen)
end

local IDLE_QUEUE: QueueStatus = { status = "Idle", since = 0 }

-- Бой начался: показать экран боя (экран подготовки заменяется — после боя вернёмся в меню).
function AppState.enterBattle(state: AppState, info: BattleInfo)
	state.battle:set(info)
	state.queue:set(table.clone(IDLE_QUEUE))
	local screen = peek(state.screen)
	if screen == "Draft" then
		state.draft:set(nil)
		AppState.replace(state, "Battle")
	elseif screen ~= "Battle" then
		AppState.navigate(state, "Battle")
	end
end

-- Подготовка к бою с сервера (данные из сети — проверяются). Открывает экран подготовки.
function AppState.applyDraft(state: AppState, payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local raw = payload :: { [string]: any }
	if type(raw.id) ~= "number" or type(raw.slots) ~= "table" then
		return
	end
	local slots: { DraftSlotInfo } = {}
	for _, slot in raw.slots do
		if
			type(slot) == "table"
			and type(slot.slot) == "number"
			and type(slot.characterId) == "string"
			and CharacterRegistry.get(slot.characterId)
		then
			table.insert(slots, {
				slot = slot.slot,
				team = if slot.team == 2 then 2 else 1,
				name = if type(slot.name) == "string" then string.sub(slot.name, 1, 30) else "?",
				characterId = slot.characterId,
				ready = slot.ready == true,
				bot = slot.bot == true,
				vote = if type(slot.vote) == "string" and Arenas.byId[slot.vote] then slot.vote else nil,
			})
		end
	end
	table.sort(slots, function(a, b)
		return a.slot < b.slot
	end)
	local votes: { [string]: number } = {}
	if type(raw.votes) == "table" then
		for id, count in raw.votes do
			if type(id) == "string" and type(count) == "number" and Arenas.byId[id] then
				votes[id] = count
			end
		end
	end
	local phase = if raw.phase == "Map" or raw.phase == "Reveal" then raw.phase else "Character"
	local seconds = if type(raw.seconds) == "number" then math.clamp(raw.seconds, 0, 60) else 0
	state.draft:set({
		id = raw.id,
		mode = if type(raw.mode) == "string" then raw.mode else "Versus",
		phase = phase,
		deadline = os.clock() + seconds,
		localSlot = if type(raw.localSlot) == "number" then raw.localSlot else nil,
		slots = slots,
		votes = votes,
		arenaId = if type(raw.arenaId) == "string" and Arenas.byId[raw.arenaId] then raw.arenaId else nil,
	})
	state.queue:set(table.clone(IDLE_QUEUE))
	if peek(state.screen) ~= "Draft" then
		AppState.navigate(state, "Draft")
	end
end

-- Подготовка отменена или покинута: вернуться в меню.
function AppState.exitDraft(state: AppState)
	state.draft:set(nil)
	if peek(state.screen) == "Draft" then
		AppState.back(state)
	end
end

-- Свой слот в подготовке.
function AppState.draftSlot(info: DraftInfo): DraftSlotInfo?
	for _, slot in info.slots do
		if slot.slot == info.localSlot then
			return slot
		end
	end
	return nil
end

-- Бой закончился: вернуться туда, откуда пришли.
function AppState.exitBattle(state: AppState)
	state.battle:set(nil)
	if peek(state.screen) == "Battle" then
		AppState.back(state)
	end
end

-- Сбросить HUD к началу боя.
function AppState.resetHud(state: AppState, info: BattleInfo)
	local hud = state.hud
	for slot, fighter in hud.fighters do
		local setup = AppState.fighterInSlot(info, slot)
		local maxHealth = if setup then setup.maxHealth else 1000
		fighter.maxHealth:set(maxHealth)
		fighter.health:set(maxHealth)
		fighter.meter:set(0)
		fighter.combo:set(0)
	end
	hud.timer:set(if info.roundsToWin > 0 then 60 else -1)
	hud.round:set(0)
	hud.wins:set({ 0, 0 })
	hud.roundsToWin:set(info.roundsToWin)
	hud.banner:set("")
end

-- Боец в слоте (nil — такого слота в бою нет).
function AppState.fighterInSlot(info: BattleInfo, slot: number): BattleFighter?
	for _, fighter in info.fighters do
		if fighter.slot == slot then
			return fighter
		end
	end
	return nil
end

-- Статус очереди/комнаты с сервера (данные из сети — проверяются).
function AppState.applyQueue(state: AppState, payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local raw = payload :: { [string]: any }
	local status = if type(raw.status) == "string" then raw.status else "Idle"
	local members: { { name: string, characterId: string } }? = nil
	if type(raw.members) == "table" then
		local list: { { name: string, characterId: string } } = {}
		for _, member in raw.members do
			if type(member) == "table" and type(member.name) == "string" and type(member.characterId) == "string" then
				table.insert(list, { name = member.name, characterId = member.characterId })
			end
		end
		members = list
	end
	local previous = peek(state.queue)
	state.queue:set({
		status = status,
		mode = if type(raw.mode) == "string" then raw.mode else previous.mode,
		code = if type(raw.code) == "string" then raw.code else nil,
		host = raw.host == true,
		members = members,
		capacity = if type(raw.capacity) == "number" then raw.capacity else nil,
		-- Таймер ожидания не сбрасывается, пока статус тот же.
		since = if previous.status == status then previous.since else os.clock(),
	})
end

-- Крупная надпись по центру экрана боя ("ROUND 1", "FIGHT!", "K.O." ...).
function AppState.showBanner(state: AppState, text: string, seconds: number, color: Color3?)
	local hud = state.hud
	local serial = peek(hud.bannerSerial) + 1
	hud.bannerSerial:set(serial)
	hud.banner:set(text)
	hud.bannerColor:set(color or Color3.new(1, 1, 1))
	task.delay(seconds, function()
		if peek(hud.bannerSerial) == serial then
			hud.banner:set("")
		end
	end)
end

-- Показать название комбо на стороне команды team на несколько секунд.
function AppState.showCombo(state: AppState, team: number, name: string, seconds: number?)
	local hud = state.hud
	local serial = peek(hud.comboSerial) + 1
	hud.comboSerial:set(serial)
	hud.comboTeam:set(team)
	hud.comboName:set(name)
	task.delay(seconds or 1.6, function()
		if peek(hud.comboSerial) == serial then
			hud.comboName:set("")
		end
	end)
end

-- Показывать ли сенсорное управление в бою (с учётом режима из настроек).
function AppState.touchControlsVisible(mode: string, platform: string): boolean
	if mode == "Always" then
		return true
	elseif mode == "Never" then
		return false
	end
	return platform == "Touch"
end

-- Показать уведомление на несколько секунд.
function AppState.notify(state: AppState, text: string, seconds: number?)
	state.noticeId += 1
	local id = state.noticeId
	state.notice:set(text)
	task.delay(seconds or 3, function()
		if state.noticeId == id then
			state.notice:set("")
		end
	end)
end

return AppState
