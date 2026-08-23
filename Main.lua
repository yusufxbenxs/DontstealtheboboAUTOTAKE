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
_G.SelectedTarget = "Auto"
_G.AutoTakeRunning = false
_G.KeepLabubus = false
_G.SellCooldown = 50

if _G.AutoTakeThread then
    task.cancel(_G.AutoTakeThread)
    _G.AutoTakeThread = nil
end

local labubuQueue = {}
local baseSlots = {}

-- Reliable Proximity Prompt Executor
local function executePromptFully(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    
    prompt.Enabled = true
    
    -- Teleport directly inside prompt radius to bypass distance checks
    local parentPart = prompt.Parent
    if parentPart then
        local cf = parentPart:IsA("BasePart") and parentPart.CFrame or (parentPart:IsA("Attachment") and parentPart.WorldCFrame)
        if cf and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
            localPlayer.Character.HumanoidRootPart.CFrame = cf
        end
    end
    task.wait(0.15)

    local duration = (prompt.HoldDuration > 0 and prompt.HoldDuration) or 0.1

    -- Fire prompt natively via executor bridge
    if fireproximityprompt then
        fireproximityprompt(prompt)
        task.wait(duration + 0.15)
    else
        prompt:InputHoldBegin()
        task.wait(duration + 0.15)
        prompt:InputHoldEnd()
    end
end

-- Resolve Target Plot Folder (Auto / Player DisplayName / Plot1-5)
local function getTargetPlotFolder()
    local plotsFolder = Workspace:WaitForChild("Map", 5):WaitForChild("Plots", 5)
    if not plotsFolder then return nil end

    if _G.SelectedTarget == "Auto" then
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            local owner = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player")
            if owner and (owner.Value == localPlayer or owner.Value == localPlayer.Name) then
                return plot
            end
        end
        return plotsFolder:FindFirstChild("Plot1")
    elseif _G.SelectedTarget:sub(1,4) == "Plot" then
        return plotsFolder:FindFirstChild(_G.SelectedTarget)
    else
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            local owner = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player")
            if owner and tostring(owner.Value) == _G.SelectedTarget then
                return plot
            end
        end
    end
    return nil
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

-- Interruptible Wait
local function interruptibleWait(seconds)
    local elapsed = 0
    while elapsed < seconds and _G.AutoTakeRunning do
        task.wait(0.1)
        elapsed = elapsed + 0.1
    end
    return _G.AutoTakeRunning
end

-- Teleport Helper
local function safeTeleport(cframe)
    local char = localPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = cframe
    end
end

-- Auto-Take Engine Task
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
                    print("[Auto-Take] Base full! 'Keep Labubus' enabled. Stopping auto-sell...")
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
        print("[Auto-Take] Loop terminated.")
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
mainFrame.Size = UDim2.new(0, 230, 0, 260)
mainFrame.Position = UDim2.new(0.02, 0, 0.1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BackgroundTransparency = 0.2
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -60, 0, 30)
titleLabel.Position = UDim2.new(0, 10, 0, 5)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Labubu Auto-Take"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.Parent = mainFrame

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

-- Target Dropdown
local dropdownBtn = Instance.new("TextButton")
dropdownBtn.Size = UDim2.new(1, -20, 0, 26)
dropdownBtn.Position = UDim2.new(0, 10, 0, 38)
dropdownBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
dropdownBtn.Text = "Target: Auto ▼"
dropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dropdownBtn.TextSize = 13
dropdownBtn.Font = Enum.Font.SourceSans
dropdownBtn.Parent = mainFrame

local dropCorner = Instance.new("UICorner")
dropCorner.CornerRadius = UDim.new(0, 6)
dropCorner.Parent = dropdownBtn

local dropdownFrame = Instance.new("ScrollingFrame")
dropdownFrame.Size = UDim2.new(1, -20, 0, 130)
dropdownFrame.Position = UDim2.new(0, 10, 0, 66)
dropdownFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
dropdownFrame.Visible = false
dropdownFrame.ZIndex = 10
dropdownFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
dropdownFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
dropdownFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = dropdownFrame

local function populateDropdown()
    for _, child in ipairs(dropdownFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    local targets = {"Auto", "Plot1", "Plot2", "Plot3", "Plot4", "Plot5"}
    local playerList = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        table.insert(playerList, plr.DisplayName .. " (@" .. plr.Name .. ")")
    end
    table.sort(playerList)

    for _, target in ipairs(targets) do table.insert(playerList, 1, target) end

    for _, targetName in ipairs(playerList) do
        local optionBtn = Instance.new("TextButton")
        optionBtn.Size = UDim2.new(1, 0, 0, 24)
        optionBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        optionBtn.Text = targetName
        optionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        optionBtn.TextSize = 12
        optionBtn.Font = Enum.Font.SourceSans
        optionBtn.ZIndex = 11
        optionBtn.Parent = dropdownFrame

        optionBtn.MouseButton1Click:Connect(function()
            _G.SelectedTarget = targetName
            dropdownBtn.Text = "Target: " .. targetName .. " ▼"
            dropdownFrame.Visible = false
        end)
    end
end

dropdownBtn.MouseButton1Click:Connect(function()
    if not dropdownFrame.Visible then populateDropdown() end
    dropdownFrame.Visible = not dropdownFrame.Visible
end)

-- Sell Cooldown Textbox Input
local cdLabel = Instance.new("TextLabel")
cdLabel.Size = UDim2.new(0, 110, 0, 26)
cdLabel.Position = UDim2.new(0, 10, 0, 72)
cdLabel.BackgroundTransparency = 1
cdLabel.Text = "Sell Wait (Sec):"
cdLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
cdLabel.TextSize = 13
cdLabel.Font = Enum.Font.SourceSans
cdLabel.Parent = mainFrame

local cdBox = Instance.new("TextBox")
cdBox.Size = UDim2.new(0, 85, 0, 26)
cdBox.Position = UDim2.new(1, -95, 0, 72)
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
toggleBtn.Position = UDim2.new(0, 10, 0, 106)
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
runButton.Position = UDim2.new(0, 10, 0, 142)
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
breakButton.Position = UDim2.new(0, 10, 0, 182)
breakButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
breakButton.Text = "Break Loop"
breakButton.TextColor3 = Color3.fromRGB(255, 255, 255)
breakButton.TextSize = 14
breakButton.Font = Enum.Font.SourceSansBold
breakButton.Parent = mainFrame

local btnCorner2 = Instance.new("UICorner")
btnCorner2.CornerRadius = UDim.new(0, 6)
btnCorner2.Parent = breakButton

-- Full Killer Functionality
local function killEverything()
    stopAutoTake()

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)

    screenGui:Destroy()
    print("[Auto-Take] Tasks killed and GUI destroyed.")
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

minimizeButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
    miniBtn.Visible = true
end)

runButton.MouseButton1Click:Connect(startAutoTake)
breakButton.MouseButton1Click:Connect(stopAutoTake)
closeButton.MouseButton1Click:Connect(killEverything)
