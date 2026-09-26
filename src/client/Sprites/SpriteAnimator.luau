--!strict
--[[
	SpriteAnimator — анимации на спрайт-листах.  [этап 2]

	План:
	  • ImageLabel + ImageRectOffset/ImageRectSize, ResampleMode = Pixelated;
	  • анимации idle, walk, dash, jump, crouch, block, light, heavy, special, super,
	    hit, knockdown, win, lose с настраиваемой частотой кадров (Types.SpriteSheet);
	  • пока арта нет — процедурный плейсхолдер из цветов палитры персонажа;
	    замена на настоящий арт = заполнить поле sprites в Config/Characters.

	Сейчас это пустой модуль-заглушка.
]]

local SpriteAnimator = {}

return SpriteAnimator
