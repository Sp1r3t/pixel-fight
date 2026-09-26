-- Формат ввода и серверная защита (InputService, RequestRouter).

local InputBits = requireShared("Combat", "InputBits")
local GameConfig = requireShared("Config", "GameConfig")

describe("InputBits", function()
	it(
		"счётчики нажатий упаковываются и распаковываются без потерь",
		function()
			local counters = { 3, 15, 0, 7, 9 }
			local unpacked = InputBits.unpackCounters(InputBits.packCounters(counters))
			for index, value in counters do
				expect(unpacked[index]).toBe(value)
			end
		end
	)

	it(
		"разница счётчиков учитывает переполнение и ограничена 3 нажатиями",
		function()
			local mask, counts = InputBits.diffCounters({ 15, 0, 0, 0, 0 }, { 1, 10, 0, 0, 0 })
			expect(counts[1]).toBe(2) -- 15 → 0 → 1
			expect(counts[2]).toBe(3) -- 10 нажатий, но максимум 3
			expect(bit32.band(mask, InputBits.Light) ~= 0).toBeTruthy()
			expect(bit32.band(mask, InputBits.Special)).toBe(0)
		end
	)

	it("sanitize вырезает лишние биты и мусор", function()
		expect(InputBits.sanitize(0xFFFFFF)).toBe(InputBits.ALL)
		expect(InputBits.sanitize(0 / 0)).toBe(0)
		expect(InputBits.horizontal(bit32.bor(InputBits.Left, InputBits.Right))).toBe(0)
	end)
end)

describe("InputService", function()
	local game = Harness.new()
	local InputService = game.serverRequire("Services", "InputService")

	local function fakePlayer(name)
		return { Name = name }
	end

	it(
		"принимает корректный пакет и выдаёт нажатие ровно один раз",
		function()
			local player = fakePlayer("a")
			local counters = InputBits.packCounters({ 1, 0, 0, 0, 0 })
			expect(InputService.receive(player, 1, InputBits.Right, counters, 10)).toBe(true)
			local first = InputService.consume(player, 10)
			expect(first.held).toBe(InputBits.Right)
			expect(first.pressed).toBe(InputBits.Light)
			local second = InputService.consume(player, 10)
			expect(second.pressed).toBe(0)
		end
	)

	it("отбрасывает устаревшие и повторные пакеты", function()
		local player = fakePlayer("b")
		InputService.receive(player, 5, InputBits.Left, 0, 1)
		expect(InputService.receive(player, 4, InputBits.Right, 0, 1)).toBe(false)
		expect(InputService.receive(player, 5, InputBits.Right, 0, 1)).toBe(false)
		expect(InputService.consume(player, 1).held).toBe(InputBits.Left)
	end)

	it("отбрасывает пакеты неверного типа", function()
		local player = fakePlayer("c")
		expect(InputService.receive(player, "1", 0, 0, 1)).toBe(false)
		expect(InputService.receive(player, 1, {}, 0, 1)).toBe(false)
		expect(InputService.receive(player, 1, 0, 2 ^ 40, 1)).toBe(false)
		expect(InputService.receive(player, 1.5, 0, 0, 1)).toBe(false)
		expect(InputService.receive(player, 1, 99999, 0, 1)).toBe(false)
		expect(InputService.getRejectedCount(player)).toBe(5)
	end)

	it("ограничивает частоту пакетов", function()
		local player = fakePlayer("d")
		local accepted = 0
		for seq = 1, 200 do
			if InputService.receive(player, seq, 0, 0, 5 + seq * 0.001) then
				accepted += 1
			end
		end
		expect(accepted).toBe(GameConfig.Input.MaxPacketsPerSecond)
	end)

	it("при обрыве связи кнопки считаются отпущенными", function()
		local player = fakePlayer("e")
		InputService.receive(player, 1, InputBits.Right, 0, 100)
		expect(InputService.consume(player, 100.2).held).toBe(InputBits.Right)
		expect(InputService.consume(player, 101).held).toBe(0)
	end)

	it("несколько быстрых нажатий раздаются по одному за кадр", function()
		local player = fakePlayer("f")
		InputService.receive(player, 1, 0, InputBits.packCounters({ 2, 0, 0, 0, 0 }), 1)
		expect(InputService.consume(player, 1).pressed).toBe(InputBits.Light)
		expect(InputService.consume(player, 1).pressed).toBe(InputBits.Light)
		expect(InputService.consume(player, 1).pressed).toBe(0)
	end)
end)

describe("RequestRouter", function()
	local game = Harness.new()
	local RequestRouter = game.serverRequire("Net", "RequestRouter")

	it("отклоняет некорректные и неизвестные запросы", function()
		local player = { Name = "x" }
		local ok, code = RequestRouter.handle(player, 42, nil, 1)
		expect(ok).toBe(false)
		expect(code).toBe("BadRequest")
		ok, code = RequestRouter.handle(player, "Hack", nil, 1)
		expect(code).toBe("UnknownAction")
	end)

	it("ограничивает частоту запросов", function()
		local player = { Name = "y" }
		local limited = false
		for _ = 1, 30 do
			local _, code = RequestRouter.handle(player, "LeaveMatch", nil, 2)
			if code == "RateLimited" then
				limited = true
			end
		end
		expect(limited).toBeTruthy()
	end)
end)
