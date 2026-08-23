-- Configuration & Core Setup
local WAIT_BEFORE_SELL = 50 -- Wait time in seconds after base is full before auto-selling

local getService = function(service)
    return (cloneref and cloneref(game:GetService(service))) or game:GetService(service)
end

local Players = getService("Players")
local Workspace = getService("Workspace")
local UserInputService = getService("UserInputService")
local VirtualInputManager = getService("VirtualInputManager")
local CoreGui = getService("CoreGui")

local localPlayer = Players.LocalPlayer

-- Global State Control
_G.SelectedPlot = "Plot1"
_G.AutoTakeRunning = false
_G.KeepLabubus = false

if _G.AutoTakeThread then
    task.cancel(_G.AutoTakeThread)
    _G.AutoTakeThread = nil
end

local labubuQueue = {}
local baseSlots = {}

-- Helper function to complete Proximity Prompts accurately
local function executePromptFully(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    
    if fireproximityprompt then
        fireproximityprompt(prompt)
        task.wait(prompt.HoldDuration + 0.05)
    else
        local completed = false
        local conn
        conn = prompt.PromptButtonHoldEnded:Connect(function()
            completed = true
            if conn then conn:Disconnect() end
        end)

        prompt:InputHoldBegin()
        
        local duration = prompt.HoldDuration > 0 and prompt.HoldDuration or 0.1
        local elapsed = 0
        while elapsed < (duration + 0.1) and _G.AutoTakeRunning and not completed do
            task.wait(0.05)
            elapsed = elapsed + 0.05
        end
        
        prompt:InputHoldEnd()
        if conn then conn:Disconnect() end
    end
end

-- Initialize NPC Queue & Plot Target Slots
local function initializeQueue()
    table.clear(labubuQueue)
    table.clear(baseSlots)

    -- 1. Grab NPCs
    local npcFolder = Workspace:WaitForChild("Map", 5):WaitForChild("Zones", 5):WaitForChild("Field", 5):WaitForChild("NPC", 5)
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            table.insert(labubuQueue, npc)
        end
    end

    -- 2. Find slots under selected plot
    local targetPlot = Workspace:WaitForChild("Map", 5):WaitForChild("Plots", 5):WaitForChild(_G.SelectedPlot, 5)
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

-- Auto-Take Core Task
local function startAutoTake()
    if _G.AutoTakeRunning then return end
    _G.AutoTakeRunning = true

    _G.AutoTakeThread = task.spawn(function()
        while _G.AutoTakeRunning do
            initializeQueue()

            if #labubuQueue == 0 or #baseSlots == 0 then
                warn("[Auto-Take] No NPCs or target slots found for " .. tostring(_G.SelectedPlot))
                if not interruptibleWait(3) then break end
                continue
            end

            local slotIndex = 1

            -- Fill available slots
            while _G.AutoTakeRunning and #labubuQueue > 0 and slotIndex <= #baseSlots do
                local currentNpc = table.remove(labubuQueue, 1)
                local pickupPrompt = currentNpc:FindFirstChild("Prompts") and currentNpc.Prompts:FindFirstChild("Pickup")

                if currentNpc and pickupPrompt then
                    -- Teleport to NPC and trigger pickup
                    safeTeleport(currentNpc:GetPivot())
                    if not interruptibleWait(0.2) then break end

                    executePromptFully(pickupPrompt)
                    if not interruptibleWait(0.3) then break end

                    -- Teleport to slot
                    local slotData = baseSlots[slotIndex]
                    if slotData and slotData.part then
                        safeTeleport(slotData.part.CFrame + Vector3.new(0, 3, 0))
                        if not interruptibleWait(0.2) then break end

                        -- Place Labubu using SlotPlace prompt
                        if slotData.placePrompt then
                            executePromptFully(slotData.placePrompt)
                        end
                    end

                    slotIndex = slotIndex + 1
                    if not interruptibleWait(0.5) then break end
                end
            end

            -- Check Keep Labubus setting before auto-selling
            if _G.AutoTakeRunning then
                if _G.KeepLabubus then
                    print("[Auto-Take] Base full! 'Keep Labubus' is enabled. Skipping sell step...")
                    _G.AutoTakeRunning = false
                    break
                else
                    print("[Auto-Take] Base full! Waiting " .. WAIT_BEFORE_SELL .. "s to sell...")
                    
                    if interruptibleWait(WAIT_BEFORE_SELL) then
                        print("[Auto-Take] Selling items...")
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
                        interruptibleWait(1)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
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
        print("[Auto-Take] Script loop stopped.")
    end
end

-- UI Construction
local guiParent = (gethui and gethui()) or CoreGui or localPlayer:WaitForChild("PlayerGui")
if guiParent:FindFirstChild("AutoTakeGUI") then
    guiParent.AutoTakeGUI:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoTakeGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 220, 0, 215)
mainFrame.Position = UDim2.new(0.02, 0, 0.1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BackgroundTransparency = 0.3
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = mainFrame

-- Title Text
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 0, 30)
titleLabel.Position = UDim2.new(0, 10, 0, 5)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Dont steal the labubu AUTO-TAKE"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.Parent = mainFrame

-- Close Button (X)
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 22, 0, 22)
closeButton.Position = UDim2.new(1, -27, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 14
closeButton.Font = Enum.Font.SourceSansBold
closeButton.Parent = mainFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 4)
closeCorner.Parent = closeButton

-- Dropdown Button
local dropdownBtn = Instance.new("TextButton")
dropdownBtn.Size = UDim2.new(1, -20, 0, 28)
dropdownBtn.Position = UDim2.new(0, 10, 0, 38)
dropdownBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
dropdownBtn.Text = "Select Base: Plot1 ▼"
dropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dropdownBtn.TextSize = 13
dropdownBtn.Font = Enum.Font.SourceSans
dropdownBtn.Parent = mainFrame

local dropCorner = Instance.new("UICorner")
dropCorner.CornerRadius = UDim.new(0, 6)
dropCorner.Parent = dropdownBtn

-- Dropdown Options Frame
local dropdownFrame = Instance.new("Frame")
dropdownFrame.Size = UDim2.new(1, -20, 0, 125)
dropdownFrame.Position = UDim2.new(0, 10, 0, 68)
dropdownFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
dropdownFrame.Visible = false
dropdownFrame.ZIndex = 5
dropdownFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = dropdownFrame

for i = 1, 5 do
    local plotName = "Plot" .. i
    local optionBtn = Instance.new("TextButton")
    optionBtn.Size = UDim2.new(1, 0, 0, 25)
    optionBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    optionBtn.Text = plotName
    optionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    optionBtn.TextSize = 13
    optionBtn.Font = Enum.Font.SourceSans
    optionBtn.ZIndex = 6
    optionBtn.Parent = dropdownFrame

    optionBtn.MouseButton1Click:Connect(function()
        _G.SelectedPlot = plotName
        dropdownBtn.Text = "Select Base: " .. plotName .. " ▼"
        dropdownFrame.Visible = false
    end)
end

dropdownBtn.MouseButton1Click:Connect(function()
    dropdownFrame.Visible = not dropdownFrame.Visible
end)

-- Keep Labubus Toggle Button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 28)
toggleBtn.Position = UDim2.new(0, 10, 0, 72)
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
runButton.Size = UDim2.new(1, -20, 0, 30)
runButton.Position = UDim2.new(0, 10, 0, 108)
runButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
runButton.Text = "Run auto-take"
runButton.TextColor3 = Color3.fromRGB(255, 255, 255)
runButton.TextSize = 14
runButton.Font = Enum.Font.SourceSansBold
runButton.Parent = mainFrame

local btnCorner1 = Instance.new("UICorner")
btnCorner1.CornerRadius = UDim.new(0, 6)
btnCorner1.Parent = runButton

-- Break Button
local breakButton = Instance.new("TextButton")
breakButton.Size = UDim2.new(1, -20, 0, 30)
breakButton.Position = UDim2.new(0, 10, 0, 144)
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
    print("[Auto-Take] UI destroyed and task ended.")
end

-- Dragging Mechanics
local dragging, dragInput, dragStart, startPos

mainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

mainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Button Listeners
runButton.MouseButton1Click:Connect(startAutoTake)
breakButton.MouseButton1Click:Connect(stopAutoTake)
closeButton.MouseButton1Click:Connect(killEverything)
