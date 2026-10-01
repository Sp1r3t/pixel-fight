--!strict
--[[
	BossService — одиночный режим: 20 боссов по порядку.

	  • запрос StartBoss {bossId, characterId}: проверка владения персонажем и открытия босса
	    (открыт следующий после последнего побеждённого; пройденных можно перепроходить);
	  • бой до GameConfig.RoundsToWin.Boss побед; босс — ИИ (BossAI) с профилем из BossRegistry,
	    с умеренным бонусом HP и уникальными механиками (BossRules);
	  • победа засчитывается только по итогам матча на сервере (onFinished), награда — за первую победу;
	  • grantSkip — засчитать следующего босса без боя (покупка «Пропустить босса», этап 9).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Types = require(ReplicatedStorage.Shared.Types)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)
local MatchFlow = require(ReplicatedStorage.Shared.Combat.MatchFlow)

local BossAI = require(script.Parent.Parent.AI.BossAI)
local BossRules = require(script.Parent.Parent.Match.BossRules)
local Match = require(script.Parent.Parent.Match.Match)
local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)
local MatchService = require(script.Parent.MatchService)
local DataService = require(script.Parent.DataService)

type BossDef = Types.BossDef

local PLAYER_SLOT = 1
local BOSS_SLOT = 2

local BossService = {
	Name = "BossService",
}

type OfferKind = "BossRetry" | "BossBoost"
type BossOffer = {
	kind: OfferKind,
	token: number,
	player: Player,
	productId: number,
	pending: boolean,
}

local offerToken = 0

local function productFor(kind: OfferKind): Monetization.Product?
	for _, product in Monetization.products do
		if product.kind == kind then
			return product
		end
	end
	return nil
end

local function closeOffer(match: Match.Match)
	local offer = match.data.bossOffer :: BossOffer?
	if offer == nil then
		return
	end
	match.data.bossOffer = nil
	if offer.player.Parent ~= nil then
		Transport.fireClient("MatchEvent", offer.player, "BossOfferClosed", { token = offer.token })
	end
end

local function expireOffer(match: Match.Match, token: number)
	local offer = match.data.bossOffer :: BossOffer?
	if match.ended or offer == nil or offer.token ~= token or offer.pending then
		return
	end
	local kind = offer.kind
	closeOffer(match)
	if kind == "BossRetry" then
		match.data.returnToLobby = true
		MatchService.finish(match, "Finished", BOSS_SLOT)
	end
end

local function openOffer(match: Match.Match, player: Player, kind: OfferKind, duration: number)
	if match.ended or match.data.bossOffer ~= nil then
		return
	end
	local product = productFor(kind)
	if product == nil then
		return
	end
	offerToken += 1
	local offer: BossOffer = {
		kind = kind,
		token = offerToken,
		player = player,
		productId = product.id,
		pending = false,
	}
	match.data.bossOffer = offer
	Transport.fireClient("MatchEvent", player, "BossOffer", {
		kind = kind,
		token = offer.token,
		duration = duration,
		price = product.priceHint,
		productId = product.id,
	})
	task.delay(duration, function()
		expireOffer(match, offer.token)
	end)
end

-- Открыт ли босс игроку (следующий по порядку или уже пройденный).
function BossService.isUnlocked(player: Player, boss: BossDef): boolean
	return boss.order <= DataService.getBossProgress(player) + 1
end

local function onBossFinished(player: Player, boss: BossDef, result: Match.MatchResult, returnToLobby: boolean?)
	local won = result.reason == "Finished" and result.winner == PLAYER_SLOT
	local firstClear, reward = false, 0
	if won then
		firstClear, reward = DataService.recordBossWin(player, boss.id, boss.order, boss.reward)
	end
	if player.Parent ~= nil then
		local nextBoss = BossRegistry.byOrder(boss.order + 1)
		Transport.fireClient("MatchEvent", player, "BossResult", {
			bossId = boss.id,
			won = won,
			returnToLobby = returnToLobby == true,
			firstClear = firstClear,
			reward = reward,
			unlocked = if won and firstClear and nextBoss then nextBoss.id else nil,
		})
	end
end

-- Начать бой с боссом (проверки владения и открытия — в обработчике запроса).
function BossService.startBoss(player: Player, boss: BossDef, characterId: string, seed: number?): Match.Match
	local isMirror = table.find(boss.mechanics, "Mirror") ~= nil
	local bossCharacter = if isMirror then characterId else boss.character
	local profile = BossRegistry.profile(boss)
	local match = MatchService.create({
		mode = "Boss",
		arenaId = boss.arena,
		characters = { characterId, bossCharacter },
		controllers = {
			{ kind = "Player", player = player },
			{ kind = "AI", think = BossAI.controller(profile, seed or math.random(1, 2 ^ 30)) },
		},
		participants = { player },
		hpMultipliers = { 1, boss.hpMultiplier },
		roundsToWin = GameConfig.RoundsToWin.Boss,
		presentation = {
			[BOSS_SLOT] = { displayName = boss.name, palette = boss.palette, visualStyle = boss.visualStyle },
		},
		boss = { id = boss.id, order = boss.order, name = boss.name, title = boss.title },
		onFinished = function(endingMatch: Match.Match, result: Match.MatchResult)
			closeOffer(endingMatch)
			onBossFinished(player, boss, result, endingMatch.data.returnToLobby)
		end,
		beforeFinish = function(endingMatch: Match.Match, result: Match.MatchResult): boolean
			if result.winner ~= BOSS_SLOT then
				return true
			end
			endingMatch.paused = true
			openOffer(endingMatch, player, "BossRetry", 5)
			return false
		end,
	})
	BossRules.setup(match, BOSS_SLOT, boss.mechanics)
	match.data.onRoundEnd = function(_event: MatchFlow.FlowEvent)
		if not match.sim.fighters[PLAYER_SLOT].ko then
			return
		end
		closeOffer(match)
		match.paused = true
		match.accumulator = 0
		openOffer(match, player, "BossRetry", 5)
	end
	match.data.offerBossBoost = function()
		openOffer(match, player, "BossBoost", 7)
	end
	return match
end

-- Receipt выдаёт эффект только активному серверному предложению.
function BossService.grantOffer(player: Player, kind: OfferKind): boolean
	local match = MatchService.getMatchOf(player)
	local offer = if match then match.data.bossOffer :: BossOffer? else nil
	if match == nil or offer == nil or offer.player ~= player or offer.kind ~= kind then
		return false
	end
	if kind == "BossBoost" then
		local fighter = match.sim.fighters[PLAYER_SLOT]
		fighter.modifiers.damageDealt *= 1.5
		fighter.modifiers.meterGain *= 1.5
		fighter.modifiers.damageTaken *= 0.7
		match.data.bossBoostPurchased = true
	else
		local flow = match.flow
		if flow == nil or not MatchFlow.retryLastRound(flow, match.sim) then
			return false
		end
	end
	closeOffer(match)
	match.paused = false
	match.accumulator = 0
	Transport.fireClient("MatchEvent", player, "Purchase", { kind = kind })
	return true
end

local function actOnOffer(player: Player, payload: unknown): (boolean, any)
	if type(payload) ~= "table" then
		return false, "BadRequest"
	end
	local action = (payload :: any).action
	local token = (payload :: any).token
	local match = MatchService.getMatchOf(player)
	local offer = if match then match.data.bossOffer :: BossOffer? else nil
	if match == nil or offer == nil or offer.player ~= player or token ~= offer.token then
		return false, "TooLate"
	end
	if action == "Buy" then
		if offer.productId == 0 then
			return false, "ProductNotConfigured"
		end
		if offer.pending then
			return false, "TooLate"
		end
		offer.pending = true
		match.paused = true
		match.accumulator = 0
		return true, { productId = offer.productId }
	elseif action == "Dismiss" or action == "PromptCancelled" then
		local kind = offer.kind
		closeOffer(match)
		if kind == "BossRetry" then
			match.data.returnToLobby = true
			MatchService.finish(match, "Finished", BOSS_SLOT)
		else
			match.paused = false
			match.accumulator = 0
		end
		return true, nil
	end
	return false, "BadRequest"
end

--[[
	Засчитать следующего босса без боя (покупка «Пропустить босса»). Возвращает пропущенного
	босса или nil, если пропускать нечего. Награда за пропуск не выдаётся.
]]
function BossService.grantSkip(player: Player): BossDef?
	local nextBoss = BossRegistry.byOrder(DataService.getBossProgress(player) + 1)
	if nextBoss == nil then
		return nil
	end
	DataService.recordBossWin(player, nextBoss.id, nextBoss.order, 0)
	return nextBoss
end

function BossService.Init()
	BossRegistry.assertValid()
	MatchService.addStepHook(BossRules.step)

	RequestRouter.register("StartBoss", function(player: Player, payload: unknown)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		local bossId = (payload :: any).bossId
		local characterId = (payload :: any).characterId
		if type(bossId) ~= "string" or type(characterId) ~= "string" then
			return false, "BadRequest"
		end
		local boss = BossRegistry.get(bossId)
		if boss == nil then
			return false, "BadRequest"
		end
		if CharacterRegistry.get(characterId) == nil or not DataService.ownsCharacter(player, characterId) then
			return false, "CharacterNotAvailable"
		end
		if not BossService.isUnlocked(player, boss) then
			return false, "BossLocked"
		end
		local match = BossService.startBoss(player, boss, characterId, nil)
		return true, match.id
	end)

	RequestRouter.register("BossOfferAction", actOnOffer)
end

function BossService.Start() end

return BossService
