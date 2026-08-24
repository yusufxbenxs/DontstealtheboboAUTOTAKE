-- GameBuddy Cross-Platform Loader (PC & Mobile Safe)
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui", 5) or localPlayer:FindFirstChildOfClass("PlayerGui")

-- Safe UI Parent Strategy
local targetParent = CoreGui
local successCore = pcall(function()
    local test = Instance.new("Folder")
    test.Parent = CoreGui
    test:Destroy()
end)
if not successCore and playerGui then
    targetParent = playerGui
end

if targetParent:FindFirstChild("GameBuddyLoader") then 
    targetParent.GameBuddyLoader:Destroy() 
end

local sg = Instance.new("ScreenGui")
sg.Name = "GameBuddyLoader"
sg.ResetOnSpawn = false
sg.DisplayOrder = 999999
sg.Parent = targetParent

local window = Instance.new("Frame")
window.Size = UDim2.new(0, 340, 0, 200)
window.Position = UDim2.new(0.5, -170, 0.5, -100)
window.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
window.BorderSizePixel = 0
window.Active = true
window.Draggable = true
window.Parent = sg

local winCorner = Instance.new("UICorner")
winCorner.CornerRadius = UDim.new(0, 10)
winCorner.Parent = window

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 38)
header.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
header.BorderSizePixel = 0
header.Parent = window

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "GameBuddy - Select Platform"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

-- PC Button
local pcBtn = Instance.new("TextButton")
pcBtn.Size = UDim2.new(1, -30, 0, 45)
pcBtn.Position = UDim2.new(0, 15, 0, 55)
pcBtn.BackgroundColor3 = Color3.fromRGB(41, 128, 185)
pcBtn.Text = "Load PC Version"
pcBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
pcBtn.Font = Enum.Font.GothamBold
pcBtn.TextSize = 13
pcBtn.Parent = window

local pcCorner = Instance.new("UICorner")
pcCorner.CornerRadius = UDim.new(0, 6)
pcCorner.Parent = pcBtn

-- Mobile Button
local mobileBtn = Instance.new("TextButton")
mobileBtn.Size = UDim2.new(1, -30, 0, 45)
mobileBtn.Position = UDim2.new(0, 15, 0, 115)
mobileBtn.BackgroundColor3 = Color3.fromRGB(39, 174, 96)
mobileBtn.Text = "Load Mobile Version"
mobileBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
mobileBtn.Font = Enum.Font.GothamBold
mobileBtn.TextSize = 13
mobileBtn.Parent = window

local mobileCorner = Instance.new("UICorner")
mobileCorner.CornerRadius = UDim.new(0, 6)
mobileCorner.Parent = mobileBtn

-- Robust execution wrapper function
local function safeExecute(url)
    sg:Destroy()
    task.spawn(function()
        local success, result = pcall(function()
            local source = game:HttpGet(url)
            local fn, err = loadstring(source)
            if fn then
                fn()
            else
                warn("GameBuddy Loadstring Compile Error: ", err)
            end
        end)
        if not success then
            warn("GameBuddy HTTP/Execution Error: ", result)
        end
    end)
end

-- Button Connections
pcBtn.MouseButton1Click:Connect(function()
    safeExecute('https://raw.githubusercontent.com/yusufxbenxs/Gamebuddy/refs/heads/main/mainPC.lua')
end)

mobileBtn.MouseButton1Click:Connect(function()
    safeExecute('https://raw.githubusercontent.com/yusufxbenxs/Gamebuddy/refs/heads/main/mainMobile.lua')
end)
