-- Движение в симуляции: ходьба, прыжки, приседание, рывки, границы, раздвигание, детерминизм.

local Simulation = requireShared("Combat", "Simulation")
local InputBits = requireShared("Combat", "InputBits")
local GameConfig = requireShared("Config", "GameConfig")

local Physics = GameConfig.Physics
local TICK = GameConfig.TickRate

local function newSim(a, b)
	return Simulation.new({ characters = { a or "rook", b or "rook" } })
end

-- Прогнать N кадров с заданным вводом первого бойца (второй стоит).
local function run(sim, frames, held1, pressed1, held2)
	for _ = 1, frames do
		Simulation.step(sim, {
			{ held = held1 or 0, pressed = pressed1 or 0 },
			{ held = held2 or 0, pressed = 0 },
		})
		pressed1 = 0
	end
end

local function farApart(sim)
	sim.fighters[1].x = -10
	sim.fighters[2].x = 10
end

describe("Старт раунда", function()
	it("бойцы стоят на старте лицом друг к другу", function()
		local sim = newSim()
		local a, b = sim.fighters[1], sim.fighters[2]
		expect(a.x).toBeCloseTo(-Physics.StartDistance / 2)
		expect(b.x).toBeCloseTo(Physics.StartDistance / 2)
		expect(a.facing).toBe(1)
		expect(b.facing).toBe(-1)
		expect(a.state).toBe("Idle")
	end)
end)

describe("Ходьба", function()
	it(
		"назад медленнее, чем вперёд, и ровно со скоростью персонажа",
		function()
			local sim = newSim()
			sim.fighters[1].x = -5
			sim.fighters[2].x = 5
			local speed = sim.fighters[1].stats.walkSpeed
			run(sim, TICK, InputBits.Left)
			expect(sim.fighters[1].x).toBeCloseTo(-5 - speed * Physics.BackWalkFactor, 1e-6)
			expect(sim.fighters[1].state).toBe("Walk")

			local sim2 = newSim()
			farApart(sim2)
			run(sim2, TICK / 2, InputBits.Right)
			expect(sim2.fighters[1].x).toBeCloseTo(-10 + speed / 2, 1e-6)
		end
	)

	it("быстрые персонажи ходят быстрее медленных", function()
		local sim = newSim("mira", "brakk")
		expect(sim.fighters[1].stats.walkSpeed > sim.fighters[2].stats.walkSpeed).toBeTruthy()
	end)

	it("бойцы не проходят сквозь друг друга на земле", function()
		local sim = newSim()
		run(sim, TICK * 2, InputBits.Right, 0, InputBits.Left)
		local gap = sim.fighters[2].x - sim.fighters[1].x
		expect(gap >= Physics.PushWidth - 1e-6).toBeTruthy()
	end)

	it("упираются в края арены", function()
		local sim = newSim()
		run(sim, TICK * 5, InputBits.Left, 0, InputBits.Left)
		local wall = Physics.ArenaHalfWidth - Physics.PushWidth / 2
		expect(sim.fighters[1].x).toBeCloseTo(-wall, 1e-6)
		expect(sim.fighters[2].x >= -wall + Physics.PushWidth - 1e-6).toBeTruthy()
	end)

	it("не расходятся дальше максимальной дистанции", function()
		local sim = newSim()
		run(sim, TICK * 5, InputBits.Left, 0, InputBits.Right)
		local distance = sim.fighters[2].x - sim.fighters[1].x
		expect(distance <= Physics.MaxSeparation + 1e-6).toBeTruthy()
	end)
end)

describe("Прыжок и присед", function()
	it(
		"вертикальный прыжок: подготовка, взлёт, высота, приземление",
		function()
			local sim = newSim()
			farApart(sim)
			local startX = sim.fighters[1].x
			run(sim, 1, InputBits.Up)
			expect(sim.fighters[1].state).toBe("PreJump")
			local peak, airFrames = 0, 0
			for _ = 1, 80 do
				run(sim, 1, 0)
				local f = sim.fighters[1]
				peak = math.max(peak, f.y)
				if f.state == "Air" then
					airFrames += 1
				end
			end
			local expectedPeak = Physics.JumpVelocity ^ 2 / (2 * Physics.Gravity)
			expect(math.abs(peak - expectedPeak) < 0.4).toBeTruthy()
			expect(math.abs(airFrames - 2 * Physics.JumpVelocity / Physics.Gravity * TICK) <= 2).toBeTruthy()
			expect(sim.fighters[1].y).toBe(0)
			expect(sim.fighters[1].state).toBe("Idle")
			expect(sim.fighters[1].x).toBeCloseTo(startX)
		end
	)

	it("прыжок вперёд перемещает по X", function()
		local sim = newSim()
		farApart(sim)
		run(sim, 60, bit32.bor(InputBits.Up, InputBits.Right))
		expect(sim.fighters[1].x > -10 + 5).toBeTruthy()
	end)

	it("присед останавливает бойца", function()
		local sim = newSim()
		farApart(sim)
		run(sim, 10, bit32.bor(InputBits.Down, InputBits.Right))
		expect(sim.fighters[1].state).toBe("Crouch")
		expect(sim.fighters[1].x).toBeCloseTo(-10)
	end)

	it(
		"перепрыгнув противника, боец разворачивается после приземления",
		function()
			local sim = newSim()
			sim.fighters[1].x = -1.2
			sim.fighters[2].x = 1.2
			run(sim, 70, bit32.bor(InputBits.Up, InputBits.Right))
			local a, b = sim.fighters[1], sim.fighters[2]
			expect(a.x > b.x).toBeTruthy()
			expect(a.facing).toBe(-1)
			expect(b.facing).toBe(1)
		end
	)
end)

describe("Рывки", function()
	it("двойное нажатие вперёд — рывок на заданную дистанцию", function()
		local sim = newSim()
		farApart(sim)
		run(sim, 2, InputBits.Right)
		run(sim, 2, 0)
		run(sim, 1, InputBits.Right)
		expect(sim.fighters[1].state).toBe("Dash")
		local fromX = sim.fighters[1].x
		run(sim, Physics.DashFrames + 2, 0)
		local travelled = sim.fighters[1].x - fromX
		expect(math.abs(travelled - Physics.DashDistance) < 0.8).toBeTruthy()
		expect(sim.fighters[1].state).toBe("Idle")
	end)

	it("медленное двойное нажатие — просто шаги", function()
		local sim = newSim()
		farApart(sim)
		run(sim, 2, InputBits.Right)
		run(sim, Physics.DoubleTapWindow + 5, 0)
		run(sim, 1, InputBits.Right)
		expect(sim.fighters[1].state).toBe("Walk")
	end)

	it("кнопка рывка назад — отскок с неуязвимостью", function()
		local sim = newSim()
		farApart(sim)
		run(sim, 1, InputBits.Left, InputBits.Dash)
		expect(sim.fighters[1].state).toBe("Backdash")
		expect(sim.fighters[1].invulnerable > 0).toBeTruthy()
		run(sim, Physics.BackdashFrames + 2, 0)
		expect(sim.fighters[1].x < -10 - 3).toBeTruthy()
		expect(sim.fighters[1].invulnerable).toBe(0)
	end)
end)

describe("Ввод", function()
	it(
		"пока ввод выключен (заставка раунда), бойцы не двигаются",
		function()
			local sim = newSim()
			sim.inputEnabled = false
			run(sim, 30, InputBits.Right)
			expect(sim.fighters[1].x).toBeCloseTo(-Physics.StartDistance / 2)
		end
	)

	it("мусорный ввод безопасен", function()
		local sim = newSim()
		Simulation.step(sim, { { held = 0 / 0, pressed = -5 }, { held = 1e30, pressed = 3.7 } })
		expect(sim.fighters[1].x == sim.fighters[1].x).toBeTruthy()
	end)

	it("симуляция детерминирована", function()
		local function simulate()
			local sim = newSim("zip", "brakk")
			local held = { InputBits.Right, InputBits.Right, 0, InputBits.Right, InputBits.Up, 0, InputBits.Left }
			for frame = 1, 300 do
				local h = held[(frame // 17) % #held + 1]
				Simulation.step(sim, { { held = h, pressed = 0 }, { held = InputBits.Left, pressed = 0 } })
			end
			local a, b = sim.fighters[1], sim.fighters[2]
			return string.format("%.6f %.6f %.6f %.6f %s %s", a.x, a.y, b.x, b.y, a.state, b.state)
		end
		expect(simulate()).toBe(simulate())
	end)
end)
