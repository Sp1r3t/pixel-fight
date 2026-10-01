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
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local Combos = require(ReplicatedStorage.Shared.Config.Combos)
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local InputController = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)
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
	NotEnoughCrystals = "Не хватает кристаллов 💎",
	TooFast = "",
	AlreadyOwned = "Этот боец уже открыт",
	ProfileLoading = "Сохранения ещё загружаются — секунду",
	NotInRoom = "Вы не в комнате",
	NotHost = "Начать бой может только хозяин комнаты",
	NotInDraft = "Подготовка к бою уже закончилась",
	TooLate = "Время вышло — выбор уже сделан",
	ProductNotConfigured = "Товар ещё не настроен: укажите его ID в Config/Monetization",
	ArenaLocked = "Эту карту можно выбрать, только если она куплена",
}

-- Почему отменена подготовка к бою.
local DRAFT_CANCEL_TEXT: { [string]: string } = {
	Empty = "Все игроки вышли — бой отменён",
	Replaced = "Начался другой бой",
}

local scope: Fusion.Scope<typeof(Fusion)>? = nil
local state: AppState.AppState? = nil
local activeBossPrompt: { token: number, productId: number }? = nil

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
	appState.actions.startCpu = function(level: number, mode: string)
		request("StartCpu", { level = level, mode = mode, characterId = characterId() })
	end
	appState.actions.roomStart = function()
		request("RoomStart", nil)
	end
	appState.actions.draftPick = function(id: string)
		request("DraftPick", { characterId = id })
	end
	appState.actions.draftReady = function()
		request("DraftReady", nil)
	end
	appState.actions.draftVote = function(arenaId: string)
		request("DraftVote", { arenaId = arenaId })
	end
	appState.actions.draftLeave = function()
		request("DraftLeave", nil)
		AppState.exitDraft(appState)
	end
	appState.actions.buyCharacter = function(id: string)
		request("BuyCharacter", { characterId = id })
	end
	appState.actions.buyArena = function(arenaId: string)
		request("BuyArena", { arenaId = arenaId })
	end
	appState.actions.promptArenaPass = function(arenaId: string)
		local passId = Monetization.arenaPasses[arenaId] or 0
		if passId == 0 then
			AppState.notify(appState, NOT_CONFIGURED, 4)
			return
		end
		pcall(function()
			game:GetService("MarketplaceService"):PromptGamePassPurchase(Players.LocalPlayer, passId)
		end)
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
	appState.actions.bossOffer = function(action: string)
		local offer = peek(appState.bossOffer)
		if offer == nil or offer.pending then
			return
		end
		if action == "Dismiss" then
			appState.bossOffer:set(nil)
			request("BossOfferAction", { action = "Dismiss", token = offer.token })
			return
		end
		if action ~= "Buy" then
			return
		end
		offer.pending = true
		appState.bossOffer:set(table.clone(offer))
		task.spawn(function()
			local ok, result = Transport.invokeServer("Request", "BossOfferAction", {
				action = "Buy",
				token = offer.token,
			})
			if not ok or type(result) ~= "table" or type(result.productId) ~= "number" then
				offer.pending = false
				if peek(appState.bossOffer) ~= nil then
					appState.bossOffer:set(table.clone(offer))
				end
				AppState.notify(appState, ERROR_TEXT[result] or tostring(result), 4)
				return
			end
			activeBossPrompt = { token = offer.token, productId = result.productId }
			local prompted = pcall(function()
				game:GetService("MarketplaceService"):PromptProductPurchase(Players.LocalPlayer, result.productId)
			end)
			if not prompted then
				activeBossPrompt = nil
				request("BossOfferAction", { action = "PromptCancelled", token = offer.token })
			end
		end)
	end
	appState.actions.promptVip = function()
		if Monetization.vipPass == 0 then
			AppState.notify(appState, NOT_CONFIGURED, 4)
			return
		end
		pcall(function()
			game:GetService("MarketplaceService"):PromptGamePassPurchase(Players.LocalPlayer, Monetization.vipPass)
		end)
	end
	appState.actions.buyItem = function(itemId: string)
		request("BuyItem", { itemId = itemId })
	end
	appState.actions.equip = function(slot: string, itemId: string?)
		request("Equip", { slot = slot, itemId = itemId })
	end
	appState.actions.claimDaily = function()
		task.spawn(function()
			local ok, result = Transport.invokeServer("Request", "ClaimDaily", nil)
			if ok and type(result) == "table" then
				local text = `🎁 День {result.day} из 7: +{result.coins} 🪙`
				if type(result.crystals) == "number" and result.crystals > 0 then
					text ..= ` +{result.crystals} 💎`
				end
				AppState.notify(appState, text, 4)
			elseif result == "AlreadyClaimed" then
				AppState.notify(
					appState,
					"Награда дня уже получена — приходи завтра!",
					3
				)
			end
		end)
	end
	appState.actions.emote = function(emoteId: string)
		request("Emote", { emoteId = emoteId })
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
	appState.inputBindings:set(InputController.getBindingLabels())
	rootScope:Observer(appState.controlsLayout):onBind(function()
		InputController.applyKeyboardBindings(peek(appState.controlsLayout).keyboard)
		appState.inputBindings:set(InputController.getBindingLabels())
	end)
	InputController.onPlatformChanged(function(platform)
		appState.platform:set(platform)
		appState.inputBindings:set(InputController.getBindingLabels(platform))
	end)
	-- Сенсорные кнопки на экране → камера держит бойцов над ними и ближе к центру.
	local touchVisible = rootScope:Computed(function(use)
		return AppState.touchControlsVisible(use(appState.controlsLayout).mode, use(appState.platform))
	end)
	rootScope:Observer(touchVisible):onBind(function()
		CameraController.setTouchFraming(peek(touchVisible))
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
		if kind == "BossOffer" and type(payload) == "table" then
			if
				type(payload.kind) == "string"
				and type(payload.token) == "number"
				and type(payload.duration) == "number"
				and type(payload.price) == "number"
				and type(payload.productId) == "number"
			then
				appState.bossOffer:set({
					kind = payload.kind,
					token = payload.token,
					duration = payload.duration,
					price = payload.price,
					productId = payload.productId,
					startedAt = os.clock(),
					pending = false,
				})
			end
		elseif kind == "BossOfferClosed" then
			appState.bossOffer:set(nil)
			activeBossPrompt = nil
		end
		if kind == "Draft" then
			AppState.applyDraft(appState, payload)
		elseif kind == "DraftCancelled" then
			local reason = if type(payload) == "table" then payload.reason else nil
			AppState.exitDraft(appState)
			AppState.notify(appState, DRAFT_CANCEL_TEXT[reason] or "Бой отменён", 4)
		elseif kind == "Queue" then
			AppState.applyQueue(appState, payload)
			local reason = if type(payload) == "table" then payload.reason else nil
			if type(reason) == "string" and QUEUE_REASON_TEXT[reason] then
				AppState.notify(appState, QUEUE_REASON_TEXT[reason], 4)
			end
		elseif kind == "ComboUnlocked" and type(payload) == "table" and type(payload.id) == "string" then
			-- Первое выполнение комбо: награда уже начислена (профиль придёт каналом Profile).
			local combo = Combos.byId[payload.id]
			if combo then
				local coins = if type(payload.coins) == "number" then payload.coins else combo.reward
				AppState.notify(appState, `Новое комбо «{combo.name}»! +{coins} 🪙`, 3)
			end
		elseif kind == "Reward" and type(payload) == "table" and type(payload.coins) == "number" then
			AppState.notify(appState, `Победа! +{payload.coins} монет`, 4)
		elseif kind == "Purchase" and type(payload) == "table" then
			-- Покупка прошла (данные уже обновились каналом Profile).
			if payload.kind == "Character" and type(payload.characterId) == "string" then
				local def = CharacterRegistry.get(payload.characterId)
				AppState.notify(appState, `Боец {if def then def.displayName else "?"} открыт!`, 4)
			elseif payload.kind == "Arena" and type(payload.arenaId) == "string" then
				local arena = Arenas.byId[payload.arenaId]
				AppState.notify(appState, `Карта «{if arena then arena.name else "?"}» открыта!`, 4)
			elseif payload.kind == "Coins" and type(payload.amount) == "number" then
				AppState.notify(appState, `+{payload.amount} монет`, 4)
			elseif payload.kind == "Crystals" and type(payload.amount) == "number" then
				AppState.notify(appState, `+{payload.amount} 💎 кристаллов`, 4)
			elseif payload.kind == "StarterPack" then
				AppState.notify(appState, "Набор новичка получен! 🎉", 4)
			elseif payload.kind == "Vip" then
				AppState.notify(appState, "Ты VIP! 👑 Больше монет и радужные удары", 5)
			elseif payload.kind == "Item" and type(payload.itemId) == "string" then
				local item = Cosmetics.byId[payload.itemId]
				if item then
					AppState.notify(appState, `{item.icon} «{item.name}» — теперь твоё!`, 4)
				end
			elseif payload.kind == "SkipBoss" then
				local boss = if type(payload.bossId) == "string" then BossRegistry.get(payload.bossId) else nil
				AppState.notify(
					appState,
					if boss
						then `Босс {boss.order} ({boss.name}) засчитан`
						else "Все боссы уже пройдены",
					4
				)
			elseif payload.kind == "BossBoost" then
				AppState.notify(appState, "Усиление активно до конца боя!", 4)
			elseif payload.kind == "BossRetry" then
				AppState.notify(appState, "Последний раунд начат заново!", 4)
			end
		end
	end)
	game:GetService("MarketplaceService").PromptProductPurchaseFinished
		:Connect(function(_userId: any, productId: any, purchased: any)
			local prompt = activeBossPrompt
			if prompt and productId == prompt.productId and purchased == false then
				activeBossPrompt = nil
				appState.bossOffer:set(nil)
				request("BossOfferAction", { action = "PromptCancelled", token = prompt.token })
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
