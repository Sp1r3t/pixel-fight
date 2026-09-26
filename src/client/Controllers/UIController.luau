--!strict
--[[
	UIController — монтирует интерфейс на Fusion.  [этап 1, расширяется на этапах 4, 5, 9]

	Владеет корневым Fusion-scope и состоянием интерфейса (AppState).
	Позже сюда придут данные с сервера (профиль, события матча) и будут
	записываться в Fusion Values — экраны обновятся сами.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = script.Parent.Parent.UI
local App = require(UI.App)
local AppState = require(UI.AppState)

local UIController = {
	Name = "UIController",
}

local scope: Fusion.Scope<typeof(Fusion)>? = nil
local state: AppState.AppState? = nil

function UIController.Init()
	scope = Fusion.scoped(Fusion)
end

function UIController.Start()
	-- Стандартные элементы Roblox, которые не нужны в файтинге.
	for _, coreGui in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreGui, false)
	end

	local rootScope = assert(scope, "UIController.Init не был вызван")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local appState = AppState.new(rootScope)
	state = appState

	App(rootScope, {
		State = appState,
		Parent = playerGui,
	})
end

-- Текущее состояние интерфейса (для других контроллеров). nil до Start().
function UIController.getState(): AppState.AppState?
	return state
end

return UIController
