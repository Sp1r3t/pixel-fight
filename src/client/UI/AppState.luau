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
}

export type BattleInfo = {
	matchId: number,
	mode: string,
	arenaId: string,
	localSlot: number?,
	fighters: { BattleFighter },
	roundsToWin: number, -- 0 — без раундов (тренировка)
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
}

-- Действия, которые UI может попросить выполнить (реализует UIController).
export type Actions = {
	startTraining: () -> (),
	leaveMatch: () -> (),
}

export type AppState = {
	-- Текущий экран. Хранится как string: старый солвер Luau расширяет строковые литералы
	-- внутри Value<T>, поэтому менять экран нужно через AppState.navigate / AppState.back.
	screen: Fusion.Value<string>,
	history: { string },
	selectedCharacterId: Fusion.Value<string>,
	-- Какие персонажи доступны игроку. Пока — только бесплатные (покупки — этап 9).
	ownedCharacters: Fusion.Value<{ [string]: boolean }>,
	-- Текущий бой (nil — не в бою).
	battle: Fusion.Value<BattleInfo?>,
	-- Короткое уведомление внизу экрана ("" — нет уведомления).
	notice: Fusion.Value<string>,
	noticeId: number,
	hud: Hud,
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
		},
		actions = {
			startTraining = noop,
			leaveMatch = noop,
		},
	}
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
