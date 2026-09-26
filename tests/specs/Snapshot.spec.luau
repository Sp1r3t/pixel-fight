-- Двоичные снапшоты: упаковка/распаковка и защита от мусора.

local Simulation = requireShared("Combat", "Simulation")
local Snapshot = requireShared("Combat", "Snapshot")
local InputBits = requireShared("Combat", "InputBits")

local function capture(sim)
	local fighters = {}
	for _, fighter in sim.fighters do
		table.insert(fighters, Snapshot.fromFighter(fighter))
	end
	return {
		frame = sim.frame,
		phase = 2,
		timer = 1234,
		fighters = fighters,
		projectiles = { { id = 7, owner = 1, kind = 3, x = 1.5, y = 2.25, direction = -1, age = 12 } },
	}
end

describe("Snapshot", function()
	it("упаковка и распаковка сохраняют состояние", function()
		local sim = Simulation.new({ characters = { "rook", "juno" } })
		for _ = 1, 20 do
			Simulation.step(sim, {
				{ held = bit32.bor(InputBits.Up, InputBits.Right), pressed = 0 },
				{ held = InputBits.Left, pressed = 0 },
			})
		end
		local original = capture(sim)
		local decoded = Snapshot.decode(Snapshot.encode(original))
		expect(decoded ~= nil).toBeTruthy()
		expect(decoded.frame).toBe(original.frame)
		expect(decoded.phase).toBe(2)
		expect(decoded.timer).toBe(1234)
		for index, fighter in original.fighters do
			local copy = decoded.fighters[index]
			expect(copy.x).toBeCloseTo(fighter.x, 1e-4)
			expect(copy.y).toBeCloseTo(fighter.y, 1e-4)
			expect(copy.vx).toBeCloseTo(fighter.vx, 0.05)
			expect(copy.vy).toBeCloseTo(fighter.vy, 0.05)
			expect(copy.state).toBe(fighter.state)
			expect(copy.facing).toBe(fighter.facing)
			expect(copy.health).toBe(fighter.health)
		end
		expect(decoded.projectiles[1].id).toBe(7)
		expect(decoded.projectiles[1].direction).toBe(-1)
		expect(decoded.projectiles[1].y).toBeCloseTo(2.25)
	end)

	it(
		"снапшот двух бойцов меньше лимита ненадёжного события",
		function()
			local sim = Simulation.new({ characters = { "rook", "juno" } })
			expect(buffer.len(Snapshot.encode(capture(sim))) < 200).toBeTruthy()
		end
	)

	it("повреждённые данные не распаковываются", function()
		expect(Snapshot.decode(buffer.create(3))).toBe(nil)
		local b = Snapshot.encode(capture(Simulation.new({ characters = { "rook", "rook" } })))
		local truncated = buffer.create(buffer.len(b) - 1)
		buffer.copy(truncated, 0, b, 0, buffer.len(b) - 1)
		expect(Snapshot.decode(truncated)).toBe(nil)
		local wrongVersion = buffer.create(buffer.len(b))
		buffer.copy(wrongVersion, 0, b)
		buffer.writeu8(wrongVersion, 0, 99)
		expect(Snapshot.decode(wrongVersion)).toBe(nil)
		expect(Snapshot.decode("not a buffer" :: any)).toBe(nil)
	end)
end)
