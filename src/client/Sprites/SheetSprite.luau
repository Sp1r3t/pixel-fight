--!strict
--[[
	Отрисовка кадров из спрайт-листа: ImageLabel + ImageRectOffset/ImageRectSize,
	ResampleMode = Pixelated (чёткие пиксели при любом масштабе).

	Раскладка листа: одна анимация — одна строка, кадры слева направо, размер кадра frameWidth×frameHeight.
	Строку/число кадров/fps каждой анимации можно задать в Characters[..].sprites.animations,
	иначе берутся значения по умолчанию из Config/Animations.

	Зеркалирование (боец смотрит влево): отрицательная ширина ImageRectSize со сдвигом
	ImageRectOffset на правый край кадра.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Animations = require(ReplicatedStorage.Shared.Config.Animations)

export type SheetSprite = {
	root: ImageLabel,
	show: (animation: Types.AnimationName, time: number, progress: number?) -> (),
	setFacing: (facing: number) -> (),
	setFlash: (amount: number) -> (),
	destroy: () -> (),
}

local IDLE: Types.AnimationName = "Idle"

type ResolvedAnimation = { row: number, frames: number, fps: number, loop: boolean }

local SheetSprite = {}

-- Параметры анимации с учётом переопределений в листе и запасных анимаций.
local function resolve(sheet: Types.SpriteSheet, animation: Types.AnimationName): ResolvedAnimation
	local current: Types.AnimationName? = animation
	for _ = 1, 4 do
		if current == nil then
			break
		end
		local custom = sheet.animations[current]
		if custom then
			return { row = custom.row, frames = custom.frames, fps = custom.fps, loop = custom.loop }
		end
		current = Animations.fallbacks[current]
	end
	-- Стандартная раскладка: если строки анимации нет в листе — запасная анимация.
	local name: Types.AnimationName = animation
	for _ = 1, 4 do
		local def = Animations.defaults[name]
		if def and (sheet.rows == nil or def.row < (sheet.rows :: number)) then
			return { row = def.row, frames = def.frames, fps = def.fps, loop = def.loop }
		end
		local fallback = Animations.fallbacks[name]
		if fallback == nil then
			break
		end
		name = fallback :: Types.AnimationName
	end
	local idle = Animations.defaults[IDLE]
	return { row = idle.row, frames = idle.frames, fps = idle.fps, loop = idle.loop }
end

-- Номер кадра (с 0) для момента времени или прогресса удара.
function SheetSprite.frameIndex(anim: ResolvedAnimation, time: number, progress: number?): number
	if anim.frames <= 1 then
		return 0
	end
	if progress ~= nil then
		return math.clamp(math.floor(progress * anim.frames), 0, anim.frames - 1)
	end
	local index = math.floor(time * anim.fps)
	if anim.loop then
		return index % anim.frames
	end
	return math.clamp(index, 0, anim.frames - 1)
end

function SheetSprite.new(parent: Instance, sheet: Types.SpriteSheet): SheetSprite
	local image = Instance.new("ImageLabel")
	image.Name = "Sheet"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = sheet.image
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image.ImageRectSize = Vector2.new(sheet.frameWidth, sheet.frameHeight)
	image.Parent = parent

	local facing = 1

	local sprite = {} :: SheetSprite
	sprite.root = image

	function sprite.show(animation: Types.AnimationName, time: number, progress: number?)
		local anim = resolve(sheet, animation)
		local column = SheetSprite.frameIndex(anim, time, progress)
		local x = column * sheet.frameWidth
		local y = anim.row * sheet.frameHeight
		if facing >= 0 then
			image.ImageRectOffset = Vector2.new(x, y)
			image.ImageRectSize = Vector2.new(sheet.frameWidth, sheet.frameHeight)
		else
			image.ImageRectOffset = Vector2.new(x + sheet.frameWidth, y)
			image.ImageRectSize = Vector2.new(-sheet.frameWidth, sheet.frameHeight)
		end
	end

	function sprite.setFacing(newFacing: number)
		facing = if newFacing < 0 then -1 else 1
	end

	-- Реакция на удар: ImageColor3 умеет только тонировать, поэтому кадр кратко краснеет.
	function sprite.setFlash(amount: number)
		image.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 110, 110), math.clamp(amount, 0, 1))
	end

	function sprite.destroy()
		image:Destroy()
	end

	sprite.show("Idle", 0, nil)
	return sprite
end

return SheetSprite
