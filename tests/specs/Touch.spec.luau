-- Сенсорное управление: раскладка, джойстик, кнопки, настройка.

local ControlsLayout = requireShared("Config", "ControlsLayout")

local function touch(x, y)
	return {
		UserInputType = Enum.UserInputType.Touch,
		UserInputState = Enum.UserInputState.Begin,
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.new(x, y, 0),
		Delta = Vector3.zero,
	}
end

local function startTraining(onTouch)
	local game = Harness.new()
	local client = game.addClient("Alice")
	game.step(2)
	if onTouch then
		client.runtime.services.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
		game.step(1)
	end
	client.click("Тренировка")
	game.step(10)
	-- Первая тренировка открывает памятку «Как играть» (кнопки под ней скрыты) — закрываем.
	if client.find("HowToPlay") then
		client.press("GotIt")
		game.step(1)
	end
	local MatchService = game.serverRequire("Services", "MatchService")
	return game, client, MatchService.getMatchOf(client.player)
end

local function uis(client)
	return client.runtime.services.UserInputService
end

describe("Раскладка управления", function()
	it(
		"мусорные данные превращаются в раскладку по умолчанию",
		function()
			local layout = ControlsLayout.sanitize("garbage")
			expect(layout.mode).toBe("Auto")
			expect(layout.controls.Light.size).toBe(1)
			local weird = ControlsLayout.sanitize({
				mode = "Hacked",
				opacity = 0 / 0,
				controls = { Light = { x = -1e9, y = 1e9, size = 50 }, Unknown = { x = 1 } },
			})
			expect(weird.mode).toBe("Auto")
			expect(weird.opacity).toBe(ControlsLayout.default().opacity)
			expect(weird.controls.Light.size).toBe(ControlsLayout.LIMITS.maxSize)
			expect(weird.controls.Light.y).toBe(ControlsLayout.LIMITS.maxY)
			expect(weird.controls.Light.x > 0).toBeTruthy()
			expect(weird.controls.Unknown).toBe(nil)
		end
	)

	it(
		"кнопки по умолчанию не перекрываются; есть «Прыжок» и «Блок»",
		function()
			local layout = ControlsLayout.default()
			expect(#ControlsLayout.overlaps(layout)).toBe(0)
			expect(layout.controls.Jump ~= nil).toBeTruthy()
			expect(layout.controls.Block ~= nil).toBeTruthy()
			-- Старые раскладки (до кнопок «Прыжок»/«Блок» и до компактной дуги) заменяются новой
			-- по умолчанию, режим показа сохраняется.
			for version = 1, 2 do
				local old = ControlsLayout.sanitize({
					version = version,
					mode = "Always",
					controls = { Light = { x = 400 } },
				})
				expect(old.mode).toBe("Always")
				expect(old.controls.Light.x).toBe(layout.controls.Light.x)
			end
		end
	)

	it(
		"раскладка по умолчанию компактная: кнопки у краёв, середина над полом свободна для бойцов",
		function()
			local layout = ControlsLayout.default()
			-- Рывок по умолчанию спрятан (двойной толчок джойстика), кнопок меньше.
			expect(layout.dashButton).toBe(false)
			-- Зона бойцов (макет 960×540, от края кнопок): по ширине 25–75%, по высоте от пола (25%)
			-- до низа HUD (78%). Ни одна видимая кнопка в неё не заходит.
			local zoneNear, zoneFar = 960 * 0.25, 960 * 0.75
			local zoneLow, zoneHigh = 540 * 0.25, 540 * 0.78
			for _, id in ControlsLayout.IDS do
				if id ~= "Dash" then
					local placement = layout.controls[id]
					local radius = ControlsLayout.diameter(layout, id) / 2
					local nearestX = math.clamp(placement.x, zoneNear, zoneFar)
					local nearestY = math.clamp(placement.y, zoneLow, zoneHigh)
					local distance = math.sqrt((placement.x - nearestX) ^ 2 + (placement.y - nearestY) ^ 2)
					expect(distance >= radius).toBeTruthy()
					-- И кнопки не уходят дальше трети ширины от своего края.
					expect(placement.x + radius <= 960 * 0.36).toBeTruthy()
				end
			end
		end
	)

	it("допустимые значения сохраняются", function()
		local custom = ControlsLayout.default()
		custom.mode = "Always"
		custom.opacity = 0.8
		custom.dashButton = false
		custom.controls.Heavy = { x = 300, y = 200, size = 1.3 }
		local clean = ControlsLayout.sanitize(custom)
		expect(clean.mode).toBe("Always")
		expect(clean.opacity).toBeCloseTo(0.8)
		expect(clean.dashButton).toBe(false)
		expect(clean.controls.Heavy.x).toBe(300)
		expect(clean.controls.Heavy.size).toBeCloseTo(1.3)
	end)
end)

describe("Сенсорное управление в бою", function()
	it("на ПК скрыто, на телефоне показывается", function()
		local game, client = startTraining(false)
		expect(client.find("TouchControls")).toBe(nil)
		-- На ПК внизу — подсказка клавиш (в тренировке всегда).
		expect(client.find("ControlsHint").Visible).toBe(true)
		expect(client.runtime.findGuiByText(client.find("ControlsHint"), "Shift", "TextLabel") ~= nil).toBeTruthy()
		uis(client).LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
		game.step(2)
		expect(client.find("TouchControls") ~= nil).toBeTruthy()
		expect(client.find("ControlsHint").Visible).toBe(false)
		-- Рывок по умолчанию спрятан, остальные кнопки на месте.
		expect(client.find("DashButton").Visible).toBe(false)
		expect(client.find("LightButton").Visible).toBe(true)
		expect(game.errors()).toBeEmpty()
	end)

	it(
		"плавающий джойстик: касание в любом месте слева ставит джойстик под палец",
		function()
			local game, client, match = startTraining(true)
			local fighter = match.sim.fighters[1]
			local startX = fighter.x
			local zone = client.find("JoystickZone")
			expect(zone ~= nil).toBeTruthy()
			-- Касание далеко от кружка джойстика (выше и правее), затем палец уходит вправо.
			local input = touch(330, 250)
			client.runtime.fire(zone, "InputBegan", input)
			game.step(1)
			local joystick = client.find("Joystick")
			-- Экран теста 1280×720 → масштаб интерфейса 720/540; координаты джойстика логические.
			expect(math.abs(joystick.Position.X.Offset - 330 / (720 / 540)) <= 1).toBeTruthy()
			input.Position = Vector3.new(410, 255, 0)
			uis(client).InputChanged:Fire(input, false)
			game.step(20)
			expect(fighter.x > startX + 1).toBeTruthy()
			-- Отпустили — джойстик вернулся на место, боец остановился.
			uis(client).InputEnded:Fire(input, false)
			game.step(6)
			expect(fighter.state).toBe("Idle")
			expect(joystick.Position.X.Offset).toBe(ControlsLayout.default().controls.Joystick.x)
			expect(game.errors()).toBeEmpty()
		end
	)

	it("кнопка «Рука» бьёт в момент касания", function()
		local game, client, match = startTraining(true)
		match.sim.fighters[1].x = -1
		match.sim.fighters[2].x = 1
		local dummy = match.sim.fighters[2]
		local input = touch(800, 450)
		client.runtime.fire(client.find("LightButton"), "InputBegan", input)
		game.step(12)
		expect(dummy.health < dummy.maxHealth).toBeTruthy()
		uis(client).InputEnded:Fire(input, false)
		game.step(2)
		expect(game.errors()).toBeEmpty()
	end)

	it(
		"джойстик: вправо — ходьба, отпустили — стоп, вверх — прыжок",
		function()
			local game, client, match = startTraining(true)
			local fighter = match.sim.fighters[1]
			local startX = fighter.x
			local input = touch(150, 400)
			client.runtime.fire(client.find("Joystick"), "InputBegan", input)
			input.Position = Vector3.new(230, 405, 0)
			uis(client).InputChanged:Fire(input, false)
			game.step(20)
			expect(fighter.x > startX + 1).toBeTruthy()
			expect(fighter.state).toBe("Walk")
			uis(client).InputEnded:Fire(input, false)
			game.step(6)
			expect(fighter.state).toBe("Idle")

			local jump = touch(150, 400)
			client.runtime.fire(client.find("Joystick"), "InputBegan", jump)
			jump.Position = Vector3.new(150, 320, 0)
			uis(client).InputChanged:Fire(jump, false)
			local jumped = false
			for _ = 1, 20 do
				game.step(1)
				if fighter.y > 1 then
					jumped = true
				end
			end
			expect(jumped).toBeTruthy()
			uis(client).InputEnded:Fire(jump, false)
			expect(game.errors()).toBeEmpty()
		end
	)

	it(
		"маленькое смещение пальца не двигает бойца (мёртвая зона)",
		function()
			local game, client, match = startTraining(true)
			local fighter = match.sim.fighters[1]
			local startX = fighter.x
			local input = touch(150, 400)
			client.runtime.fire(client.find("Joystick"), "InputBegan", input)
			input.Position = Vector3.new(158, 392, 0)
			uis(client).InputChanged:Fire(input, false)
			game.step(20)
			expect(fighter.x).toBeCloseTo(startX)
		end
	)

	it("кнопка «Супер» подсвечена, когда шкала полная", function()
		local game, client = startTraining(true)
		game.step(10)
		local stroke = client.find("SuperButton"):FindFirstChildOfClass("UIStroke")
		expect(stroke.Thickness).toBe(5)
		expect(game.errors()).toBeEmpty()
	end)
end)

describe("Экран «Управление»", function()
	it("перетаскивание, размер, сохранение на сервер", function()
		local game = Harness.new()
		local client = game.addClient("Alice")
		game.step(2)
		client.click("Управление")
		game.step(3)
		expect(client.find("ControlsSettings") ~= nil).toBeTruthy()
		expect(client.find("TouchControls") ~= nil).toBeTruthy()

		-- Перетаскиваем «Ногу» на 100 пикселей влево и 50 вверх.
		local drag = touch(700, 400)
		client.runtime.fire(client.find("HeavyButton"), "InputBegan", drag)
		drag.Position = Vector3.new(600, 350, 0)
		uis(client).InputChanged:Fire(drag, false)
		uis(client).InputEnded:Fire(drag, false)
		game.step(2)

		client.runtime.fire(client.find("SizePlus"):FindFirstChild("Face"), "Activated")
		game.step(2)
		client.click("Сохранить")
		game.step(3)

		local DataService = game.serverRequire("Services", "DataService")
		local saved = DataService.getControls(client.player)
		local default = ControlsLayout.default()
		expect(saved.controls.Heavy.x > default.controls.Heavy.x + 50).toBeTruthy()
		expect(saved.controls.Heavy.y > default.controls.Heavy.y + 20).toBeTruthy()
		expect(saved.controls.Heavy.size > 1).toBeTruthy()
		expect(game.errors()).toBeEmpty()
		expect(game.warnings()).toBeEmpty()
	end)

	it("режим «Никогда» прячет управление даже на телефоне", function()
		local game = Harness.new()
		local client = game.addClient("Alice")
		game.step(2)
		uis(client).LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
		client.click("Управление")
		game.step(2)
		client.click("Никогда")
		client.click("Сохранить")
		client.click("← Назад")
		game.step(2)
		client.click("Тренировка")
		game.step(10)
		expect(client.find("Battle") ~= nil).toBeTruthy()
		expect(client.find("TouchControls")).toBe(nil)
	end)
end)
