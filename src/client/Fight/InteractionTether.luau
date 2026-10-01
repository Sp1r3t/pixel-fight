--!strict
-- The chain is a separate layer joining the actual attacker and victim.
-- Hollow, alternating pixel links keep it readable without a solid beam.
local Tether = {}
export type Tether = {
	update: (start: Vector3, finish: Vector3, progress: number) -> (),
	destroy: () -> (),
}
function Tether.new(parent: Instance, style: string): Tether?
	if style ~= "brakk" and style ~= "morrow" and style ~= "tidebreaker" then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "CinematicChain"
	folder.Parent = parent
	local links: { Part } = {}
	local canvases: { BillboardGui } = {}
	local color = if style == "morrow"
		then Color3.fromRGB(124, 198, 139)
		elseif style == "tidebreaker" then Color3.fromRGB(193, 153, 111)
		else Color3.fromRGB(194, 187, 169)
	for index = 1, 40 do
		local part = Instance.new("Part")
		part.Name = `ChainLink{index}`
		part.Size = Vector3.new(0.1, 0.1, 0.1)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.CastShadow = false
		part.Parent = folder
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(0.35, 0.19)
		gui.Adornee = part
		gui.LightInfluence = 0
		gui.Enabled = false
		gui.Parent = part
		local link = Instance.new("Frame")
		link.Size = if index % 2 == 0 then UDim2.fromScale(0.95, 0.8) else UDim2.fromScale(0.5, 1)
		link.Position = if index % 2 == 0 then UDim2.fromScale(0.025, 0.1) else UDim2.fromScale(0.25, 0)
		link.BorderColor3 = color
		link.BorderSizePixel = 2
		link.BackgroundTransparency = 1
		link.Parent = gui
		links[index] = part
		canvases[index] = gui
	end
	local result = {} :: Tether
	function result.update(start: Vector3, finish: Vector3, progress: number)
		local release = if style == "brakk" then 0.39 elseif style == "tidebreaker" then 0.48 else 0.7
		local visible = progress >= 0.07 and progress < release
		local extension = math.clamp((progress - 0.07) / 0.1, 0, 1)
		local tip = start:Lerp(finish, extension)
		local distance = (tip - start).Magnitude
		local count = math.clamp(math.ceil(distance / 0.28), 1, #links)
		for index, part in links do
			local enabled = visible and index <= count
			canvases[index].Enabled = enabled
			if enabled then
				local fraction = (index - 0.5) / count
				local slack = math.sin(math.pi * fraction) * (1 - math.clamp(progress / 0.3, 0, 1)) * 0.6
				part.CFrame = CFrame.new(start:Lerp(tip, fraction) - Vector3.new(0, slack, 0))
			end
		end
	end
	function result.destroy()
		folder:Destroy()
	end
	return result
end
return Tether
