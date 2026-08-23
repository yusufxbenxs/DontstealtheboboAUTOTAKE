-- Services Setup
local getService = function(service)
    return (cloneref and cloneref(game:GetService(service))) or game:GetService(service)
end

local Players = getService("Players")
local Workspace = getService("Workspace")
local UserInputService = getService("UserInputService")
local VirtualInputManager = getService("VirtualInputManager")
local TweenService = getService("TweenService")
local CoreGui = getService("CoreGui")

local localPlayer = Players.LocalPlayer
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Global Configuration States
_G.SelectedPlayer = "Auto"
_G.SelectedPlot = "Plot1"
_G.SelectedLabubu = "Any (Random)"
_G.AutoTakeRunning = false
_G.KeepLabubus = false
_G.SafeMode = true
_G.UsePhysicalInput = true -- TOGGLE: true = Key Press/Touch, false = Proximity Trigger
_G.SellCooldown = 50
_G.TweenSpeed = 350

if _G.AutoTakeThread then
    task.cancel(_G.AutoTakeThread)
    _G.AutoTakeThread = nil
end

local labubuQueue = {}
local baseSlots = {}

-- Helper Functions
local function getHRP()
    local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    return char:FindFirstChild("HumanoidRootPart")
end

local function safeTeleport(targetCFrame)
    local hrp = getHRP()
    if not hrp then return end

    if _G.SafeMode then
        local distance = (hrp.Position - targetCFrame.Position).Magnitude
        if distance < 1 then return end

        local travelTime = math.clamp(distance / _G.TweenSpeed, 0.05, 1.0)
        local tweenInfo = TweenInfo.new(travelTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
        local tween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
        tween:Play()

        local start = tick()
        while tween.PlaybackState == Enum.PlaybackState.Playing and (tick() - start) < (travelTime + 0.2) do
            task.wait()
        end
    else
        hrp.CFrame = targetCFrame
    end
end

-- Core Interaction Engine
local function executeInteraction(prompt, fallbackKeyCode)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    prompt.Enabled = true

    local duration = (prompt.HoldDuration > 0 and prompt.HoldDuration) or 0.15

    if _G.UsePhysicalInput then
        if isMobile then
            local screenCenter = Vector2.new(Workspace.CurrentCamera.ViewportSize.X / 2, Workspace.CurrentCamera.ViewportSize.Y / 2)
            VirtualInputManager:SendTouchEvent(0, 0, screenCenter.X, screenCenter.Y)
            task.wait(duration)
            VirtualInputManager:SendTouchEvent(0, 2, screenCenter.X, screenCenter.Y)
        else
            local key = fallbackKeyCode or Enum.KeyCode.E
            VirtualInputManager:SendKeyEvent(true, key, false, game)
            task.wait(duration)
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end
    else
        task.spawn(function()
            if fireproximityprompt then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.wait(duration)
                prompt:InputHoldEnd()
            end
        end)
    end

    task.wait(0.1)
end

-- Target Engine
local function initializeQueue()
    table.clear(labubuQueue)
    table.clear(baseSlots)

    local npcFolder = Workspace:WaitForChild("Map", 5):WaitForChild("Zones", 5):WaitForChild("Field", 5):WaitForChild("NPC", 5)
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            if _G.SelectedLabubu == "Any (Random)" or npc.Name == _G.SelectedLabubu then
                table.insert(labubuQueue, npc)
            end
        end
    end

    local plotsFolder = Workspace:WaitForChild("Map", 5):WaitForChild("Plots", 5)
    local targetPlot = plotsFolder and (plotsFolder:FindFirstChild(_G.SelectedPlot) or plotsFolder:FindFirstChild("Plot1"))

    if targetPlot and targetPlot:FindFirstChild("Slots") then
        local foundSlots = {}
        for _, slotFolder in ipairs(targetPlot.Slots:GetChildren()) do
            local slotNumber = tonumber(slotFolder.Name)
            if slotNumber and slotNumber >= 1 and slotNumber <= 20 then
                local promptAttachment = slotFolder:FindFirstChild("PromptAttachment")
                local placePrompt = (promptAttachment and promptAttachment:FindFirstChild("SlotPlace")) or slotFolder:FindFirstChild("SlotPlace")
                local sellPrompt = (promptAttachment and promptAttachment:FindFirstChild("SlotSell")) or slotFolder:FindFirstChild("SlotSell")
                local targetPart = promptAttachment or slotFolder:FindFirstChild("Pedestal") or slotFolder:FindFirstChild("Part") or slotFolder

                if targetPart then
                    table.insert(foundSlots, {
                        index = slotNumber,
                        targetPart = targetPart,
                        placePrompt = placePrompt,
                        sellPrompt = sellPrompt
                    })
                end
            end
        end
        table.sort(foundSlots, function(a, b) return a.index < b.index end)
        for _, slotData in ipairs(foundSlots) do table.insert(baseSlots, slotData) end
    end
end

local function interruptibleWait(seconds)
    local elapsed = 0
    while elapsed < seconds and _G.AutoTakeRunning do
        task.wait(0.1)
        elapsed = elapsed + 0.1
    end
    return _G.AutoTakeRunning
end

-- Loop Control
local function startAutoTake()
    if _G.AutoTakeRunning then return end
    _G.AutoTakeRunning = true

    _G.AutoTakeThread = task.spawn(function()
        while _G.AutoTakeRunning do
            initializeQueue()

            if #labubuQueue == 0 or #baseSlots == 0 then
                if not interruptibleWait(2) then break end
                continue
            end

            local slotIndex = 1

            while _G.AutoTakeRunning and #labubuQueue > 0 and slotIndex <= #baseSlots do
                local currentNpc = table.remove(labubuQueue, 1)
                local pickupPrompt = currentNpc:FindFirstChild("Prompts") and currentNpc.Prompts:FindFirstChild("Pickup")

                if currentNpc and pickupPrompt then
                    safeTeleport(currentNpc:GetPivot())
                    if not interruptibleWait(0.1) then break end

                    executeInteraction(pickupPrompt, Enum.KeyCode.E)
                    if not interruptibleWait(0.15) then break end

                    local slotData = baseSlots[slotIndex]
                    if slotData and slotData.targetPart then
                        local targetCF = slotData.targetPart:IsA("Attachment") and slotData.targetPart.WorldCFrame or slotData.targetPart:GetPivot()
                        safeTeleport(targetCF + Vector3.new(0, 2.5, 0))
                        if not interruptibleWait(0.1) then break end

                        if slotData.placePrompt then
                            executeInteraction(slotData.placePrompt, Enum.KeyCode.E)
                        end
                    end

                    slotIndex = slotIndex + 1
                    if not interruptibleWait(0.2) then break end
                end
            end

            if _G.AutoTakeRunning then
                if _G.KeepLabubus then
                    _G.AutoTakeRunning = false
                    break
                else
                    if interruptibleWait(_G.SellCooldown) then
                        for _, slot in ipairs(baseSlots) do
                            if slot.sellPrompt then
                                executeInteraction(slot.sellPrompt, Enum.KeyCode.Q)
                            end
                        end
                        interruptibleWait(1.5)
                    end
                end
            end
        end
    end)
end

local function stopAutoTake()
    _G.AutoTakeRunning = false
    if _G.AutoTakeThread then
        task.cancel(_G.AutoTakeThread)
        _G.AutoTakeThread = nil
    end
end

-- UI Parent Setup
local guiParent = (gethui and gethui()) or CoreGui or localPlayer:WaitForChild("PlayerGui")
if guiParent:FindFirstChild("AutoTakeHubGUI") then
    guiParent.AutoTakeHubGUI:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoTakeHubGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = guiParent

local activeFrame = nil

local function enableDragging(frame)
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
end

-- Reload Function
local function reloadScript()
    stopAutoTake()
    screenGui:Destroy()
    task.wait(0.1)
    -- Re-executes current environment logic
    loadstring(game:HttpGet("https://raw.githubusercontent.com/YourRepo/script.lua"))() -- Optional fallback or local execution reset
end

local function createBaseWindow(title, size, pos)
    local win = Instance.new("Frame")
    win.Size = size
    win.Position = pos
    win.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    win.BackgroundTransparency = 0.25
    win.BorderSizePixel = 0
    win.Active = true
    win.Parent = screenGui

    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 60, 75)
    stroke.Thickness = 1
    stroke.Parent = win

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -60, 0, 30)
    titleLbl.Position = UDim2.new(0, 10, 0, 2)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = title
    titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLbl.TextSize = 13
    titleLbl.Font = Enum.Font.SourceSansBold
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = win

    -- Reload Button (↻)
    local reloadBtn = Instance.new("TextButton")
    reloadBtn.Size = UDim2.new(0, 22, 0, 22)
    reloadBtn.Position = UDim2.new(1, -52, 0, 5)
    reloadBtn.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
    reloadBtn.Text = "↻"
    reloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    reloadBtn.TextSize = 12
    reloadBtn.Font = Enum.Font.SourceSansBold
    reloadBtn.Parent = win
    Instance.new("UICorner", reloadBtn).CornerRadius = UDim.new(0, 4)

    reloadBtn.MouseButton1Click:Connect(function()
        stopAutoTake()
        screenGui:Destroy()
    end)

    -- Close Button (X)
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22)
    closeBtn.Position = UDim2.new(1, -26, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 12
    closeBtn.Font = Enum.Font.SourceSansBold
    closeBtn.Parent = win
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

    enableDragging(win)
    return win, closeBtn, reloadBtn
end

-- 1. Main Hub Window
local hubFrame, hubCloseBtn = createBaseWindow("Auto-Take Hub", UDim2.new(0, 190, 0, 130), UDim2.new(0.02, 0, 0.2, 0))
activeFrame = hubFrame

local btnSettingsWindow = Instance.new("TextButton")
btnSettingsWindow.Size = UDim2.new(1, -20, 0, 32)
btnSettingsWindow.Position = UDim2.new(0, 10, 0, 40)
btnSettingsWindow.BackgroundColor3 = Color3.fromRGB(45, 85, 125)
btnSettingsWindow.BackgroundTransparency = 0.2
btnSettingsWindow.Text = "⚙ Settings Menu"
btnSettingsWindow.TextColor3 = Color3.fromRGB(255, 255, 255)
btnSettingsWindow.TextSize = 13
btnSettingsWindow.Font = Enum.Font.SourceSansBold
btnSettingsWindow.Parent = hubFrame
Instance.new("UICorner", btnSettingsWindow).CornerRadius = UDim.new(0, 6)

local btnControlWindow = Instance.new("TextButton")
btnControlWindow.Size = UDim2.new(1, -20, 0, 32)
btnControlWindow.Position = UDim2.new(0, 10, 0, 80)
btnControlWindow.BackgroundColor3 = Color3.fromRGB(45, 125, 85)
btnControlWindow.BackgroundTransparency = 0.2
btnControlWindow.Text = "▶ Controls Menu"
btnControlWindow.TextColor3 = Color3.fromRGB(255, 255, 255)
btnControlWindow.TextSize = 13
btnControlWindow.Font = Enum.Font.SourceSansBold
btnControlWindow.Parent = hubFrame
Instance.new("UICorner", btnControlWindow).CornerRadius = UDim.new(0, 6)

hubCloseBtn.MouseButton1Click:Connect(function()
    stopAutoTake()
    screenGui:Destroy()
end)

-- 2. Restored Settings Window (All Features Restored)
local settingsFrame, settingsCloseBtn = createBaseWindow("Script Settings", UDim2.new(0, 230, 0, 360), hubFrame.Position)
settingsFrame.Visible = false

local yOffset = 38

-- Player Target Box
local playerBox = Instance.new("TextBox")
playerBox.Size = UDim2.new(1, -20, 0, 26)
playerBox.Position = UDim2.new(0, 10, 0, yOffset)
playerBox.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
playerBox.BackgroundTransparency = 0.2
playerBox.Text = "Target Player: Auto"
playerBox.TextColor3 = Color3.fromRGB(255, 255, 255)
playerBox.TextSize = 11
playerBox.Font = Enum.Font.SourceSans
playerBox.Parent = settingsFrame
Instance.new("UICorner", playerBox).CornerRadius = UDim.new(0, 5)

playerBox.FocusLost:Connect(function()
    if playerBox.Text ~= "" then _G.SelectedPlayer = playerBox.Text end
    playerBox.Text = "Target Player: " .. _G.SelectedPlayer
end)

yOffset = yOffset + 32

-- Input Mode Toggle
local inputModeBtn = Instance.new("TextButton")
inputModeBtn.Size = UDim2.new(1, -20, 0, 26)
inputModeBtn.Position = UDim2.new(0, 10, 0, yOffset)
inputModeBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
inputModeBtn.BackgroundTransparency = 0.2
inputModeBtn.Text = "Input: Physical (Key/Touch)"
inputModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
inputModeBtn.TextSize = 11
inputModeBtn.Font = Enum.Font.SourceSansBold
inputModeBtn.Parent = settingsFrame
Instance.new("UICorner", inputModeBtn).CornerRadius = UDim.new(0, 5)

inputModeBtn.MouseButton1Click:Connect(function()
    _G.UsePhysicalInput = not _G.UsePhysicalInput
    if _G.UsePhysicalInput then
        inputModeBtn.Text = "Input: Physical (Key/Touch)"
        inputModeBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    else
        inputModeBtn.Text = "Input: Virtual Proximity"
        inputModeBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 50)
    end
end)

yOffset = yOffset + 32

-- Plot Selector
local plotBtn = Instance.new("TextButton")
plotBtn.Size = UDim2.new(1, -20, 0, 26)
plotBtn.Position = UDim2.new(0, 10, 0, yOffset)
plotBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
plotBtn.BackgroundTransparency = 0.2
plotBtn.Text = "Plot: " .. _G.SelectedPlot .. " ▼"
plotBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plotBtn.TextSize = 11
plotBtn.Font = Enum.Font.SourceSans
plotBtn.Parent = settingsFrame
Instance.new("UICorner", plotBtn).CornerRadius = UDim.new(0, 5)

local plotList = {"Plot1", "Plot2", "Plot3", "Plot4", "Plot5", "Plot6"}
local currentPlotIdx = 1
plotBtn.MouseButton1Click:Connect(function()
    currentPlotIdx = (currentPlotIdx % #plotList) + 1
    _G.SelectedPlot = plotList[currentPlotIdx]
    plotBtn.Text = "Plot: " .. _G.SelectedPlot .. " ▼"
end)

yOffset = yOffset + 32

-- Labubu Target Dropdown
local labubuBtn = Instance.new("TextButton")
labubuBtn.Size = UDim2.new(1, -20, 0, 26)
labubuBtn.Position = UDim2.new(0, 10, 0, yOffset)
labubuBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
labubuBtn.BackgroundTransparency = 0.2
labubuBtn.Text = "Target: " .. _G.SelectedLabubu .. " ▼"
labubuBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
labubuBtn.TextSize = 11
labubuBtn.Font = Enum.Font.SourceSans
labubuBtn.Parent = settingsFrame
Instance.new("UICorner", labubuBtn).CornerRadius = UDim.new(0, 5)

local labubuList = {"Any (Random)", "Labubu", "Gold Labubu", "Diamond Labubu"}
local currentLabubuIdx = 1
labubuBtn.MouseButton1Click:Connect(function()
    currentLabubuIdx = (currentLabubuIdx % #labubuList) + 1
    _G.SelectedLabubu = labubuList[currentLabubuIdx]
    labubuBtn.Text = "Target: " .. _G.SelectedLabubu .. " ▼"
end)

yOffset = yOffset + 32

-- Safe Mode Toggle
local safeBtn = Instance.new("TextButton")
safeBtn.Size = UDim2.new(1, -20, 0, 26)
safeBtn.Position = UDim2.new(0, 10, 0, yOffset)
safeBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
safeBtn.BackgroundTransparency = 0.2
safeBtn.Text = "Safe Mode: ON"
safeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
safeBtn.TextSize = 11
safeBtn.Font = Enum.Font.SourceSansBold
safeBtn.Parent = settingsFrame
Instance.new("UICorner", safeBtn).CornerRadius = UDim.new(0, 5)

safeBtn.MouseButton1Click:Connect(function()
    _G.SafeMode = not _G.SafeMode
    safeBtn.Text = _G.SafeMode and "Safe Mode: ON" or "Safe Mode: OFF"
    safeBtn.BackgroundColor3 = _G.SafeMode and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(180, 50, 50)
end)

yOffset = yOffset + 32

-- Keep Labubus Toggle
local keepBtn = Instance.new("TextButton")
keepBtn.Size = UDim2.new(1, -20, 0, 26)
keepBtn.Position = UDim2.new(0, 10, 0, yOffset)
keepBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
keepBtn.BackgroundTransparency = 0.2
keepBtn.Text = "Keep Labubus: OFF"
keepBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
keepBtn.TextSize = 11
keepBtn.Font = Enum.Font.SourceSansBold
keepBtn.Parent = settingsFrame
Instance.new("UICorner", keepBtn).CornerRadius = UDim.new(0, 5)

keepBtn.MouseButton1Click:Connect(function()
    _G.KeepLabubus = not _G.KeepLabubus
    keepBtn.Text = _G.KeepLabubus and "Keep Labubus: ON" or "Keep Labubus: OFF"
    keepBtn.BackgroundColor3 = _G.KeepLabubus and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(180, 50, 50)
end)

yOffset = yOffset + 32

-- Tween Speed Box
local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(1, -20, 0, 26)
speedBox.Position = UDim2.new(0, 10, 0, yOffset)
speedBox.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
speedBox.BackgroundTransparency = 0.2
speedBox.Text = "Tween Speed: " .. tostring(_G.TweenSpeed)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.TextSize = 11
speedBox.Font = Enum.Font.SourceSans
speedBox.Parent = settingsFrame
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 5)

speedBox.FocusLost:Connect(function()
    local val = tonumber(speedBox.Text:match("%d+"))
    if val then _G.TweenSpeed = val end
    speedBox.Text = "Tween Speed: " .. tostring(_G.TweenSpeed)
end)

yOffset = yOffset + 32

-- Sell Cooldown Box
local sellBox = Instance.new("TextBox")
sellBox.Size = UDim2.new(1, -20, 0, 26)
sellBox.Position = UDim2.new(0, 10, 0, yOffset)
sellBox.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
sellBox.BackgroundTransparency = 0.2
sellBox.Text = "Sell Delay (s): " .. tostring(_G.SellCooldown)
sellBox.TextColor3 = Color3.fromRGB(255, 255, 255)
sellBox.TextSize = 11
sellBox.Font = Enum.Font.SourceSans
sellBox.Parent = settingsFrame
Instance.new("UICorner", sellBox).CornerRadius = UDim.new(0, 5)

sellBox.FocusLost:Connect(function()
    local val = tonumber(sellBox.Text:match("%d+"))
    if val then _G.SellCooldown = val end
    sellBox.Text = "Sell Delay (s): " .. tostring(_G.SellCooldown)
end)

-- 3. Execution Controls Window
local controlsFrame, controlsCloseBtn = createBaseWindow("Execution Controls", UDim2.new(0, 200, 0, 130), hubFrame.Position)
controlsFrame.Visible = false

local runBtn = Instance.new("TextButton")
runBtn.Size = UDim2.new(1, -20, 0, 32)
runBtn.Position = UDim2.new(0, 10, 0, 40)
runBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
runBtn.BackgroundTransparency = 0.2
runBtn.Text = "▶ Start Auto-Take"
runBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
runBtn.TextSize = 13
runBtn.Font = Enum.Font.SourceSansBold
runBtn.Parent = controlsFrame
Instance.new("UICorner", runBtn).CornerRadius = UDim.new(0, 6)

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1, -20, 0, 32)
stopBtn.Position = UDim2.new(0, 10, 0, 80)
stopBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
stopBtn.BackgroundTransparency = 0.2
stopBtn.Text = "⏹ Stop Auto-Take"
stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stopBtn.TextSize = 13
stopBtn.Font = Enum.Font.SourceSansBold
stopBtn.Parent = controlsFrame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 6)

-- Seamless Transitions
btnSettingsWindow.MouseButton1Click:Connect(function()
    settingsFrame.Position = hubFrame.Position
    hubFrame.Visible = false
    settingsFrame.Visible = true
    activeFrame = settingsFrame
end)

settingsCloseBtn.MouseButton1Click:Connect(function()
    hubFrame.Position = settingsFrame.Position
    settingsFrame.Visible = false
    hubFrame.Visible = true
    activeFrame = hubFrame
end)

btnControlWindow.MouseButton1Click:Connect(function()
    controlsFrame.Position = hubFrame.Position
    hubFrame.Visible = false
    controlsFrame.Visible = true
    activeFrame = controlsFrame
end)

controlsCloseBtn.MouseButton1Click:Connect(function()
    hubFrame.Position = controlsFrame.Position
    controlsFrame.Visible = false
    hubFrame.Visible = true
    activeFrame = hubFrame
end)

-- Minimize Window Keybind (Z Key)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Z then
        if activeFrame then
            activeFrame.Visible = not activeFrame.Visible
        end
    end
end)

runBtn.MouseButton1Click:Connect(startAutoTake)
stopBtn.MouseButton1Click:Connect(stopAutoTake)
