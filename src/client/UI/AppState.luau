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

local peek = Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

export type ScreenName =
	"MainMenu"
	| "ModeSelect"
	| "CharacterSelect"
	| "BossMap"
	| "Shop"
	| "ControlsSettings"
	| "Battle"

export type BattleFighter = {
	slot: number,
	characterId: string,
	playerName: string?,
	maxHealth: number,
	displayName: string?, -- своё имя (боссы)
	palette: Types.Palette?, -- свои цвета (боссы)
}

-- Участник команды в эстафете 2 на 2.
export type BattleMember = {
	characterId: string,
	playerName: string?,
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
	fighters: { BattleFighter },
	roundsToWin: number, -- 0 — без раундов (тренировка)
	boss: BattleBoss?,
	-- Эстафета 2 на 2: составы команд (слот = команда) и номер игрока в своей команде.
	teams: { { BattleMember } }?,
	localMember: number?,
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

-- Живые данные бойца для HUD (обновляет FightController каждый кадр).
export type HudFighter = {
	health: Fusion.Value<number>,
	maxHealth: Fusion.Value<number>,
	meter: Fusion.Value<number>,
	-- Сколько ударов подряд пропустил боец (счётчик комбо показывается у атакующего).
	combo: Fusion.Value<number>,
}

export type Hud = {
	fighters: { HudFighter },
	timer: Fusion.Value<number>, -- секунды; -1 — без ограничения
	round: Fusion.Value<number>,
	wins: Fusion.Value<{ number }>,
	roundsToWin: Fusion.Value<number>,
	banner: Fusion.Value<string>,
	bannerColor: Fusion.Value<Color3>,
	bannerSerial: Fusion.Value<number>,
	-- Эстафета: активный участник каждой команды и выбывшие в этом раунде (номера участников).
	members: Fusion.Value<{ number }>,
	eliminated: Fusion.Value<{ { [number]: boolean } }>,
	-- Управляет ли игрок бойцом прямо сейчас (в эстафете ждёт своей очереди).
	controlling: Fusion.Value<boolean>,
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
	startCpu: (level: number) -> (),
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
	coins: Fusion.Value<number>,
	-- Прогресс боссов: пройдено по порядку (открыт следующий), победы над каждым.
	bossProgress: Fusion.Value<number>,
	bossClears: Fusion.Value<{ [string]: number }>,
	selectedBossId: Fusion.Value<string>,
	queue: Fusion.Value<QueueStatus>,
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
	actions: Actions,
}

local AppState = {}

local function noop() end

function AppState.new(scope: Scope): AppState
	local owned: { [string]: boolean } = {}
	for _, def in CharacterRegistry.list() do
		if def.unlock == "Free" then
			owned[def.id] = true
		end
	end

	local firstCharacter = CharacterRegistry.list()[1]
	local noBattle: BattleInfo? = nil

	local hudFighters: { HudFighter } = {}
	for _ = 1, 2 do
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
		coins = scope:Value(0),
		bossProgress = scope:Value(0),
		bossClears = scope:Value({}),
		selectedBossId = scope:Value(BossRegistry.list()[1].id),
		queue = scope:Value({ status = "Idle", since = 0 } :: QueueStatus),
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
			members = scope:Value({ 1, 1 }),
			eliminated = scope:Value({ {}, {} } :: { { [number]: boolean } }),
			controlling = scope:Value(true),
		},
		platform = scope:Value("Keyboard"),
		controlsLayout = scope:Value(ControlsLayout.default()),
		controlsDraft = scope:Value(ControlsLayout.default()),
		controlsSelected = scope:Value("Light"),
		uiScale = scope:Value(1),
		actions = {
			startTraining = noop,
			startBoss = function(_bossId: string) end,
			joinQueue = function(_mode: string) end,
			leaveQueue = noop,
			createRoom = function(_mode: string) end,
			joinRoom = function(_code: string) end,
			leaveRoom = noop,
			startCpu = function(_level: number) end,
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
	if raw.controls ~= nil then
		state.controlsLayout:set(ControlsLayout.sanitize(raw.controls))
	end
end

function AppState.navigate(state: AppState, screen: ScreenName)
	local current = peek(state.screen)
	if current == screen then
		return
	end
	table.insert(state.history, current)
	state.screen:set(screen)
end

function AppState.back(state: AppState)
	local previous: string = table.remove(state.history) or "MainMenu"
	state.screen:set(previous)
end

-- Бой начался: показать экран боя.
function AppState.enterBattle(state: AppState, info: BattleInfo)
	state.battle:set(info)
	if peek(state.screen) ~= "Battle" then
		AppState.navigate(state, "Battle")
	end
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
		local setup = info.fighters[slot]
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
	hud.members:set({ 1, 1 })
	hud.eliminated:set({ {}, {} })
	hud.controlling:set(info.localSlot ~= nil and (info.teams == nil or info.localMember == 1))
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
