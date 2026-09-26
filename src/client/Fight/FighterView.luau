--!strict
--[[
	FighterView — визуальное представление бойца на арене.
	BillboardGui (квадрат SPRITE_SIZE × SPRITE_SIZE студов) в плоскости Z = 0 + аниматор + тень на полу.
	Сам ничего не решает: каждый кадр получает состояние из снапшота и показывает его.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Snapshot = require(ReplicatedStorage.Shared.Combat.Snapshot)
local SpriteAnimator = require(script.Parent.Parent.Sprites.SpriteAnimator)
local AnimationSelect = require(script.Parent.AnimationSelect)

export type FighterView = {
	slot: number,
	def: Types.CharacterDef,
	anchor: Part,
	update: (fighter: Snapshot.FighterSnapshot, dt: number) -> (),
	flash: (amount: number) -> (),
	-- Смещение отрисовки (постановка роликов суперов): бой на сервере при этом стоит.
	setOffset: (dx: number, dy: number) -> (),
	-- Скрыть бойца (телепорт: исчез — появился).
	setVisible: (visible: boolean) -> (),
	destroy: () -> (),
}

local SPRITE_SIZE = 8 -- студов: клетка спрайта
local FEET_IN_CELL = 0.96 -- где в клетке стоят ноги (доля высоты сверху)
local CENTER_OFFSET = SPRITE_SIZE * (FEET_IN_CELL - 0.5)

local FighterView = {}

function FighterView.new(parent: Instance, def: Types.CharacterDef, slot: number): FighterView
	local anchor = Instance.new("Part")
	anchor.Name = `Fighter{slot}`
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(0, CENTER_OFFSET, 0)
	anchor.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sprite"
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(SPRITE_SIZE, SPRITE_SIZE)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = anchor

	local animator = SpriteAnimator.new(gui, def)

	-- Тень: плоский тёмный диск на полу, уменьшается в прыжке.
	local shadow = Instance.new("Part")
	shadow.Name = `Shadow{slot}`
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CastShadow = false
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Transparency = 0.55
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Size = Vector3.new(0.05, 3, 3)
	shadow.Parent = parent

	local flashAmount = 0
	local offsetX, offsetY = 0, 0

	local view = {} :: FighterView
	view.slot = slot
	view.def = def
	view.anchor = anchor

	function view.update(fighter: Snapshot.FighterSnapshot, dt: number)
		-- Атакующий боец чуть ближе к камере, чтобы его удар рисовался поверх противника.
		local z = if fighter.state == "Attack" then 0.3 else 0.1 * slot
		anchor.CFrame = CFrame.new(fighter.x + offsetX, fighter.y + offsetY + CENTER_OFFSET, z)

		local shadowScale = math.clamp(1 - fighter.y / 12, 0.4, 1)
		shadow.Size = Vector3.new(0.05, 3 * shadowScale, 2 * shadowScale)
		-- Цилиндр лежит на боку: ось X вверх.
		shadow.CFrame = CFrame.new(fighter.x, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90))

		local choice = AnimationSelect.choose(fighter, def.id)
		animator.setFacing(fighter.facing)
		animator.show(choice.name, choice.time, choice.progress)

		if flashAmount > 0 then
			flashAmount = math.max(0, flashAmount - dt * 6)
		end
		animator.setFlash(flashAmount)
	end

	function view.flash(amount: number)
		flashAmount = math.max(flashAmount, amount)
	end

	function view.setOffset(dx: number, dy: number)
		offsetX, offsetY = dx, dy
	end

	function view.setVisible(visible: boolean)
		gui.Enabled = visible
		shadow.Transparency = if visible then 0.55 else 1
	end

	function view.destroy()
		animator.destroy()
		anchor:Destroy()
		shadow:Destroy()
	end

	return view
end

return FighterView
