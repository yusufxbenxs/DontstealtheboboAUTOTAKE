-- Servisler
local getService = function(service)
    return (cloneref and cloneref(game:GetService(service))) or game:GetService(service)
end

local Players = getService("Players")
local Workspace = getService("Workspace")
local VirtualInputManager = getService("VirtualInputManager")
local UserInputService = getService("UserInputService")
local CoreGui = getService("CoreGui")

local localPlayer = Players.LocalPlayer
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Genel Ayarlar
_G.AutoTakeRunning = false
_G.SelectedPlot = "Plot1"
_G.SelectedLabubu = "Hepsi (Rastgele)"
_G.KeepLabubus = false
_G.SellCooldown = 50

if _G.AutoTakeThread then
    task.cancel(_G.AutoTakeThread)
    _G.AutoTakeThread = nil
end

-- Yardımcı Fonksiyonlar
local function getHRP()
    local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    return char:FindFirstChild("HumanoidRootPart")
end

local function tpToTarget(cframeOffset)
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = cframeOffset
    end
end

local function sendPhysicalInput(holdDuration, keyCode)
    local duration = holdDuration or 0.3
    if isMobile then
        local screenCenter = Vector2.new(Workspace.CurrentCamera.ViewportSize.X / 2, Workspace.CurrentCamera.ViewportSize.Y / 2)
        VirtualInputManager:SendTouchEvent(0, 0, screenCenter.X, screenCenter.Y)
        task.wait(duration)
        VirtualInputManager:SendTouchEvent(0, 2, screenCenter.X, screenCenter.Y)
    else
        local key = keyCode or Enum.KeyCode.E
        VirtualInputManager:SendKeyEvent(true, key, false, game)
        task.wait(duration)
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    end
end

-- Ana Oto Toplama Motoru
local function runPhysicalAutoTake()
    if _G.AutoTakeRunning then return end
    _G.AutoTakeRunning = true

    _G.AutoTakeThread = task.spawn(function()
        while _G.AutoTakeRunning do
            local npcFolder = Workspace:FindFirstChild("Map") and Workspace.Map.Zones.Field.NPC
            local plot = Workspace:FindFirstChild("Map") and Workspace.Map.Plots:FindFirstChild(_G.SelectedPlot)

            if npcFolder and plot and plot:FindFirstChild("Slots") then
                local rawNpcs = npcFolder:GetChildren()
                local npcs = {}

                for _, npc in ipairs(rawNpcs) do
                    if _G.SelectedLabubu == "Hepsi (Rastgele)" or npc.Name == _G.SelectedLabubu then
                        table.insert(npcs, npc)
                    end
                end

                local slots = plot.Slots:GetChildren()

                for i = 1, math.min(#npcs, #slots) do
                    if not _G.AutoTakeRunning then break end

                    local npc = npcs[i]
                    local slot = slots[i]

                    -- 1. NPC'yi Al
                    if npc then
                        tpToTarget(npc:GetPivot())
                        task.wait(0.15)

                        local prompt = npc:FindFirstChildWhichIsA("ProximityPrompt", true)
                        local holdTime = (prompt and prompt.HoldDuration > 0) and prompt.HoldDuration or 0.2

                        sendPhysicalInput(holdTime + 0.1, Enum.KeyCode.E)
                        task.wait(0.2)
                    end

                    -- 2. Alana Yerleştir
                    if slot then
                        local targetPart = slot:FindFirstChild("PromptAttachment") or slot:FindFirstChild("Pedestal") or slot
                        local slotCF = targetPart:IsA("Attachment") and targetPart.WorldCFrame or targetPart:GetPivot()

                        tpToTarget(slotCF + Vector3.new(0, 2.5, 0))
                        task.wait(0.15)

                        local slotPrompt = slot:FindFirstChildWhichIsA("ProximityPrompt", true)
                        local holdTime = (slotPrompt and slotPrompt.HoldDuration > 0) and slotPrompt.HoldDuration or 0.2

                        sendPhysicalInput(holdTime + 0.1, Enum.KeyCode.E)
                        task.wait(0.25)
                    end
                end

                -- Otomatik Satış Mantığı
                if _G.AutoTakeRunning then
                    if _G.KeepLabubus then
                        _G.AutoTakeRunning = false
                        break
                    else
                        local elapsed = 0
                        while elapsed < _G.SellCooldown and _G.AutoTakeRunning do
                            task.wait(0.5)
                            elapsed = elapsed + 0.5
                        end

                        if _G.AutoTakeRunning then
                            for _, slot in ipairs(slots) do
                                local targetPart = slot:FindFirstChild("PromptAttachment") or slot:FindFirstChild("Pedestal") or slot
                                local slotCF = targetPart:IsA("Attachment") and targetPart.WorldCFrame or targetPart:GetPivot()

                                tpToTarget(slotCF + Vector3.new(0, 2.5, 0))
                                task.wait(0.1)

                                sendPhysicalInput(0.2, Enum.KeyCode.Q)
                                task.wait(0.15)
                            end
                        end
                    end
                end
            end
            task.wait(1)
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

-- Arayüz Kurulumu
local guiParent = (gethui and gethui()) or CoreGui or localPlayer:WaitForChild("PlayerGui")
if guiParent:FindFirstChild("AutoTakeHubGUI") then
    guiParent.AutoTakeHubGUI:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoTakeHubGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = guiParent

local activeFrame = nil
local miniZBtn = nil

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

-- Taşınabilir Z Butonu
local function createMiniZButton()
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 38, 0, 38)
    btn.Position = UDim2.new(0.02, 0, 0.4, 0)
    btn.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    btn.BackgroundTransparency = 0.2
    btn.Text = "Z"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 18
    btn.Font = Enum.Font.SourceSansBold
    btn.Visible = false
    btn.Active = true
    btn.Parent = screenGui

    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(80, 80, 110)
    stroke.Thickness = 1.5
    stroke.Parent = btn

    local dragging = false
    local dragStart, startPos
    local totalMoveDistance = 0

    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = btn.Position
            totalMoveDistance = 0
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            totalMoveDistance = delta.Magnitude
            btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                if totalMoveDistance < 6 then
                    if activeFrame then
                        activeFrame.Visible = true
                        btn.Visible = false
                    end
                end
            end
        end
    end)

    return btn
end

miniZBtn = createMiniZButton()

local function toggleUI()
    if activeFrame then
        activeFrame.Visible = not activeFrame.Visible
        miniZBtn.Visible = not activeFrame.Visible
    end
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

    -- Küçültme Butonu (_)
    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 22, 0, 22)
    minBtn.Position = UDim2.new(1, -52, 0, 5)
    minBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
    minBtn.Text = "_"
    minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minBtn.TextSize = 12
    minBtn.Font = Enum.Font.SourceSansBold
    minBtn.Parent = win
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

    minBtn.MouseButton1Click:Connect(toggleUI)

    -- Kapatma Butonu (X)
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
    return win, closeBtn
end

-- Hub Pencereleri
local hubFrame, hubCloseBtn = createBaseWindow("Oto-Toplama Hub", UDim2.new(0, 190, 0, 130), UDim2.new(0.02, 0, 0.2, 0))
activeFrame = hubFrame

local btnSettingsWindow = Instance.new("TextButton")
btnSettingsWindow.Size = UDim2.new(1, -20, 0, 32)
btnSettingsWindow.Position = UDim2.new(0, 10, 0, 40)
btnSettingsWindow.BackgroundColor3 = Color3.fromRGB(45, 85, 125)
btnSettingsWindow.BackgroundTransparency = 0.2
btnSettingsWindow.Text = "⚙ Ayarlar Menüsü"
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
btnControlWindow.Text = "▶ Kontrol Menüsü"
btnControlWindow.TextColor3 = Color3.fromRGB(255, 255, 255)
btnControlWindow.TextSize = 13
btnControlWindow.Font = Enum.Font.SourceSansBold
btnControlWindow.Parent = hubFrame
Instance.new("UICorner", btnControlWindow).CornerRadius = UDim.new(0, 6)

hubCloseBtn.MouseButton1Click:Connect(function()
    stopAutoTake()
    screenGui:Destroy()
end)

-- Ayarlar Menüsü
local settingsFrame, settingsCloseBtn = createBaseWindow("Betik Ayarları", UDim2.new(0, 220, 0, 220), hubFrame.Position)
settingsFrame.Visible = false

local yOffset = 38

local plotBtn = Instance.new("TextButton")
plotBtn.Size = UDim2.new(1, -20, 0, 28)
plotBtn.Position = UDim2.new(0, 10, 0, yOffset)
plotBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
plotBtn.BackgroundTransparency = 0.2
plotBtn.Text = "Alan: " .. _G.SelectedPlot .. " ▼"
plotBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plotBtn.TextSize = 12
plotBtn.Font = Enum.Font.SourceSans
plotBtn.Parent = settingsFrame
Instance.new("UICorner", plotBtn).CornerRadius = UDim.new(0, 5)

local plotList = {"Plot1", "Plot2", "Plot3", "Plot4", "Plot5", "Plot6"}
local currentPlotIdx = 1
plotBtn.MouseButton1Click:Connect(function()
    currentPlotIdx = (currentPlotIdx % #plotList) + 1
    _G.SelectedPlot = plotList[currentPlotIdx]
    plotBtn.Text = "Alan: " .. _G.SelectedPlot .. " ▼"
end)

yOffset = yOffset + 34

local labubuBtn = Instance.new("TextButton")
labubuBtn.Size = UDim2.new(1, -20, 0, 28)
labubuBtn.Position = UDim2.new(0, 10, 0, yOffset)
labubuBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
labubuBtn.BackgroundTransparency = 0.2
labubuBtn.Text = "Hedef: " .. _G.SelectedLabubu .. " ▼"
labubuBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
labubuBtn.TextSize = 12
labubuBtn.Font = Enum.Font.SourceSans
labubuBtn.Parent = settingsFrame
Instance.new("UICorner", labubuBtn).CornerRadius = UDim.new(0, 5)

local labubuList = {"Hepsi (Rastgele)", "Labubu", "Gold Labubu", "Diamond Labubu"}
local currentLabubuIdx = 1
labubuBtn.MouseButton1Click:Connect(function()
    currentLabubuIdx = (currentLabubuIdx % #labubuList) + 1
    _G.SelectedLabubu = labubuList[currentLabubuIdx]
    labubuBtn.Text = "Hedef: " .. _G.SelectedLabubu .. " ▼"
end)

yOffset = yOffset + 34

local keepBtn = Instance.new("TextButton")
keepBtn.Size = UDim2.new(1, -20, 0, 28)
keepBtn.Position = UDim2.new(0, 10, 0, yOffset)
keepBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
keepBtn.BackgroundTransparency = 0.2
keepBtn.Text = "Labubuları Tut: KAPALI"
keepBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
keepBtn.TextSize = 12
keepBtn.Font = Enum.Font.SourceSansBold
keepBtn.Parent = settingsFrame
Instance.new("UICorner", keepBtn).CornerRadius = UDim.new(0, 5)

keepBtn.MouseButton1Click:Connect(function()
    _G.KeepLabubus = not _G.KeepLabubus
    keepBtn.Text = _G.KeepLabubus and "Labubuları Tut: AÇIK" or "Labubuları Tut: KAPALI"
    keepBtn.BackgroundColor3 = _G.KeepLabubus and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(180, 50, 50)
end)

yOffset = yOffset + 34

local sellBox = Instance.new("TextBox")
sellBox.Size = UDim2.new(1, -20, 0, 28)
sellBox.Position = UDim2.new(0, 10, 0, yOffset)
sellBox.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
sellBox.BackgroundTransparency = 0.2
sellBox.Text = "Satış Gecikmesi (s): " .. tostring(_G.SellCooldown)
sellBox.TextColor3 = Color3.fromRGB(255, 255, 255)
sellBox.TextSize = 12
sellBox.Font = Enum.Font.SourceSans
sellBox.Parent = settingsFrame
Instance.new("UICorner", sellBox).CornerRadius = UDim.new(0, 5)

sellBox.FocusLost:Connect(function()
    local val = tonumber(sellBox.Text:match("%d+"))
    if val then _G.SellCooldown = val end
    sellBox.Text = "Satış Gecikmesi (s): " .. tostring(_G.SellCooldown)
end)

-- Kontrol Menüsü
local controlsFrame, controlsCloseBtn = createBaseWindow("Çalıştırma Kontrolleri", UDim2.new(0, 200, 0, 130), hubFrame.Position)
controlsFrame.Visible = false

local runBtn = Instance.new("TextButton")
runBtn.Size = UDim2.new(1, -20, 0, 32)
runBtn.Position = UDim2.new(0, 10, 0, 40)
runBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
runBtn.BackgroundTransparency = 0.2
runBtn.Text = "▶ Başlat"
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
stopBtn.Text = "⏹ Durdur"
stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stopBtn.TextSize = 13
stopBtn.Font = Enum.Font.SourceSansBold
stopBtn.Parent = controlsFrame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 6)

-- Gezinme Mantığı
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Z then
        toggleUI()
    end
end)

runBtn.MouseButton1Click:Connect(runPhysicalAutoTake)
stopBtn.MouseButton1Click:Connect(stopAutoTake)
