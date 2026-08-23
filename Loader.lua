-- Services
local getService = function(service)
    return (cloneref and cloneref(game:GetService(service))) or game:GetService(service)
end

local UserInputService = getService("UserInputService")
local CoreGui = getService("CoreGui")
local Players = getService("Players")

local localPlayer = Players.LocalPlayer

-- Clean previous instances
local guiParent = (gethui and gethui()) or CoreGui or localPlayer:WaitForChild("PlayerGui")
if guiParent:FindFirstChild("AutoTakeLoader") then
    guiParent.AutoTakeLoader:Destroy()
end

-- ScreenGui Setup
local loaderGui = Instance.new("ScreenGui")
loaderGui.Name = "AutoTakeLoader"
loaderGui.ResetOnSpawn = false
loaderGui.Parent = guiParent

-- Main Window Frame
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 150)
frame.Position = UDim2.new(0.5, -110, 0.4, -75)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.BackgroundTransparency = 0.2
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = loaderGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = frame

-- Title Label
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -30, 0, 30)
title.Position = UDim2.new(0, 10, 0, 5)
title.BackgroundTransparency = 1
title.Text = "Auto-Take Loader"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.SourceSansBold
title.Parent = frame

-- Close Button (X)
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -26, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.SourceSansBold
closeBtn.Parent = frame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 4)
closeCorner.Parent = closeBtn

-- Button 1: Standard Run
local runBtn = Instance.new("TextButton")
runBtn.Size = UDim2.new(1, -20, 0, 40)
runBtn.Position = UDim2.new(0, 10, 0, 45)
runBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
runBtn.Text = "Run Script"
runBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
runBtn.TextSize = 14
runBtn.Font = Enum.Font.SourceSansBold
runBtn.Parent = frame

local runCorner = Instance.new("UICorner")
runCorner.CornerRadius = UDim.new(0, 6)
runCorner.Parent = runBtn

-- Button 2: Force Uncached Update Run
runUpdatedBtn = Instance.new("TextButton")
runUpdatedBtn.Size = UDim2.new(1, -20, 0, 40)
runUpdatedBtn.Position = UDim2.new(0, 10, 0, 95)
runUpdatedBtn.BackgroundColor3 = Color3.fromRGB(46, 139, 192)
runUpdatedBtn.Text = "Run Script (Updated)"
runUpdatedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
runUpdatedBtn.TextSize = 14
runUpdatedBtn.Font = Enum.Font.SourceSansBold
runUpdatedBtn.Parent = frame

local updatedCorner = Instance.new("UICorner")
updatedCorner.CornerRadius = UDim.new(0, 6)
updatedCorner.Parent = runUpdatedBtn

-- Draggable UI Setup
local dragging, dragInput, dragStart, startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
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

-- Script Execution Callbacks
local rawUrl = 'https://raw.githubusercontent.com/yusufxbenxs/DontstealtheboboAUTOTAKE/refs/heads/main/Main.lua'

runBtn.MouseButton1Click:Connect(function()
    loaderGui:Destroy()
    loadstring(game:HttpGet(rawUrl))()
end)

runUpdatedBtn.MouseButton1Click:Connect(function()
    loaderGui:Destroy()
    loadstring(game:HttpGet(rawUrl .. '?v=' .. tick()))()
end)

closeBtn.MouseButton1Click:Connect(function()
    loaderGui:Destroy()
end)
