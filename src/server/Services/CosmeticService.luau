--!strict
--[[
	CosmeticService — надетая косметика и эмоции в бою.

	  • Equip: надеть/снять облик бойца, эффект ударов или финишер (только то, что есть у игрока);
	  • Emote: смайлик над своим бойцом в бою. Только доступные эмоции, не чаще одной в
	    Cosmetics.EMOTE_COOLDOWN секунд (защита от спама). Видят все участники боя.
	Всё это — внешний вид: боевой код косметику не читает.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Match = require(script.Parent.Parent.Match.Match)
local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local CosmeticService = {
	Name = "CosmeticService",
}

local lastEmote: { [Player]: number } = {}

function CosmeticService.equip(player: Player, slot: string, itemId: string?): (boolean, string?)
	if not DataService.isLoaded(player) then
		return false, "ProfileLoading"
	end
	if DataService.equip(player, slot, itemId) then
		return true, nil
	end
	return false, "BadRequest"
end

-- Эмоция в бою (now — os.clock(), параметр для тестов).
function CosmeticService.emote(player: Player, emoteId: string, now: number): (boolean, string?)
	local item = Cosmetics.byId[emoteId]
	if item == nil or item.kind ~= "Emote" or not DataService.hasItem(player, emoteId) then
		return false, "BadRequest"
	end
	local match = MatchService.getMatchOf(player)
	local slot = if match then Match.slotOf(match, player) else nil
	if match == nil or slot == nil or match.ended then
		return false, "NotInMatch"
	end
	local last = lastEmote[player]
	if last and now - last < Cosmetics.EMOTE_COOLDOWN then
		return false, "TooFast"
	end
	lastEmote[player] = now
	MatchService.queueEvent(match, { k = "Emote", s = slot, f = match.sim.frame, t = emoteId })
	return true, nil
end

function CosmeticService.Init()
	RequestRouter.register("Equip", function(player: Player, payload: unknown)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		local slot, itemId = (payload :: any).slot, (payload :: any).itemId
		if type(slot) ~= "string" or (itemId ~= nil and type(itemId) ~= "string") then
			return false, "BadRequest"
		end
		return CosmeticService.equip(player, slot, itemId)
	end)
	RequestRouter.register("Emote", function(player: Player, payload: unknown)
		local emoteId = if type(payload) == "table" then (payload :: any).emoteId else nil
		if type(emoteId) ~= "string" then
			return false, "BadRequest"
		end
		return CosmeticService.emote(player, emoteId, os.clock())
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastEmote[player] = nil
	end)
end

function CosmeticService.Start() end

return CosmeticService
