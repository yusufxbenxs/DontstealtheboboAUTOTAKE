-- Service Initialization
local getService = function(service)
    return (cloneref and cloneref(game:GetService(service))) or game:GetService(service)
end

local Players = getService("Players")
local UserInputService = getService("UserInputService")
local CoreGui = getService("CoreGui")

local localPlayer = Players.LocalPlayer

-- GUI Parent Setup
local guiParent = (gethui and gethui()) or CoreGui or localPlayer:WaitForChild("PlayerGui")
if guiParent:FindFirstChild("AutoTakeLoaderGUI") then
    guiParent.AutoTakeLoaderGUI:Destroy()
end

local loaderGui = Instance.new("ScreenGui")
loaderGui.Name = "AutoTakeLoaderGUI"
loaderGui.ResetOnSpawn = false
loaderGui.Parent = guiParent

-- Loader Main Frame
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 250, 0, 180)
frame.Position = UDim2.new(0.5, -125, 0.4, -90)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = loaderGui

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 75)
stroke.Thickness = 1
stroke.Parent = frame

-- Title Label
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 30)
title.Position = UDim2.new(0, 10, 0, 5)
title.BackgroundTransparency = 1
title.Text = "Auto-Take Loader"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 13
title.Font = Enum.Font.SourceSansBold
title.Parent = frame

-- Script URLs Mapping
local scriptUrls = {
    ["English"] = "https://raw.githubusercontent.com/yusufxbenxs/DontstealtheboboAUTOTAKE/refs/heads/main/Main.lua",
    ["Türkçe (Turkish)"] = "https://raw.githubusercontent.com/yusufxbenxs/DontstealtheboboAUTOTAKE/refs/heads/main/MainTR.lua"
}

local selectedLanguage = "English"
local langList = {"English", "Türkçe (Turkish)"}
local currentLangIndex = 1

-- Language Dropdown Button
local dropdownBtn = Instance.new("TextButton")
dropdownBtn.Size = UDim2.new(1, -20, 0, 30)
dropdownBtn.Position = UDim2.new(0, 10, 0, 40)
dropdownBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
dropdownBtn.BackgroundTransparency = 0.2
dropdownBtn.Text = "Language: " .. selectedLanguage .. " ▼"
dropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dropdownBtn.TextSize = 12
dropdownBtn.Font = Enum.Font.SourceSans
dropdownBtn.Parent = frame
Instance.new("UICorner", dropdownBtn).CornerRadius = UDim.new(0, 5)

dropdownBtn.MouseButton1Click:Connect(function()
    currentLangIndex = (currentLangIndex % #langList) + 1
    selectedLanguage = langList[currentLangIndex]
    dropdownBtn.Text = "Language: " .. selectedLanguage .. " ▼"
end)

-- Execution Handler Function
local function runScript(useCache)
    local baseUrl = scriptUrls[selectedLanguage]
    if not baseUrl then return end

    -- Append timestamp parameter to bypass Roblox HttpGet caching for "Updated"
    local targetUrl = useCache and baseUrl or (baseUrl .. "?t=" .. tostring(tick()))

    task.spawn(function()
        local success, err = pcall(function()
            loadstring(game:HttpGet(targetUrl))()
        end)

        if not success then
            warn("Failed to load script: " .. tostring(err))
        else
            loaderGui:Destroy()
        end
    end)
end

-- Load (Cache) Button
local loadCacheBtn = Instance.new("TextButton")
loadCacheBtn.Size = UDim2.new(1, -20, 0, 32)
loadCacheBtn.Position = UDim2.new(0, 10, 0, 85)
loadCacheBtn.BackgroundColor3 = Color3.fromRGB(45, 85, 125)
loadCacheBtn.BackgroundTransparency = 0.2
loadCacheBtn.Text = "⚡ Load (Cache)"
loadCacheBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
loadCacheBtn.TextSize = 12
loadCacheBtn.Font = Enum.Font.SourceSansBold
loadCacheBtn.Parent = frame
Instance.new("UICorner", loadCacheBtn).CornerRadius = UDim.new(0, 5)

loadCacheBtn.MouseButton1Click:Connect(function()
    loadCacheBtn.Text = "Loading..."
    runScript(true)
end)

-- Load (Updated) Button
local loadUpdatedBtn = Instance.new("TextButton")
loadUpdatedBtn.Size = UDim2.new(1, -20, 0, 32)
loadUpdatedBtn.Position = UDim2.new(0, 10, 0, 128)
loadUpdatedBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
loadUpdatedBtn.BackgroundTransparency = 0.2
loadUpdatedBtn.Text = "🔄 Load (Updated)"
loadUpdatedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
loadUpdatedBtn.TextSize = 12
loadUpdatedBtn.Font = Enum.Font.SourceSansBold
loadUpdatedBtn.Parent = frame
Instance.new("UICorner", loadUpdatedBtn).CornerRadius = UDim.new(0, 5)

loadUpdatedBtn.MouseButton1Click:Connect(function()
    loadUpdatedBtn.Text = "Fetching Latest..."
    runScript(false)
end)

-- Draggable Logic
local dragging, dragInput, dragStart, startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
