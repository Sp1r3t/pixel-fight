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

	Пиксель-арт уже нарисован процедурно (tools/pixelart/, см. его README) — art/sprites/<id>.png
	на каждого из 16 бойцов. Включить: загрузить PNG в Roblox Studio и вписать rbxassetid в
	Config/CharacterSprites.luau — CharacterRegistry сам подставит его в CharacterDef.sprites,
	никакой код здесь трогать не нужно. Пока запись не заполнена — используется Rig.
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

local SpriteAnimator = {}

local function noUpdate(_dt: number, _vx: number, _vy: number) end

function SpriteAnimator.new(parent: Instance, def: Types.CharacterDef): Animator
	local sheet = def.sprites
	if sheet ~= nil then
		local sprite = SheetSprite.new(parent, sheet)
		return {
			root = sprite.root,
			kind = "Sheet",
			show = function(animation, time, progress)
				sprite.show(animation, time, progress)
			end,
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
