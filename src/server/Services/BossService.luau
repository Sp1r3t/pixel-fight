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
local Types = require(ReplicatedStorage.Shared.Types)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

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

-- Открыт ли босс игроку (следующий по порядку или уже пройденный).
function BossService.isUnlocked(player: Player, boss: BossDef): boolean
	return boss.order <= DataService.getBossProgress(player) + 1
end

local function onBossFinished(player: Player, boss: BossDef, result: Match.MatchResult)
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
			[BOSS_SLOT] = { displayName = boss.name, palette = boss.palette },
		},
		boss = { id = boss.id, order = boss.order, name = boss.name, title = boss.title },
		onFinished = function(_match: Match.Match, result: Match.MatchResult)
			onBossFinished(player, boss, result)
		end,
	})
	BossRules.setup(match, BOSS_SLOT, boss.mechanics)
	return match
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
end

function BossService.Start() end

return BossService
