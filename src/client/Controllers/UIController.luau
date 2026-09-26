--!strict
--[[
	UIController — монтирует интерфейс на Fusion и выполняет действия UI.

	Владеет корневым Fusion-scope и состоянием интерфейса (AppState). Действия UI
	(начать тренировку, выйти из боя, ...) превращаются в запросы к серверу;
	ответы и данные с сервера записываются в Fusion Values — экраны обновляются сами.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)
local UI = script.Parent.Parent.UI
local App = require(UI.App)
local AppState = require(UI.AppState)

local peek = Fusion.peek

local UIController = {
	Name = "UIController",
}

local ERROR_TEXT: { [string]: string } = {
	CharacterNotAvailable = "Этот боец пока недоступен",
	RateLimited = "Слишком часто — подождите секунду",
	NotInMatch = "Вы не в бою",
	ServerError = "Ошибка сервера, попробуйте ещё раз",
}

local scope: Fusion.Scope<typeof(Fusion)>? = nil
local state: AppState.AppState? = nil

-- Запрос к серверу в отдельном потоке (InvokeServer ждёт ответа). Ошибки показываются уведомлением.
local function request(action: string, payload: any?)
	task.spawn(function()
		local ok, result = Transport.invokeServer("Request", action, payload)
		if not ok and state then
			local code = if type(result) == "string" then result else "ServerError"
			AppState.notify(state, ERROR_TEXT[code] or code)
		end
	end)
end

function UIController.Init()
	local rootScope = Fusion.scoped(Fusion)
	scope = rootScope
	local appState = AppState.new(rootScope)
	appState.actions.startTraining = function()
		request("StartTraining", { characterId = peek(appState.selectedCharacterId) })
	end
	appState.actions.leaveMatch = function()
		request("LeaveMatch", nil)
	end
	state = appState
end

function UIController.Start()
	-- Стандартные элементы Roblox, которые не нужны в файтинге.
	for _, coreGui in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreGui, false)
	end

	local rootScope = assert(scope, "UIController.Init не был вызван")
	local appState = assert(state, "UIController.Init не был вызван")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	App(rootScope, {
		State = appState,
		Parent = playerGui,
	})
end

-- Состояние интерфейса (для других контроллеров). Доступно после Init().
function UIController.getState(): AppState.AppState?
	return state
end

return UIController
