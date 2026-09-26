--!strict
--[[
	Хитбоксы (чем бьют) и хартбоксы (куда можно попасть) — прямоугольники в координатах арены.
]]

local Types = require(script.Parent.Parent.Types)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local Physics = GameConfig.Physics
local HURT_HALF_WIDTH = GameConfig.Combat.HurtboxWidth / 2

export type Rect = {
	left: number,
	right: number,
	bottom: number,
	top: number,
}

-- Форма тела для хартбокса: стоя, сидя, в воздухе или неуязвим.
export type HurtKind = "Stand" | "Crouch" | "Air" | "None"

local Hitbox = {}

--[[
	Хитбокс удара. reach — множитель дальности (характеристика «дальность» для обычных ударов).
	Прямоугольник зеркалится по направлению взгляда бойца.
]]
function Hitbox.attack(x: number, y: number, facing: number, box: Types.Box, reach: number): Rect
	local centerX = x + facing * box.x * reach
	local halfWidth = box.w * reach / 2
	return {
		left = centerX - halfWidth,
		right = centerX + halfWidth,
		bottom = y + box.y - box.h / 2,
		top = y + box.y + box.h / 2,
	}
end

function Hitbox.hurt(x: number, y: number, kind: HurtKind): Rect?
	if kind == "None" then
		return nil
	elseif kind == "Crouch" then
		return { left = x - HURT_HALF_WIDTH, right = x + HURT_HALF_WIDTH, bottom = y, top = y + Physics.CrouchHeight }
	elseif kind == "Air" then
		return {
			left = x - HURT_HALF_WIDTH * 0.9,
			right = x + HURT_HALF_WIDTH * 0.9,
			bottom = y + 0.4,
			top = y + Physics.StandHeight - 0.4,
		}
	end
	return { left = x - HURT_HALF_WIDTH, right = x + HURT_HALF_WIDTH, bottom = y, top = y + Physics.StandHeight }
end

function Hitbox.overlaps(a: Rect, b: Rect): boolean
	return a.left < b.right and b.left < a.right and a.bottom < b.top and b.bottom < a.top
end

-- Точка попадания: середина пересечения прямоугольников (для искр на клиенте).
function Hitbox.contactPoint(a: Rect, b: Rect): (number, number)
	local left = math.max(a.left, b.left)
	local right = math.min(a.right, b.right)
	local bottom = math.max(a.bottom, b.bottom)
	local top = math.min(a.top, b.top)
	return (left + right) / 2, (bottom + top) / 2
end

return Hitbox
