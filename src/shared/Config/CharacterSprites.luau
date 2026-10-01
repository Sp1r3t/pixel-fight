--!strict
-- Six uploaded arcade atlases use the generated 128px / eight-column layout.
-- Import IDs with tools/pixelart/import-arcade.js; see art/sprites/v3/README.md.
-- Until all six pages are supplied, retain the existing two-page legacy sheet.

local Types = require(script.Parent.Parent.Types)
local Uploads = require(script.Parent.CharacterSpriteUploads)
local Arcade = require(script.Parent.ArcadeSpriteLayout)
local ConceptUploads = require(script.Parent.ConceptSpriteUploads)
local ConceptLayout = require(script.Parent.ConceptSpriteLayout)
local CombatProfiles = require(script.Parent.CombatProfiles)

local FRAME = 120
local ROWS = 12 -- 0=Idle 1=Walk 2=Dash 3=Jump 4=Crouch 5=Block 6=Light 7=Heavy 8=Special 9=Super 10=Hit 11=Knockdown
local SPLIT_ROW = 6 -- ряды >= 6 берутся из второго файла (_b.png)

local function sheet(assetIdA: string, assetIdB: string): Types.SpriteSheet
	return {
		stableIdle = true,
		image = assetIdA,
		image2 = assetIdB,
		splitRow = SPLIT_ROW,
		frameWidth = FRAME,
		frameHeight = FRAME,
		rows = ROWS,
		animations = {},
	}
end

local Sprites: { [string]: Types.SpriteSheet } = {
	rook = sheet("rbxassetid://76152170271717", "rbxassetid://84325922161652"),
	mira = sheet("rbxassetid://109125083921355", "rbxassetid://111832141677194"),
	brakk = sheet("rbxassetid://77863204197002", "rbxassetid://104490252287801"),
	juno = sheet("rbxassetid://106169331103975", "rbxassetid://93213090780163"),
	sable = sheet("rbxassetid://137157976896996", "rbxassetid://129980444725804"),
	dax = sheet("rbxassetid://73516415550906", "rbxassetid://124192228014738"),
	wren = sheet("rbxassetid://81077781417736", "rbxassetid://139330523051420"),
	sorren = sheet("rbxassetid://99485743466879", "rbxassetid://95565237722719"),
	pike = sheet("rbxassetid://131192541460295", "rbxassetid://83285744919314"),
	zip = sheet("rbxassetid://107757702543013", "rbxassetid://76853391939899"),
	ashka = sheet("rbxassetid://95109300264059", "rbxassetid://115699173612019"),
	glacia = sheet("rbxassetid://136665708563389", "rbxassetid://119619418775286"),
	tempest = sheet("rbxassetid://132161571516048", "rbxassetid://84846350329776"),
	byte = sheet("rbxassetid://100149680469092", "rbxassetid://91310348954806"),
	morrow = sheet("rbxassetid://121448820348133", "rbxassetid://76561755274288"),
	astra = sheet("rbxassetid://90211975640551", "rbxassetid://116399239779900"),
}

local CharacterSprites = {}

function CharacterSprites.getConcept(id: string): Types.SpriteSheet?
	local profile = CombatProfiles.get(id)
	local pages = ConceptUploads[if profile then profile.id else id]
	if pages == nil or (#pages ~= 6 and #pages ~= 8) then
		return nil
	end
	local animations = ConceptLayout
	if #pages == 6 then
		animations = table.clone(ConceptLayout)
		for name, animation in animations do
			if animation.page and animation.page > 6 then
				animations[name] = nil
			end
		end
	end
	return {
		image = pages[1],
		pages = pages,
		columns = 4,
		frameWidth = 256,
		frameHeight = 256,
		animations = animations,
	}
end

function CharacterSprites.get(characterId: string): Types.SpriteSheet?
	local concept = CharacterSprites.getConcept(characterId)
	if concept then
		return concept
	end
	local pages = Uploads[characterId]
	if pages and #pages == 6 then
		return {
			image = pages[1],
			pages = pages,
			columns = 8,
			frameWidth = 128,
			frameHeight = 128,
			animations = Arcade,
		}
	end
	local entry = Sprites[characterId]
	if entry == nil or entry.image == "rbxassetid://0" or entry.image == "" then
		return nil
	end
	return entry
end

return CharacterSprites
