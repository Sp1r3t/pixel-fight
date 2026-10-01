--!strict
-- Generated from arcade-poses.js. Local atlas rows; each animation wraps after 8 frames.
local Types = require(script.Parent.Parent.Types)
local animations: { [Types.AnimationName]: Types.SpriteAnimation } = {
	Idle = { page = 1, row = 0, frames = 16, fps = 8, loop = true },
	Walk = { page = 1, row = 2, frames = 16, fps = 24, loop = true },
	Dash = { page = 1, row = 4, frames = 16, fps = 48, loop = false },
	Jump = { page = 1, row = 6, frames = 16, fps = 24, loop = false },
	Crouch = { page = 2, row = 0, frames = 16, fps = 40, loop = false },
	Block = { page = 2, row = 2, frames = 16, fps = 40, loop = false },
	Light = { page = 2, row = 4, frames = 16, fps = 0, loop = false },
	Heavy = { page = 2, row = 6, frames = 16, fps = 0, loop = false },
	Special = { page = 3, row = 0, frames = 16, fps = 0, loop = false },
	Hit = { page = 3, row = 2, frames = 16, fps = 32, loop = false },
	Knockdown = { page = 3, row = 4, frames = 16, fps = 24, loop = false },
	CrouchLight = { page = 3, row = 6, frames = 16, fps = 0, loop = false },
	CrouchHeavy = { page = 4, row = 0, frames = 16, fps = 0, loop = false },
	AirLight = { page = 4, row = 2, frames = 16, fps = 0, loop = false },
	AirHeavy = { page = 4, row = 4, frames = 16, fps = 0, loop = false },
	Light2 = { page = 4, row = 6, frames = 16, fps = 0, loop = false },
	Light3 = { page = 5, row = 0, frames = 16, fps = 0, loop = false },
	BackJump = { page = 5, row = 2, frames = 16, fps = 24, loop = false },
	Super = { page = 6, row = 0, frames = 64, fps = 0, loop = false },
}
return animations
