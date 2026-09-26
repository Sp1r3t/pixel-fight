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
local ControlsLayout = require(ReplicatedStorage.Shared.Config.ControlsLayout)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local InputController = require(script.Parent.InputController)
local UI = script.Parent.Parent.UI
local App = require(UI.App)
local AppState = require(UI.AppState)

local peek = Fusion.peek

local UIController = {
	Name = "UIController",
}

-- Почему закончилось ожидание (статус "Idle" с причиной).
local QUEUE_REASON_TEXT: { [string]: string } = {
	RoomClosed = "Хозяин закрыл комнату",
	RoomExpired = "Комната закрыта: слишком долго ждали",
	RoomNotFound = "Комната друга уже закрыта",
	OpponentMissing = "Соперник не подключился — возвращаемся в лобби",
	TeleportFailed = "Не удалось подключиться к серверу матча",
}

local NOT_CONFIGURED = "Товар ещё не настроен: укажите его ID в Config/Monetization"

local ERROR_TEXT: { [string]: string } = {
	CharacterNotAvailable = "Этот боец пока недоступен",
	BossLocked = "Сначала победите предыдущего босса",
	BadRequest = "Некорректный запрос",
	InMatch = "Сначала закончите текущий бой",
	BadCode = "Код комнаты — 6 букв и цифр",
	RoomNotFound = "Комната с таким кодом не найдена",
	RoomFull = "Комната уже заполнена",
	TeleportFailed = "Не удалось подключиться к серверу матча",
	RateLimited = "Слишком часто — подождите секунду",
	NotInMatch = "Вы не в бою",
	ServerError = "Ошибка сервера, попробуйте ещё раз",
	NotEnoughCoins = "Не хватает монет",
	AlreadyOwned = "Этот боец уже открыт",
	ProfileLoading = "Сохранения ещё загружаются — секунду",
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
	appState.actions.startBoss = function(bossId: string)
		request("StartBoss", { bossId = bossId, characterId = peek(appState.selectedCharacterId) })
	end
	local function characterId(): string
		return peek(appState.selectedCharacterId)
	end
	appState.actions.joinQueue = function(mode: string)
		request("QueueJoin", { mode = mode, characterId = characterId() })
	end
	appState.actions.leaveQueue = function()
		request("QueueLeave", nil)
	end
	appState.actions.createRoom = function(mode: string)
		request("RoomCreate", { mode = mode, characterId = characterId() })
	end
	appState.actions.joinRoom = function(code: string)
		request("RoomJoin", { code = code, characterId = characterId() })
	end
	appState.actions.leaveRoom = function()
		request("RoomLeave", nil)
	end
	appState.actions.startCpu = function(level: number)
		request("StartCpu", { level = level, characterId = characterId() })
	end
	appState.actions.buyCharacter = function(id: string)
		request("BuyCharacter", { characterId = id })
	end
	appState.actions.promptPass = function(id: string)
		local passId = Monetization.gamePasses[id] or 0
		if passId == 0 then
			AppState.notify(appState, NOT_CONFIGURED, 4)
			return
		end
		pcall(function()
			game:GetService("MarketplaceService"):PromptGamePassPurchase(Players.LocalPlayer, passId)
		end)
	end
	appState.actions.promptProduct = function(key: string)
		local productId = 0
		for _, product in Monetization.products do
			if product.key == key then
				productId = product.id
			end
		end
		if productId == 0 then
			AppState.notify(appState, NOT_CONFIGURED, 4)
			return
		end
		pcall(function()
			game:GetService("MarketplaceService"):PromptProductPurchase(Players.LocalPlayer, productId)
		end)
	end
	appState.actions.leaveMatch = function()
		request("LeaveMatch", nil)
	end
	appState.actions.saveControls = function(layout: ControlsLayout.Layout)
		local clean = ControlsLayout.sanitize(layout)
		appState.controlsLayout:set(clean)
		request("SaveControls", clean)
		AppState.notify(appState, "Управление сохранено")
	end
	appState.actions.touchPress = function(bit: number)
		InputController.pressVirtual(bit)
	end
	appState.actions.touchHeld = function(mask: number)
		InputController.setVirtualHeld(mask)
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
	appState.platform:set(InputController.getPlatform())
	InputController.onPlatformChanged(function(platform)
		appState.platform:set(platform)
	end)
	-- Профиль: сервер присылает его после каждого изменения; при запуске — запрашиваем сами.
	Transport.onClientEvent("Profile", function(profile: any)
		AppState.applyProfile(appState, profile)
	end)
	task.spawn(function()
		local ok, profile = Transport.invokeServer("Request", "GetProfile", nil)
		if ok then
			AppState.applyProfile(appState, profile)
		end
		-- Клиент готов: сервер может, например, завершить вход в комнату друга после телепорта.
		Transport.invokeServer("Request", "ClientReady", nil)
	end)
	-- Поиск матча, комнаты и награды мультиплеера.
	Transport.onClientEvent("MatchEvent", function(kind: any, payload: any)
		if kind == "Queue" then
			AppState.applyQueue(appState, payload)
			local reason = if type(payload) == "table" then payload.reason else nil
			if type(reason) == "string" and QUEUE_REASON_TEXT[reason] then
				AppState.notify(appState, QUEUE_REASON_TEXT[reason], 4)
			end
		elseif kind == "Reward" and type(payload) == "table" and type(payload.coins) == "number" then
			AppState.notify(appState, `Победа! +{payload.coins} монет`, 4)
		elseif kind == "Purchase" and type(payload) == "table" then
			-- Покупка прошла (данные уже обновились каналом Profile).
			if payload.kind == "Character" and type(payload.characterId) == "string" then
				local def = CharacterRegistry.get(payload.characterId)
				AppState.notify(appState, `Боец {if def then def.displayName else "?"} открыт!`, 4)
			elseif payload.kind == "Coins" and type(payload.amount) == "number" then
				AppState.notify(appState, `+{payload.amount} монет`, 4)
			elseif payload.kind == "SkipBoss" then
				local boss = if type(payload.bossId) == "string" then BossRegistry.get(payload.bossId) else nil
				AppState.notify(
					appState,
					if boss
						then `Босс {boss.order} ({boss.name}) засчитан`
						else "Все боссы уже пройдены",
					4
				)
			end
		end
	end)
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
