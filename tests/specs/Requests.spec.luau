-- Запросы клиента: любой мусор в данных не роняет обработчики сервера.

local JUNK = {
	"nil",
	5,
	-1,
	0 / 0,
	math.huge,
	"x",
	true,
	{},
	{ 1, 2, 3 },
	{ itemId = 5, slot = {}, emoteId = true },
	{ characterId = "nobody", arenaId = "nowhere", bossId = "nobody", order = -3 },
	{ characterId = {}, arenaId = 7, mode = "Hack", code = {} },
	{ itemId = "rook_shadow", slot = "Skin:nobody" },
	{ slot = "HitEffect", itemId = "ko_fireworks" },
	{ layout = { buttons = { { id = {}, x = 0 / 0 } } } },
	{ code = string.rep("A", 5000), team = 99, mode = "Team" },
}

local ACTIONS = {
	"BuyArena",
	"BuyCharacter",
	"BuyItem",
	"ClaimDaily",
	"ClientReady",
	"DraftLeave",
	"DraftPick",
	"DraftReady",
	"DraftVote",
	"Emote",
	"Equip",
	"GetProfile",
	"LeaveMatch",
	"QueueJoin",
	"QueueLeave",
	"RoomCreate",
	"RoomJoin",
	"RoomLeave",
	"RoomStart",
	"SaveControls",
	"StartBoss",
	"StartCpu",
	"StartTraining",
}

describe("Запросы клиента", function()
	it(
		"мусорные данные в любом запросе — отказ, а не ошибка сервера",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice")
			game.step(3)
			local Router = game.serverRequire("Net", "RequestRouter")
			local now = 1000
			for _, action in ACTIONS do
				for _, payload in JUNK do
					now += 1
					local _, result =
						Router.handle(alice.player, action, if payload == "nil" then nil else payload, now)
					if result == "ServerError" or result == "UnknownAction" then
						error(`{action}: {result}`)
					end
					game.step(1)
				end
			end
			expect(game.errors()).toBeEmpty()
		end
	)

	it("больше 12 запросов в секунду — отказ по лимиту", function()
		local game = Harness.new()
		local alice = game.addClient("Alice")
		game.step(3)
		local Router = game.serverRequire("Net", "RequestRouter")
		local limited = false
		for _ = 1, 60 do
			local _, result = Router.handle(alice.player, "GetProfile", nil, 5000)
			if result == "RateLimited" then
				limited = true
			end
		end
		expect(limited).toBe(true)
	end)
end)
