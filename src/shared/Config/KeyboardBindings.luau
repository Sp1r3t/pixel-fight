--!strict
local KeyboardBindings = {}
export type Bindings = { [string]: { string } }
local actions = { "MoveLeft", "MoveRight", "Jump", "Crouch", "Light", "Heavy", "Special", "Super", "Block", "Dash" }
local defaults: Bindings = {
	MoveLeft = { "A", "Left" },
	MoveRight = { "D", "Right" },
	Jump = { "W", "Up", "Space" },
	Crouch = { "S", "Down" },
	Light = { "J" },
	Heavy = { "K" },
	Special = { "L" },
	Super = { "I" },
	Block = { "Q" },
	Dash = { "LeftShift", "RightShift" },
}
local allowed: { [string]: boolean } = {}
for byte = string.byte("A"), string.byte("Z") do
	allowed[string.char(byte)] = true
end
for _, key in
	{
		"Zero",
		"One",
		"Two",
		"Three",
		"Four",
		"Five",
		"Six",
		"Seven",
		"Eight",
		"Nine",
		"Space",
		"Left",
		"Right",
		"Up",
		"Down",
		"LeftShift",
		"RightShift",
		"LeftControl",
		"RightControl",
		"LeftAlt",
		"RightAlt",
		"Tab",
		"Return",
		"Backspace",
		"Minus",
		"Equals",
		"LeftBracket",
		"RightBracket",
		"Semicolon",
		"Quote",
		"Comma",
		"Period",
		"Slash",
		"BackSlash",
		"Insert",
		"Delete",
		"Home",
		"End",
		"PageUp",
		"PageDown",
	}
do
	allowed[key] = true
end
for index = 1, 12 do
	allowed[`F{index}`] = true
end

function KeyboardBindings.default(): Bindings
	local result: Bindings = {}
	for action, keys in defaults do
		result[action] = table.clone(keys)
	end
	return result
end
function KeyboardBindings.isAllowed(key: string): boolean
	return allowed[key] == true
end
function KeyboardBindings.sanitize(raw: unknown): Bindings
	local result = KeyboardBindings.default()
	if type(raw) ~= "table" then
		return result
	end
	for _, action in actions do
		local keys = (raw :: any)[action]
		if keys ~= nil then
			if type(keys) ~= "table" or #keys < 1 or #keys > 3 then
				return KeyboardBindings.default()
			end
			local clean: { string } = {}
			for _, key in keys do
				if type(key) ~= "string" or not allowed[key] then
					return KeyboardBindings.default()
				end
				table.insert(clean, key)
			end
			result[action] = clean
		end
	end
	local used: { [string]: boolean } = {}
	for _, action in actions do
		for _, key in result[action] do
			if used[key] then
				return KeyboardBindings.default()
			end
			used[key] = true
		end
	end
	return result
end
KeyboardBindings.actions = table.freeze(actions)
return table.freeze(KeyboardBindings)
