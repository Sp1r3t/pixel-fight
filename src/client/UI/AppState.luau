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

	return {
		screen = scope:Value("MainMenu"),
		history = {},
		selectedCharacterId = scope:Value(firstCharacter.id),
		ownedCharacters = scope:Value(owned),
		battle = scope:Value(noBattle),
		notice = scope:Value(""),
		noticeId = 0,
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
