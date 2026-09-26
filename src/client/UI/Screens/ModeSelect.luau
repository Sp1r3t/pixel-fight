--!strict
--[[
	Экран «Выбор режима» — пока заглушка.  [этап 7]
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local AppState = require(script.Parent.Parent.AppState)
local PlaceholderScreen = require(script.Parent.Parent.Components.PlaceholderScreen)

type Scope = Fusion.Scope<typeof(Fusion)>

local function ModeSelect(scope: Scope, state: AppState.AppState): Instance
	return PlaceholderScreen(scope, {
		Title = "ВЫБОР РЕЖИМА",
		Stage = 7,
		Description = "Мультиплеер: 1 на 1, 2 на 2 и приватные матчи с другом. Появится на этапе 7.",
		OnBack = function()
			AppState.back(state)
		end,
	})
end

return ModeSelect
