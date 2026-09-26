--!strict
--[[
	Реактивное состояние интерфейса. Всё, что показывает UI, лежит здесь в Fusion Values:
	меняется значение → Fusion сам перерисовывает зависимые части экрана.

	Позже (этап 9) DataService будет присылать профиль игрока, а контроллер —
	записывать его в эти же Values (ownedCharacters, валюта, прогресс боссов и т.д.).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)

local peek = Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

export type ScreenName = "MainMenu" | "ModeSelect" | "CharacterSelect" | "BossMap" | "Shop" | "ControlsSettings"

export type AppState = {
	-- Текущий экран. Хранится как string: старый солвер Luau расширяет строковые литералы
	-- внутри Value<T>, поэтому менять экран нужно через AppState.navigate / AppState.back.
	screen: Fusion.Value<string>,
	history: { string },
	selectedCharacterId: Fusion.Value<string>,
	-- Какие персонажи доступны игроку. Пока — только бесплатные (покупки — этап 9).
	ownedCharacters: Fusion.Value<{ [string]: boolean }>,
}

local AppState = {}

function AppState.new(scope: Scope): AppState
	local owned: { [string]: boolean } = {}
	for _, def in CharacterRegistry.list() do
		if def.unlock == "Free" then
			owned[def.id] = true
		end
	end

	local firstCharacter = CharacterRegistry.list()[1]

	return {
		screen = scope:Value("MainMenu"),
		history = {},
		selectedCharacterId = scope:Value(firstCharacter.id),
		ownedCharacters = scope:Value(owned),
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

return AppState
