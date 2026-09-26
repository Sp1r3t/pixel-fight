--!strict
--[[
	Экран «Управление» — пока заглушка.  [этап 5]
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local AppState = require(script.Parent.Parent.AppState)
local PlaceholderScreen = require(script.Parent.Parent.Components.PlaceholderScreen)

type Scope = Fusion.Scope<typeof(Fusion)>

local function ControlsSettings(scope: Scope, state: AppState.AppState): Instance
	return PlaceholderScreen(scope, {
		Title = "УПРАВЛЕНИЕ",
		Stage = 5,
		Description = "Настройка размера и положения кнопок в стиле мобильного файтинга. Появится на этапе 5.",
		OnBack = function()
			AppState.back(state)
		end,
	})
end

return ControlsSettings
