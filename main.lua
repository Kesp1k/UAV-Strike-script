-- UAV Strike v1
local GUI = loadstring(readfile("iyai_data/Gui.lua"))()
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local cam = workspace.CurrentCamera
local lp = Players.LocalPlayer

local state = { esp = false, boost = false }
local boostSpeed = 600
local SPEED_STEP = 25
local highlights = {}
local boxes = {}
local originals = {}
local closed = false

local COL_GREEN = Color3.fromRGB(0, 160, 90)
local COL_TRACK = Color3.fromRGB(80, 80, 80)
local COL_ROW   = Color3.fromRGB(50, 50, 50)
local COL_WHITE = Color3.fromRGB(255, 255, 255)
local COL_ESP_FILL    = Color3.fromRGB(255, 0, 0)
local COL_ESP_OUTLINE = Color3.fromRGB(0, 0, 0)

local function isMine(m)
	local pv = m:FindFirstChild("Player")
	local ov = m:FindFirstChild("Operator")
	return (pv and pv.Value == lp) or (ov and ov.Value == lp)
end

local function droneRoots()
	local roots = {}
	local d = workspace:FindFirstChild("Drones")
	if d then table.insert(roots, d) end
	table.insert(roots, workspace)
	return roots
end

local function getDrone()
	local found
	for _, root in ipairs(droneRoots()) do
		for _, v in ipairs(root:GetChildren()) do
			if v:IsA("Model") and v:FindFirstChild("Settings") and v.Settings:FindFirstChild("Fly") and isMine(v) then
				found = v
			end
		end
	end
	return found
end

local function enemyDroneParts()
	local t = {}
	for _, root in ipairs(droneRoots()) do
		for _, v in ipairs(root:GetChildren()) do
			if v:IsA("Model") and v:FindFirstChild("Settings") and v.Settings:FindFirstChild("Fly") and not isMine(v) then
				local ls = v:FindFirstChild("LifeStatus")
				if ls and ls.Value then
					local pp = v.PrimaryPart or (v:FindFirstChild("Parts") and v.Parts:FindFirstChild("PrimaryPart"))
					if pp then table.insert(t, pp) end
				end
			end
		end
	end
	return t
end

local ESP_SCALE = 1.5

-- Highlight goes on the character itself (renders reliably); the 1.5x black box
-- is drawn with a BoxHandleAdornment so it stays visible on an invisible part.
local function ensure(inst)
	if not inst or not inst.Parent then return end
	if inst:FindFirstChild("IYAI_esp") then return end

	local h = Instance.new("Highlight")
	h.Name = "IYAI_esp"
	h.Adornee = inst
	h.FillColor = COL_ESP_FILL
	h.FillTransparency = 0.35
	h.OutlineColor = COL_ESP_OUTLINE
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = inst
	highlights[h] = true

	pcall(function()
		if inst:FindFirstChild("IYAI_esp_box") then return end
		local cf, size = inst:GetBoundingBox()
		if not cf or not size then return end

		local model = Instance.new("Model")
		model.Name = "IYAI_esp_box"

		local part = Instance.new("Part")
		part.Name = "Box"
		part.Size = Vector3.new(
			math.max(size.X, 0.5),
			math.max(size.Y, 0.5),
			math.max(size.Z, 0.5)
		) * ESP_SCALE
		part.CFrame = cf
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true

		local root = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
		if root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = part
			w.Parent = part
		else
			part.Anchored = true
		end

		local box = Instance.new("BoxHandleAdornment")
		box.Name = "IYAI_box"
		box.Adornee = part
		box.Size = part.Size
		box.Color3 = COL_ESP_OUTLINE
		box.Transparency = 0.4
		box.AlwaysOnTop = true
		box.ZIndex = 0
		box.Parent = part

		part.Parent = model
		model.Parent = inst
		boxes[model] = true
	end)
end

local function clearEsp()
	for h in pairs(highlights) do
		if h.Parent then h:Destroy() end
		highlights[h] = nil
	end
	for m in pairs(boxes) do
		if m.Parent then m:Destroy() end
		boxes[m] = nil
	end
end

local function applyBoost(drone)
	local fly = drone:FindFirstChild("Settings") and drone.Settings:FindFirstChild("Fly")
	if not fly then return end
	local ms = fly:FindFirstChild("MaxSpeed")
	local ac = fly:FindFirstChild("Acceleration")
	if not originals[drone] then
		originals[drone] = { max = ms and ms.Value, acc = ac and ac.Value }
	end
	if ms then ms.Value = boostSpeed end
	if ac then ac.Value = math.max(originals[drone].acc or 0.1, 2) end
end

local function restoreBoost()
	for drone, o in pairs(originals) do
		if drone and drone.Parent then
			local fly = drone:FindFirstChild("Settings") and drone.Settings:FindFirstChild("Fly")
			if fly then
				local ms = fly:FindFirstChild("MaxSpeed")
				local ac = fly:FindFirstChild("Acceleration")
				if ms and o.max then ms.Value = o.max end
				if ac and o.acc then ac.Value = o.acc end
			end
		end
	end
	originals = {}
end

local win = GUI.window("UAV Strike", 350, 470)

local items = {}
local function add(item) table.insert(items, item); return item end

add(win:section("ESP"))
add(win:toggle("Player ESP", false, function(on) state.esp = on end))

add(win:separator())
add(win:section("Drone Boost"))
add(win:toggle("Drone Boost", false, function(on)
	state.boost = on
	if not on then restoreBoost() end
end))

local sliderRow = Instance.new("Frame")
sliderRow.Size = UDim2.new(1, 0, 0, 50)
sliderRow.BackgroundColor3 = COL_ROW
sliderRow.BorderSizePixel = 0
sliderRow.Parent = win.content
local rc = Instance.new("UICorner")
rc.CornerRadius = UDim.new(0, 6)
rc.Parent = sliderRow

local sliderLbl = Instance.new("TextLabel")
sliderLbl.Size = UDim2.new(1, -20, 0, 20)
sliderLbl.Position = UDim2.new(0, 10, 0, 6)
sliderLbl.BackgroundTransparency = 1
sliderLbl.Text = "Boost Speed: " .. boostSpeed
sliderLbl.TextColor3 = COL_WHITE
sliderLbl.TextSize = 13
sliderLbl.Font = Enum.Font.Gotham
sliderLbl.TextXAlignment = Enum.TextXAlignment.Left
sliderLbl.Parent = sliderRow

local track = Instance.new("Frame")
track.Size = UDim2.new(1, -20, 0, 4)
track.Position = UDim2.new(0, 10, 0, 36)
track.BackgroundColor3 = COL_TRACK
track.BorderSizePixel = 0
track.Parent = sliderRow
local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0, 2)
tc.Parent = track

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = COL_GREEN
fill.BorderSizePixel = 0
fill.Parent = track
local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(0, 2)
fc.Parent = fill

local knob = Instance.new("Frame")
knob.Size = UDim2.new(0, 12, 0, 12)
knob.Position = UDim2.new(1, -12, 0.5, -6)
knob.BackgroundColor3 = COL_WHITE
knob.BorderSizePixel = 0
knob.Parent = fill
local kc = Instance.new("UICorner")
kc.CornerRadius = UDim.new(1, 0)
kc.Parent = knob

local MIN_SPEED, MAX_SPEED = 100, 3000

local function setFrac(frac)
	frac = math.clamp(frac, 0, 1)
	fill.Size = UDim2.new(frac, 0, 1, 0)
	boostSpeed = math.floor(MIN_SPEED + (MAX_SPEED - MIN_SPEED) * frac + 0.5)
	sliderLbl.Text = "Boost Speed: " .. boostSpeed
end

setFrac((600 - MIN_SPEED) / (MAX_SPEED - MIN_SPEED))


local function setSpeed(v)
	v = math.clamp(math.floor(v + 0.5), MIN_SPEED, MAX_SPEED)
	setFrac((v - MIN_SPEED) / (MAX_SPEED - MIN_SPEED))
	boostSpeed = v
	sliderLbl.Text = "Boost Speed: " .. v
end

local sliding = false
local grab = Instance.new("TextButton")
grab.Size = UDim2.new(1, 0, 1, 0)
grab.BackgroundTransparency = 1
grab.Text = ""
grab.Parent = sliderRow

local function fromMouseX(mx)
	setFrac((mx - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1))
end

grab.MouseButton1Down:Connect(function()
	sliding = true
	fromMouseX(UIS:GetMouseLocation().X)
end)

UIS.InputChanged:Connect(function(input)
	if sliding then
		if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			sliding = false
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			fromMouseX(UIS:GetMouseLocation().X)
		end
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end
end)

add(sliderRow)

add(win:separator())
add(win:section("Hotkeys"))
add(win:label("Q / E - drone speed down / up"))
add(win:label("Right Shift - hide / show window"))

for i, item in ipairs(items) do item.LayoutOrder = i end

-- Right Shift: collapse / expand the window
UIS.InputBegan:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.RightShift then
		if win.gui and win.gui.Parent then
			win.gui.Enabled = not win.gui.Enabled
		end
	end
end)


task.spawn(function()
	while not closed do
		if win.gui.Parent == nil then break end
		if not UIS:GetFocusedTextBox() then
			if UIS:IsKeyDown(Enum.KeyCode.E) then setSpeed(boostSpeed + SPEED_STEP) end
			if UIS:IsKeyDown(Enum.KeyCode.Q) then setSpeed(boostSpeed - SPEED_STEP) end
		end
		task.wait(0.08)
	end
end)

task.spawn(function()
	while not closed do
		if not win.gui.Parent then
			closed = true
			restoreBoost()
			clearEsp()
			break
		end

		local drone = getDrone()

		if state.esp then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= lp and p.Character then ensure(p.Character) end
			end
		else
			clearEsp()
		end

		if state.boost and drone then
			pcall(applyBoost, drone)
		end

		task.wait(0.05)
	end
end)
