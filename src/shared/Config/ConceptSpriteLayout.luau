--!strict
-- Approved concept animation pages: 256px cells, four columns.
local Types = require(script.Parent.Parent.Types)
local animations: { [Types.AnimationName]: Types.SpriteAnimation } = {
	Idle = { page = 1, row = 0, frames = 4, fps = 6, loop = true },
	Walk = { page = 1, row = 1, frames = 4, fps = 12, loop = true },
	Dash = { page = 1, row = 2, frames = 4, fps = 12, loop = false },
	Jump = { page = 1, row = 3, frames = 4, fps = 12, loop = false },
	BackJump = { page = 2, row = 0, frames = 4, fps = 12, loop = false },
	Crouch = { page = 2, row = 1, frames = 4, fps = 12, loop = false },
	Block = { page = 2, row = 2, frames = 4, fps = 12, loop = false },
	Hit = { page = 2, row = 3, frames = 4, fps = 12, loop = false },
	Light = { page = 3, row = 0, frames = 4, fps = 12, loop = false },
	Light2 = { page = 3, row = 1, frames = 4, fps = 12, loop = false },
	Light3 = { page = 3, row = 2, frames = 4, fps = 12, loop = false },
	Heavy = { page = 3, row = 3, frames = 4, fps = 12, loop = false },
	CrouchLight = { page = 4, row = 0, frames = 4, fps = 12, loop = false },
	CrouchHeavy = { page = 4, row = 1, frames = 4, fps = 12, loop = false },
	AirLight = { page = 4, row = 2, frames = 4, fps = 12, loop = false },
	AirHeavy = { page = 4, row = 3, frames = 4, fps = 12, loop = false },
	Knockdown = { page = 5, row = 0, frames = 4, fps = 12, loop = false },
	WakeUp = { page = 5, row = 1, frames = 4, fps = 12, loop = false },
	Special = { page = 5, row = 2, frames = 8, fps = 12, loop = false },
	Super = { page = 6, row = 0, frames = 16, fps = 8, loop = false },
	Pulled = { page = 7, row = 0, frames = 4, fps = 12, loop = false },
	Grabbed = { page = 7, row = 1, frames = 4, fps = 12, loop = false },
	Lifted = { page = 7, row = 2, frames = 4, fps = 12, loop = false },
	Thrown = { page = 7, row = 3, frames = 4, fps = 12, loop = false },
	Launched = { page = 8, row = 0, frames = 4, fps = 12, loop = false },
	Slammed = { page = 8, row = 1, frames = 4, fps = 12, loop = false },
	Bound = { page = 8, row = 2, frames = 4, fps = 12, loop = false },
	Suspended = { page = 8, row = 3, frames = 4, fps = 12, loop = false },
}
return animations
