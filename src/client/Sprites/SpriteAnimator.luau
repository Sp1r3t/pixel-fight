--!strict
--[[
	SpriteAnimator — единый интерфейс анимации бойца.

	  • если у персонажа задан спрайт-лист (Characters[..].sprites) — SheetSprite
	    (ImageLabel + ImageRectOffset/ImageRectSize, ResampleMode = Pixelated);
	  • иначе — PuppetSprite, процедурная пиксельная «кукла» из цветов палитры.

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
local PuppetSprite = require(script.Parent.PuppetSprite)

export type Animator = {
	root: GuiObject,
	kind: "Sheet" | "Puppet",
	show: (animation: Types.AnimationName, time: number, progress: number?) -> (),
	setFacing: (facing: number) -> (),
	setFlash: (amount: number) -> (),
	destroy: () -> (),
}

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
			destroy = sprite.destroy,
		}
	end
	local puppet = PuppetSprite.new(parent, def)
	return {
		root = puppet.root,
		kind = "Puppet",
		show = puppet.show,
		setFacing = puppet.setFacing,
		setFlash = puppet.setFlash,
		destroy = puppet.destroy,
	}
end

return SpriteAnimator
