-- Settings & Services Setup
local getService = function(service)
    return (cloneref and cloneref(game:GetService(service))) or game:GetService(service)
end

local Players = getService("Players")
local Workspace = getService("Workspace")
local UserInputService = getService("UserInputService")
local VirtualInputManager = getService("VirtualInputManager")
local CoreGui = getService("CoreGui")

local localPlayer = Players.LocalPlayer

-- Global States
_G.SelectedPlayer = "Auto"
_G.SelectedPlot = "Plot1"
_G.AutoTakeRunning = false
_G.KeepLabubus = false
_G.SellCooldown = 50

if _G.AutoTakeThread then
    task.cancel(_G.AutoTakeThread)
    _G.AutoTakeThread = nil
end

local labubuQueue = {}
local baseSlots = {}

-- Resolve actual Player Instance based on selection
local function getTargetPlayer()
    if _G.SelectedPlayer == "Auto" then
        return localPlayer
    else
        for _, plr in ipairs(Players:GetPlayers()) do
            local fullName = plr.DisplayName .. " (@" .. plr.Name .. ")"
            if fullName == _G.SelectedPlayer or plr.Name == _G.SelectedPlayer then
                return plr
            end
        end
    end
    return localPlayer
end

-- Teleport Target Player safely
local function safeTeleport(cframe)
    local targetPlr = getTargetPlayer()
    if targetPlr and targetPlr.Character and targetPlr.Character:FindFirstChild("HumanoidRootPart") then
        targetPlr.Character.HumanoidRootPart.CFrame = cframe
    end
end

-- Proximity Prompt Executor
local function executePromptFully(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    
    prompt.Enabled = true
    
    local parentPart = prompt.Parent
    if parentPart then
        local cf = parentPart:IsA("BasePart") and parentPart.CFrame or (parentPart:IsA("Attachment") and parentPart.WorldCFrame)
        if cf then
            safeTeleport(cf)
        end
    end
    task.wait(0.15)

    local duration = (prompt.HoldDuration > 0 and prompt.HoldDuration) or 0.1

    if fireproximityprompt then
        fireproximityprompt(prompt)
        task.wait(duration + 0.15)
    else
        prompt:InputHoldBegin()
        task.wait(duration + 0.15)
        prompt:InputHoldEnd()
    end
end

-- Get Selected Target Plot Folder
local function getTargetPlotFolder()
    local plotsFolder = Workspace:WaitForChild("Map", 5):WaitForChild("Plots", 5)
    if not plotsFolder then return nil end
    return plotsFolder:FindFirstChild(_G.SelectedPlot) or plotsFolder:FindFirstChild("Plot1")
end

-- Initialize Queue & Target Base Slots
local function initializeQueue()
    table.clear(labubuQueue)
    table.clear(baseSlots)

    local npcFolder = Workspace:WaitForChild("Map", 5):WaitForChild("Zones", 5):WaitForChild("Field", 5):WaitForChild("NPC", 5)
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            table.insert(labubuQueue, npc)
        end
    end

    local targetPlot = getTargetPlotFolder()
    if targetPlot and targetPlot:FindFirstChild("Slots") then
        local foundSlots = {}

        for _, slotFolder in ipairs(targetPlot.Slots:GetChildren()) do
            local slotNumber = tonumber(slotFolder.Name)
            if slotNumber then
                local promptAttachment = slotFolder:FindFirstChild("PromptAttachment")
                local placePrompt = promptAttachment and promptAttachment:FindFirstChild("SlotPlace")
                local sellPrompt = promptAttachment and promptAttachment:FindFirstChild("SlotSell")

                local targetPart = slotFolder:FindFirstChild("Pedestal") and slotFolder.Pedestal:FindFirstChild("Top") or promptAttachment

                if targetPart then
                    table.insert(foundSlots, {
                        index = slotNumber,
                        part = targetPart,
                        placePrompt = placePrompt,
                        sellPrompt = sellPrompt
                    })
                end
            end
        end

        table.sort(foundSlots, function(a, b) return a.index < b.index end)

        for _, slotData in ipairs(foundSlots) do
            table.insert(baseSlots, slotData)
        end
    end
end

-- Interruptible Wait Helper
local function interruptibleWait(seconds)
    local elapsed = 0
    while elapsed < seconds and _G.AutoTakeRunning do
        task.wait(0.1)
        elapsed = elapsed + 0.1
    end
    return _G.AutoTakeRunning
end

-- Auto-Take Core Engine Loop
local function startAutoTake()
    if _G.AutoTakeRunning then return end
    _G.AutoTakeRunning = true

    _G.AutoTakeThread = task.spawn(function()
        while _G.AutoTakeRunning do
            initializeQueue()

            if #labubuQueue == 0 or #baseSlots == 0 then
                warn("[Auto-Take] Waiting for NPCs or slots...")
                if not interruptibleWait(3) then break end
                continue
            end

            local slotIndex = 1

            while _G.AutoTakeRunning and #labubuQueue > 0 and slotIndex <= #baseSlots do
                local currentNpc = table.remove(labubuQueue, 1)
                local pickupPrompt = currentNpc:FindFirstChild("Prompts") and currentNpc.Prompts:FindFirstChild("Pickup")

                if currentNpc and pickupPrompt then
                    safeTeleport(currentNpc:GetPivot())
                    if not interruptibleWait(0.2) then break end

                    executePromptFully(pickupPrompt)
                    if not interruptibleWait(0.3) then break end

                    local slotData = baseSlots[slotIndex]
                    if slotData and slotData.part then
                        safeTeleport(slotData.part.CFrame + Vector3.new(0, 2, 0))
                        if not interruptibleWait(0.3) then break end

                        if slotData.placePrompt then
                            executePromptFully(slotData.placePrompt)
                        end
                    end

                    slotIndex = slotIndex + 1
                    if not interruptibleWait(0.4) then break end
                end
            end

            if _G.AutoTakeRunning then
                if _G.KeepLabubus then
                    print("[Auto-Take] Base full! 'Keep Labubus' enabled. Stopping loop.")
                    _G.AutoTakeRunning = false
                    break
                else
                    print("[Auto-Take] Base full! Waiting " .. tostring(_G.SellCooldown) .. "s to sell...")
                    if interruptibleWait(_G.SellCooldown) then
                        print("[Auto-Take] Firing SlotSell prompts...")
                        for _, slot in ipairs(baseSlots) do
                            if slot.sellPrompt then
                                executePromptFully(slot.sellPrompt)
                            end
                        end
                        interruptibleWait(2)
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
        print("[Auto-Take] Loop stopped.")
    end
end

-- Interface Setup
local guiParent = (gethui and gethui()) or CoreGui or localPlayer:WaitForChild("PlayerGui")
if guiParent:FindFirstChild("AutoTakeGUI") then
    guiParent.AutoTakeGUI:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoTakeGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = guiParent

-- Floating Minimize Button ("Z")
local miniBtn = Instance.new("TextButton")
miniBtn.Size = UDim2.new(0, 45, 0, 45)
miniBtn.Position = UDim2.new(0.05, 0, 0.2, 0)
miniBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
miniBtn.Text = "Z"
miniBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
miniBtn.TextSize = 22
miniBtn.Font = Enum.Font.SourceSansBold
miniBtn.Visible = false
miniBtn.Active = true
miniBtn.Parent = screenGui

local miniCorner = Instance.new("UICorner")
miniCorner.CornerRadius = UDim.new(0, 10)
miniCorner.Parent = miniBtn

-- Main Draggable Window Frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 230, 0, 295)
mainFrame.Position = UDim2.new(0.02, 0, 0.1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BackgroundTransparency = 0.2
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

-- Header Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -86, 0, 30)
titleLabel.Position = UDim2.new(0, 10, 0, 5)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Labubu Auto-Take"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.Parent = mainFrame

-- Reload Button (↻)
local reloadButton = Instance.new("TextButton")
reloadButton.Size = UDim2.new(0, 22, 0, 22)
reloadButton.Position = UDim2.new(1, -78, 0, 5)
reloadButton.BackgroundColor3 = Color3.fromRGB(46, 139, 192)
reloadButton.Text = "↻"
reloadButton.TextColor3 = Color3.fromRGB(255, 255, 255)
reloadButton.TextSize = 16
reloadButton.Font = Enum.Font.SourceSansBold
reloadButton.Parent = mainFrame

local reloadCorner = Instance.new("UICorner")
reloadCorner.CornerRadius = UDim.new(0, 4)
reloadCorner.Parent = reloadButton

-- Minimize Button (-)
local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.new(0, 22, 0, 22)
minimizeButton.Position = UDim2.new(1, -52, 0, 5)
minimizeButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
minimizeButton.Text = "-"
minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeButton.TextSize = 16
minimizeButton.Font = Enum.Font.SourceSansBold
minimizeButton.Parent = mainFrame

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 4)
minCorner.Parent = minimizeButton

-- Close Button (X)
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 22, 0, 22)
closeButton.Position = UDim2.new(1, -26, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 14
closeButton.Font = Enum.Font.SourceSansBold
closeButton.Parent = mainFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 4)
closeCorner.Parent = closeButton

-- 1. Target Player Dropdown
local plrDropBtn = Instance.new("TextButton")
plrDropBtn.Size = UDim2.new(1, -20, 0, 26)
plrDropBtn.Position = UDim2.new(0, 10, 0, 36)
plrDropBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
plrDropBtn.Text = "Player: Auto ▼"
plrDropBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plrDropBtn.TextSize = 13
plrDropBtn.Font = Enum.Font.SourceSans
plrDropBtn.Parent = mainFrame

local plrDropCorner = Instance.new("UICorner")
plrDropCorner.CornerRadius = UDim.new(0, 6)
plrDropCorner.Parent = plrDropBtn

local plrDropFrame = Instance.new("ScrollingFrame")
plrDropFrame.Size = UDim2.new(1, -20, 0, 120)
plrDropFrame.Position = UDim2.new(0, 10, 0, 64)
plrDropFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
plrDropFrame.Visible = false
plrDropFrame.ZIndex = 15
plrDropFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
plrDropFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
plrDropFrame.Parent = mainFrame

local plrListLayout = Instance.new("UIListLayout")
plrListLayout.Parent = plrDropFrame

local function populatePlayerDropdown()
    for _, child in ipairs(plrDropFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    local playerList = {"Auto"}
    local activePlayers = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        table.insert(activePlayers, plr.DisplayName .. " (@" .. plr.Name .. ")")
    end
    table.sort(activePlayers)
    for _, name in ipairs(activePlayers) do table.insert(playerList, name) end

    for _, plrName in ipairs(playerList) do
        local optionBtn = Instance.new("TextButton")
        optionBtn.Size = UDim2.new(1, 0, 0, 24)
        optionBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        optionBtn.Text = plrName
        optionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        optionBtn.TextSize = 12
        optionBtn.Font = Enum.Font.SourceSans
        optionBtn.ZIndex = 16
        optionBtn.Parent = plrDropFrame

        optionBtn.MouseButton1Click:Connect(function()
            _G.SelectedPlayer = plrName
            plrDropBtn.Text = "Player: " .. plrName .. " ▼"
            plrDropFrame.Visible = false
        end)
    end
end

plrDropBtn.MouseButton1Click:Connect(function()
    if not plrDropFrame.Visible then populatePlayerDropdown() end
    plrDropFrame.Visible = not plrDropFrame.Visible
end)

-- 2. Target Plot Dropdown
local plotDropBtn = Instance.new("TextButton")
plotDropBtn.Size = UDim2.new(1, -20, 0, 26)
plotDropBtn.Position = UDim2.new(0, 10, 0, 68)
plotDropBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
plotDropBtn.Text = "Plot: Plot1 ▼"
plotDropBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plotDropBtn.TextSize = 13
plotDropBtn.Font = Enum.Font.SourceSans
plotDropBtn.Parent = mainFrame

local plotDropCorner = Instance.new("UICorner")
plotDropCorner.CornerRadius = UDim.new(0, 6)
plotDropCorner.Parent = plotDropBtn

local plotDropFrame = Instance.new("ScrollingFrame")
plotDropFrame.Size = UDim2.new(1, -20, 0, 120)
plotDropFrame.Position = UDim2.new(0, 10, 0, 96)
plotDropFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
plotDropFrame.Visible = false
plotDropFrame.ZIndex = 10
plotDropFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
plotDropFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
plotDropFrame.Parent = mainFrame

local plotListLayout = Instance.new("UIListLayout")
plotListLayout.Parent = plotDropFrame

for i = 1, 5 do
    local plotName = "Plot" .. i
    local optionBtn = Instance.new("TextButton")
    optionBtn.Size = UDim2.new(1, 0, 0, 24)
    optionBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    optionBtn.Text = plotName
    optionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    optionBtn.TextSize = 12
    optionBtn.Font = Enum.Font.SourceSans
    optionBtn.ZIndex = 11
    optionBtn.Parent = plotDropFrame

    optionBtn.MouseButton1Click:Connect(function()
        _G.SelectedPlot = plotName
        plotDropBtn.Text = "Plot: " .. plotName .. " ▼"
        plotDropFrame.Visible = false
    end)
end

plotDropBtn.MouseButton1Click:Connect(function()
    plotDropFrame.Visible = not plotDropFrame.Visible
end)

-- Sell Cooldown Textbox Input
local cdLabel = Instance.new("TextLabel")
cdLabel.Size = UDim2.new(0, 110, 0, 26)
cdLabel.Position = UDim2.new(0, 10, 0, 102)
cdLabel.BackgroundTransparency = 1
cdLabel.Text = "Sell Wait (Sec):"
cdLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
cdLabel.TextSize = 13
cdLabel.Font = Enum.Font.SourceSans
cdLabel.Parent = mainFrame

local cdBox = Instance.new("TextBox")
cdBox.Size = UDim2.new(0, 85, 0, 26)
cdBox.Position = UDim2.new(1, -95, 0, 102)
cdBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
cdBox.Text = tostring(_G.SellCooldown)
cdBox.TextColor3 = Color3.fromRGB(255, 255, 255)
cdBox.TextSize = 13
cdBox.Font = Enum.Font.SourceSans
cdBox.Parent = mainFrame

local cdCorner = Instance.new("UICorner")
cdCorner.CornerRadius = UDim.new(0, 6)
cdCorner.Parent = cdBox

cdBox.FocusLost:Connect(function()
    local num = tonumber(cdBox.Text)
    if num and num >= 0 then
        _G.SellCooldown = num
    else
        cdBox.Text = tostring(_G.SellCooldown)
    end
end)

-- Keep Labubus Toggle Button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 28)
toggleBtn.Position = UDim2.new(0, 10, 0, 136)
toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
toggleBtn.Text = "Keep Labubus: OFF"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize = 13
toggleBtn.Font = Enum.Font.SourceSansBold
toggleBtn.Parent = mainFrame

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggleBtn

toggleBtn.MouseButton1Click:Connect(function()
    _G.KeepLabubus = not _G.KeepLabubus
    if _G.KeepLabubus then
        toggleBtn.Text = "Keep Labubus: ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    else
        toggleBtn.Text = "Keep Labubus: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    end
end)

-- Run Button
local runButton = Instance.new("TextButton")
runButton.Size = UDim2.new(1, -20, 0, 32)
runButton.Position = UDim2.new(0, 10, 0, 172)
runButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
runButton.Text = "Run Auto-Take"
runButton.TextColor3 = Color3.fromRGB(255, 255, 255)
runButton.TextSize = 14
runButton.Font = Enum.Font.SourceSansBold
runButton.Parent = mainFrame

local btnCorner1 = Instance.new("UICorner")
btnCorner1.CornerRadius = UDim.new(0, 6)
btnCorner1.Parent = runButton

-- Break Button
local breakButton = Instance.new("TextButton")
breakButton.Size = UDim2.new(1, -20, 0, 32)
breakButton.Position = UDim2.new(0, 10, 0, 212)
breakButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
breakButton.Text = "Break Loop"
breakButton.TextColor3 = Color3.fromRGB(255, 255, 255)
breakButton.TextSize = 14
breakButton.Font = Enum.Font.SourceSansBold
breakButton.Parent = mainFrame

local btnCorner2 = Instance.new("UICorner")
btnCorner2.CornerRadius = UDim.new(0, 6)
btnCorner2.Parent = breakButton

-- Full Script Termination (Killer Function)
local function killEverything()
    stopAutoTake()

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)

    screenGui:Destroy()
    print("[Auto-Take] Tasks killed and GUI destroyed.")
end

-- Reload Functionality
local function reloadScript()
    print("[Auto-Take] Fetching script update...")
    stopAutoTake()

    task.spawn(function()
        pcall(function()
            loadstring(game:HttpGet('https://raw.githubusercontent.com/yusufxbenxs/DontstealtheboboAUTOTAKE/refs/heads/main/Main.lua'))()
        end)
    end)

    task.wait(0.5)
    screenGui:Destroy()
    print("[Auto-Take] Old instance terminated successfully.")
end

-- Draggable UI Setup (Prevents opening while dragging on Mobile)
local function enableDragging(frame, clickCallback)
    local dragging, dragInput, dragStart, startPos
    local totalDragDistance = 0

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            totalDragDistance = 0

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if clickCallback and totalDragDistance < 8 then
                        clickCallback()
                    end
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
            totalDragDistance = (input.Position - dragStart).Magnitude
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

enableDragging(mainFrame, nil)
enableDragging(miniBtn, function()
    mainFrame.Visible = true
    miniBtn.Visible = false
end)

reloadButton.MouseButton1Click:Connect(reloadScript)
minimizeButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
    miniBtn.Visible = true
end)

runButton.MouseButton1Click:Connect(startAutoTake)
breakButton.MouseButton1Click:Connect(stopAutoTake)
closeButton.MouseButton1Click:Connect(killEverything)
