local function setup()
	local runtime = newRuntime({ isClient = true })
	local loader = newLoader({ globals = runtime.globals, services = runtime.services })
	local function client(...)
		return loader.require(loader.get("StarterPlayer", "StarterPlayerScripts", "Client", ...))
	end
	return runtime, client
end

describe("Sprite atlas", function()
	it("selects and advances attack frames even before IsLoaded is true", function()
		local runtime, client = setup()
		local sprite = client("Sprites", "SheetSprite").new(runtime.globals.Instance.new("Frame"), {
			image = "rbxassetid://1",
			pages = { "rbxassetid://1", "rbxassetid://2" },
			columns = 8,
			frameWidth = 128,
			frameHeight = 128,
			animations = { Light = { page = 2, row = 0, frames = 16, fps = 0, loop = false } },
		})
		local idle = sprite.root:FindFirstChild("Page1")
		local attack = sprite.root:FindFirstChild("Page2")
		attack.IsLoaded = false
		expect(sprite.show("Light", 0, 0.5)).toBe(false)
		expect(idle.ImageTransparency).toBe(1)
		expect(attack.Visible).toBe(true)
		expect(attack.ImageTransparency).toBe(0)
		expect(attack.ImageRectOffset).toBe(Vector2.new(0, 128))
		expect(sprite.root.Image).toBe("rbxassetid://2")
		sprite.show("Light", 0, 0.75)
		expect(attack.ImageRectOffset).toBe(Vector2.new(512, 128))
		attack.IsLoaded = true
		expect(sprite.show("Light", 0, 0.5)).toBe(true)
		expect(idle.ImageTransparency).toBe(1)
		expect(attack.ImageTransparency).toBe(0)
		expect(attack.ImageRectOffset).toBe(Vector2.new(0, 128))
		sprite.setFacing(-1)
		sprite.show("Light", 0, 1)
		expect(attack.ImageRectOffset).toBe(Vector2.new(1024, 128))
		expect(attack.ImageRectSize).toBe(Vector2.new(-128, 128))
		sprite.setFlash(1)
		expect(attack.ImageColor3).toBe(sprite.root.ImageColor3)
		sprite.destroy()
	end)
	it("never substitutes rigs for any of the 16 pixel fighters while pages load", function()
		local runtime, client = setup()
		for _, def in requireShared("Characters", "CharacterRegistry").list() do
			local animator = client("Sprites", "SpriteAnimator").new(runtime.globals.Instance.new("Frame"), def)
			expect(animator.kind).toBe("Sheet")
			for _, page in animator.root:GetChildren() do
				page.IsLoaded = false
			end
			for name, anim in def.sprites.animations do
				animator.show(name, 0, 0)
				local page = animator.root:FindFirstChild("Page" .. anim.page)
				local start = page.ImageRectOffset
				animator.show(name, 0.1, 0.5)
				expect(page.ImageRectOffset ~= start).toBeTruthy()
				expect(page.Visible).toBe(true)
				expect(page.ImageTransparency).toBe(0)
				expect(animator.root:FindFirstChild("Rig")).toBe(nil)
			end
			animator.destroy()
		end
	end)
	it("wraps frame 8 onto the next row and mirrors within that frame", function()
		local runtime, client = setup()
		local Sheet = client("Sprites", "SheetSprite")
		local sprite = Sheet.new(runtime.globals.Instance.new("Frame"), {
			image = "rbxassetid://1",
			pages = { "rbxassetid://1", "rbxassetid://2" },
			columns = 8,
			frameWidth = 128,
			frameHeight = 128,
			animations = { Light = { page = 2, row = 4, frames = 16, fps = 0, loop = false } },
		})
		sprite.show("Light", 0, 0.5)
		expect(sprite.root.Image).toBe("rbxassetid://2")
		expect(sprite.root.ImageRectOffset).toBe(Vector2.new(0, 640))
		sprite.setFacing(-1)
		sprite.show("Light", 0, 0.5)
		expect(sprite.root.ImageRectOffset).toBe(Vector2.new(128, 640))
		expect(sprite.root.ImageRectSize).toBe(Vector2.new(-128, 128))
		sprite.show("Light", 0, 1)
		expect(sprite.root.ImageRectOffset).toBe(Vector2.new(1024, 640))
		sprite.destroy()
	end)

	it("keeps legacy idle planted without scrolling frames horizontally", function()
		local runtime, client = setup()
		local Sheet = client("Sprites", "SheetSprite")
		local sprite = Sheet.new(runtime.globals.Instance.new("Frame"), {
			image = "rbxassetid://1",
			frameWidth = 120,
			frameHeight = 120,
			stableIdle = true,
			animations = {},
		})
		for _, time in { 0, 0.2, 0.5, 1, 1.5, 2 } do
			sprite.show("Idle", time)
			expect(sprite.root.ImageRectOffset).toBe(Vector2.new(0, 0))
			expect(sprite.root.Position.X.Scale).toBe(0)
			expect(sprite.root.Size.X.Scale).toBe(1)
			expect(sprite.root.Position.Y.Scale + sprite.root.Size.Y.Scale * 0.96).toBeCloseTo(0.96, 1e-6)
		end
		sprite.show("Walk", 0.2)
		expect(sprite.root.Size.Y.Scale).toBe(1)
		expect(sprite.root.Position.Y.Scale).toBe(0)
		sprite.destroy()
	end)

	it("defines separate crouching and aerial attacks with valid atlas bounds", function()
		local layout = requireShared("Config", "ArcadeSpriteLayout")
		local count = 0
		for _, anim in layout do
			count += 1
			expect(anim.frames == 16 or anim.frames == 64).toBeTruthy()
			expect(anim.page >= 1 and anim.page <= 6).toBeTruthy()
			expect((anim.row + math.ceil(anim.frames / 8)) * 128 <= 1024).toBeTruthy()
		end
		expect(count).toBe(20)
		expect(layout.Super.frames).toBe(64)
		expect(layout.Super.page).toBe(6)
		expect(layout.Light2.row ~= layout.Light.row or layout.Light2.page ~= layout.Light.page).toBeTruthy()
		expect(layout.Light3.row ~= layout.Light2.row or layout.Light3.page ~= layout.Light2.page).toBeTruthy()
		expect(layout.AirHeavy.page ~= layout.Heavy.page).toBeTruthy()
		expect(layout.CrouchLight.row ~= layout.Light.row or layout.CrouchLight.page ~= layout.Light.page).toBeTruthy()
	end)

	it("uses clothed rigs instead of legacy sheets while replacement outfits await upload", function()
		local Looks = requireShared("Config", "CharacterLooks")
		local Sprites = requireShared("Config", "CharacterSprites")
		local Uploads = requireShared("Config", "CharacterSpriteUploads")
		for _, id in { "rook", "brakk", "sable" } do
			local look = Looks.get(id)
			expect(look.top.style ~= "Bare").toBeTruthy()
			expect(look.sleeves).toBe("Full")
			if not Uploads[id] then
				expect(Sprites.get(id)).toBe(nil)
			end
		end
	end)
end)

describe("Smooth presentation clock", function()
	local function fighter(frame, flags)
		return {
			x = 0,
			y = 0,
			vx = 0,
			vy = 0,
			state = "Idle",
			move = 0,
			stateFrame = frame,
			moveFrame = frame,
			flags = flags or 0,
		}
	end
	local function snapshot(frame, f)
		return { frame = frame, fighters = { f }, projectiles = {} }
	end
	it("retains fractional animation time between packets", function()
		local _, client = setup()
		local buffer = client("Fight", "SnapshotBuffer").new(0)
		buffer.push(snapshot(0, fighter(0)), 0)
		buffer.push(snapshot(2, fighter(2)), 2 / 60)
		local sample = buffer.sample(1.25 / 60)
		expect(sample.fighters[1].stateFrame).toBeCloseTo(1.25, 1e-6)
		expect(sample.fighters[1].moveFrame).toBeCloseTo(1.25, 1e-6)
	end)
	it("does not animate through hitstop or interpolate a restarted move backwards", function()
		local _, client = setup()
		local Buffer = client("Fight", "SnapshotBuffer")
		local Flags = requireShared("Combat", "Snapshot").Flags
		local buffer = Buffer.new(0)
		buffer.push(snapshot(0, fighter(10, Flags.Hitstop)), 0)
		buffer.push(snapshot(2, fighter(10, Flags.Hitstop)), 2 / 60)
		expect(buffer.sample(1 / 60).fighters[1].stateFrame).toBe(10)
		expect(buffer.sample(3 / 60).fighters[1].stateFrame).toBe(10)
		buffer.reset()
		buffer.push(snapshot(0, fighter(10)), 0)
		buffer.push(snapshot(2, fighter(0)), 2 / 60)
		expect(buffer.sample(1 / 60).fighters[1].stateFrame).toBe(10)
	end)
end)
