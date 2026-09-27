--!strict
--[[
	SpriteAnimator — единый интерфейс анимации бойца.

	  • если у персонажа задан спрайт-лист (Characters[..].sprites) — SheetSprite
	    (ImageLabel + ImageRectOffset/ImageRectSize, ResampleMode = Pixelated);
	  • иначе — Rig, детализированный процедурный боец (скелет с локтями и коленями, облик из
	    Config/CharacterLooks, ткань с физикой, шлейфы ударов, свечение магии).

	Аниматор не хранит время сам: каждый кадр бой сообщает, какую анимацию показать
	и сколько времени персонаж в этом состоянии (или прогресс удара по фреймдате).
	Так анимация всегда совпадает с серверной симуляцией.

	Замена плейсхолдеров на арт: загрузить лист в Roblox и заполнить поле sprites персонажа:
	    sprites = { image = "rbxassetid://…", frameWidth = 64, frameHeight = 64, animations = {} }
	(animations можно оставить пустым, если лист следует стандартной раскладке Config/Animations).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local SheetSprite = require(script.Parent.SheetSprite)
local Rig = require(script.Parent.Rig)

export type Animator = {
	root: GuiObject,
	kind: "Sheet" | "Rig",
	show: (animation: Types.AnimationName, time: number, progress: number?) -> (),
	setFacing: (facing: number) -> (),
	setFlash: (amount: number) -> (),
	-- Подкраска к цвету (силуэт в меню): 0 — исходные цвета, 1 — целиком цвет.
	setTint: (color: Color3, amount: number) -> (),
	-- Время кадра и скорость бойца (студ/с) — для ткани и эффектов; вызывается перед show.
	update: (dt: number, vx: number, vy: number) -> (),
	destroy: () -> (),
}

local function noUpdate(_dt: number, _vx: number, _vy: number) end

local SpriteAnimator = {}

function SpriteAnimator.new(parent: Instance, def: Types.CharacterDef): Animator
	local sheet = def.sprites
	if sheet ~= nil then
		local sprite = SheetSprite.new(parent, sheet)
		return {
			root = sprite.root,
			kind = "Sheet",
			show = sprite.show,
			setFacing = sprite.setFacing,
			setFlash = sprite.setFlash,
			setTint = sprite.setTint,
			update = noUpdate,
			destroy = sprite.destroy,
		}
	end
	local rig = Rig.new(parent, def)
	return {
		root = rig.root,
		kind = "Rig",
		show = rig.show,
		setFacing = rig.setFacing,
		setFlash = rig.setFlash,
		setTint = rig.setTint,
		update = rig.update,
		destroy = rig.destroy,
	}
end

return SpriteAnimator
