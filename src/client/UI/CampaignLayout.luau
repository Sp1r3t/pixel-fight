--!strict
-- Shared geometry for the map, route and review tools.
local Layout = { Width = 912, Height = 284, ViewWidth = 912 }
local stops = {
	{ Vector2.new(108, 169), Vector2.new(322, 119), Vector2.new(516, 205), Vector2.new(806, 139) },
	{ Vector2.new(106, 202), Vector2.new(291, 125), Vector2.new(559, 169), Vector2.new(810, 117) },
	{ Vector2.new(108, 137), Vector2.new(361, 199), Vector2.new(550, 108), Vector2.new(806, 195) },
	{ Vector2.new(112, 199), Vector2.new(318, 132), Vector2.new(566, 203), Vector2.new(808, 134) },
	{ Vector2.new(104, 153), Vector2.new(320, 202), Vector2.new(536, 132), Vector2.new(806, 185) },
}
-- Different entry and exit tangents let each road wind around its landscape.
local bends = {
	{ { 45, 52 }, { -24, -50 }, { 45, 58 } },
	{ { -28, 48 }, { 62, -42 }, { -47, -34 } },
	{ { 50, -32 }, { 46, 52 }, { -24, -47 } },
	{ { 38, 44 }, { -35, -54 }, { 46, 42 } },
	{ { -28, -50 }, { 38, 52 }, { -42, -25 } },
}
function Layout.pageOf(order: number): number
	return math.floor((order - 1) / 4)
end
function Layout.pageAt(x: number): number
	return math.clamp(math.floor(x / Layout.Width + 0.5), 0, #stops - 1)
end
function Layout.point(order: number): Vector2
	local chapter = Layout.pageOf(order)
	local stop = stops[chapter + 1][(order - 1) % 4 + 1]
	return Vector2.new(chapter * Layout.Width + stop.X, stop.Y)
end
function Layout.curve(order: number, t: number): Vector2
	local a, b = Layout.point(order), Layout.point(order + 1)
	local segment = (order - 1) % 4 + 1
	local bend = if segment < 4 then bends[Layout.pageOf(order) + 1][segment] else { -18, 18 }
	local dx = b.X - a.X
	local c1 = a + Vector2.new(dx * 0.38, bend[1])
	local c2 = b - Vector2.new(dx * 0.32, bend[2])
	local u = 1 - t
	return a * u ^ 3 + c1 * (3 * u ^ 2 * t) + c2 * (3 * u * t ^ 2) + b * t ^ 3
end
return table.freeze(Layout)
