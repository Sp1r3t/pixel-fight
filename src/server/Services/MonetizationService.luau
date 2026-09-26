--!strict
--[[
	MonetizationService — покупки.

	  • платные бойцы: Game Pass (владение проверяется при входе и после покупки) или монеты,
	    заработанные в игре (запрос BuyCharacter);
	  • Developer Products (ProcessReceipt): «Пропустить босса», наборы монет.
	    Защита от повторной выдачи: PurchaseId записывается в профиль вместе с выдачей награды,
	    а PurchaseGranted возвращается только после того, как профиль с этой записью сохранён.
	    Повторный чек с тем же PurchaseId награду не выдаёт — только подтверждает сохранение;
	  • игрок не на сервере, профиль не загружен, сохранение не прошло — NotProcessedYet
	    (Roblox повторит чек позже).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local ProfileSchema = require(ReplicatedStorage.Shared.Data.ProfileSchema)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)
local DataService = require(script.Parent.DataService)
local BossService = require(script.Parent.BossService)

local PROFILE_WAIT_SECONDS = 10

local MonetizationService = {
	Name = "MonetizationService",
}

local productById: { [number]: Monetization.Product } = {}
for _, product in Monetization.products do
	if product.id ~= 0 then
		productById[product.id] = product
	end
end

local characterByPass: { [number]: string } = {}
for characterId, passId in Monetization.gamePasses do
	if passId ~= 0 then
		characterByPass[passId] = characterId
	end
end

local function marketplace(): any
	return game:GetService("MarketplaceService")
end

local function notify(player: Player, payload: { [string]: any })
	if player.Parent ~= nil then
		Transport.fireClient("MatchEvent", player, "Purchase", payload)
	end
end

-- Владеет ли игрок Game Pass (ошибки сети — «нет», проверим при следующем входе).
local function ownsPass(player: Player, passId: number): boolean
	local ok, owns = pcall(function()
		return marketplace():UserOwnsGamePassAsync(player.UserId, passId)
	end)
	return ok and owns == true
end

-- При загрузке профиля: открыть бойцов, чьи Game Pass куплены (в том числе на сайте).
local function syncPasses(player: Player)
	for characterId, passId in Monetization.gamePasses do
		if passId ~= 0 and not DataService.ownsCharacter(player, characterId) and ownsPass(player, passId) then
			DataService.grantCharacter(player, characterId)
		end
	end
end

-- Выдать награду продукта. Ошибка — исключение (чек не засчитывается).
local function grantProduct(player: Player, product: Monetization.Product)
	if product.kind == "SkipBoss" then
		local skipped = BossService.grantSkip(player)
		notify(player, { kind = "SkipBoss", bossId = if skipped then skipped.id else nil })
	elseif product.kind == "Coins" then
		local amount = product.amount or 0
		assert(DataService.addCoins(player, amount), "профиль не загружен")
		notify(player, { kind = "Coins", amount = amount })
	else
		error(`Неизвестный тип продукта {product.kind}`)
	end
end

-- Обработка чека Developer Product (вынесено отдельно для тестов).
function MonetizationService.processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return notYet
	end
	local product = productById[receipt.ProductId]
	if product == nil then
		warn(`[Monetization] Неизвестный продукт {receipt.ProductId}`)
		return notYet
	end
	local session = DataService.waitForSession(player, PROFILE_WAIT_SECONDS)
	if session == nil or not session.isActive() then
		return notYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local data = session.data
	if data.purchases[purchaseId] == nil then
		local ok, err = pcall(function(): string?
			grantProduct(player, product)
			return nil
		end)
		if not ok then
			warn(`[Monetization] Не удалось выдать {product.key}: {err}`)
			return notYet
		end
		data.purchases[purchaseId] = os.time()
		ProfileSchema.trimPurchases(data)
	end
	local function recorded(saved: ProfileSchema.PlayerData): boolean
		return saved.purchases[purchaseId] ~= nil
	end
	-- Засчитываем покупку только когда запись о ней уже в сохранённых данных.
	if session.isSaved(recorded) or (session.saveAsync() and session.isSaved(recorded)) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return notYet
end

-- Покупка платного бойца за монеты.
function MonetizationService.buyWithCoins(player: Player, characterId: string): (boolean, string?)
	local def = CharacterRegistry.get(characterId)
	if def == nil or def.unlock ~= "Paid" then
		return false, "BadRequest"
	end
	if not DataService.isLoaded(player) then
		return false, "ProfileLoading"
	end
	if DataService.ownsCharacter(player, characterId) then
		return false, "AlreadyOwned"
	end
	if not DataService.spendCoins(player, Monetization.characterCoinPrice) then
		return false, "NotEnoughCoins"
	end
	DataService.grantCharacter(player, characterId)
	notify(player, { kind = "Character", characterId = characterId })
	return true, nil
end

function MonetizationService.Init()
	RequestRouter.register("BuyCharacter", function(player: Player, payload: unknown)
		local characterId = if type(payload) == "table" then (payload :: any).characterId else nil
		if type(characterId) ~= "string" then
			return false, "BadRequest"
		end
		return MonetizationService.buyWithCoins(player, characterId)
	end)
	DataService.onLoaded(syncPasses)
end

function MonetizationService.Start()
	local service = marketplace()
	service.ProcessReceipt = MonetizationService.processReceipt
	-- Событие приходит от самого Roblox (клиент подделать его не может).
	service.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local characterId = characterByPass[passId]
		if purchased and characterId then
			DataService.grantCharacter(player, characterId)
			notify(player, { kind = "Character", characterId = characterId })
		end
	end)
end

return MonetizationService
