-- Ayarlar ve Servis Kurulumu
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

-- Global Durumlar
_G.SelectedPlayer = "Otomatik"
_G.SelectedPlot = "Plot1"
_G.SelectedLabubu = "Herhangi Biri (Rastgele)"
_G.AutoTakeRunning = false
_G.KeepLabubus = false
_G.SafeMode = true
_G.SellCooldown = 50
_G.TweenSpeed = 350 -- Saniyede kat edilen mesafe (Studs)
_G.InteractionMethod = "Otomatik" -- Modlar: "Otomatik", "E/Q Basılı Tut", "Dokunmatik"

if _G.AutoTakeThread then
    task.cancel(_G.AutoTakeThread)
    _G.AutoTakeThread = nil
end

local labubuQueue = {}
local baseSlots = {}

-- Seçime göre hedef Oyuncu Nesnesini bulma
local function getTargetPlayer()
    if _G.SelectedPlayer == "Otomatik" then
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

-- Işınlanma / Hareket Yöneticisi (Tween vs Anında)
local function safeTeleport(targetCFrame)
    local targetPlr = getTargetPlayer()
    if not targetPlr or not targetPlr.Character then return end
    
    local hrp = targetPlr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if _G.SafeMode then
        local distance = (hrp.Position - targetCFrame.Position).Magnitude
        if distance < 1 then return end

        local travelTime = math.clamp(distance / _G.TweenSpeed, 0.05, 1.2)
        local tweenInfo = TweenInfo.new(
            travelTime,
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.Out
        )

        local tween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
        tween:Play()
        tween.Completed:Wait()
    else
        hrp.CFrame = targetCFrame
    end
end

-- Etkileşim Butonu Çalıştırıcısı
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
    task.wait(0.1)

    local duration = (prompt.HoldDuration > 0 and prompt.HoldDuration) or 0.1
    local mode = _G.InteractionMethod

    if mode == "E/Q Basılı Tut" then
        local key = (prompt.KeyboardKeyCode ~= Enum.KeyCode.Unknown) and prompt.KeyboardKeyCode or Enum.KeyCode.E
        VirtualInputManager:SendKeyEvent(true, key, false, game)
        prompt:InputHoldBegin()
        task.wait(duration + 0.1)
        prompt:InputHoldEnd()
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    elseif mode == "Dokunmatik" then
        local viewportSize = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
        local centerPos = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
        
        VirtualInputManager:SendTouchPadEvent(centerPos.X, centerPos.Y, 0, Enum.UserInputState.Begin)
        prompt:InputHoldBegin()
        task.wait(duration + 0.1)
        prompt:InputHoldEnd()
        VirtualInputManager:SendTouchPadEvent(centerPos.X, centerPos.Y, 0, Enum.UserInputState.End)
    else
        -- Otomatik / Doğrudan Tetikleme Yöntemi
        if fireproximityprompt then
            fireproximityprompt(prompt)
            task.wait(duration + 0.1)
        else
            prompt:InputHoldBegin()
            task.wait(duration + 0.1)
            prompt:InputHoldEnd()
        end
    end
end

-- Seçili Hedef Plot Klasörünü Al
local function getTargetPlotFolder()
    local plotsFolder = Workspace:WaitForChild("Map", 5):WaitForChild("Plots", 5)
    if not plotsFolder then return nil end
    return plotsFolder:FindFirstChild(_G.SelectedPlot) or plotsFolder:FindFirstChild("Plot1")
end

-- Kuyruğu ve Hedef Alan Yuvalarını Başlat
local function initializeQueue()
    table.clear(labubuQueue)
    table.clear(baseSlots)

    local npcFolder = Workspace:WaitForChild("Map", 5):WaitForChild("Zones", 5):WaitForChild("Field", 5):WaitForChild("NPC", 5)
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            if _G.SelectedLabubu == "Herhangi Biri (Rastgele)" or npc.Name == _G.SelectedLabubu then
                table.insert(labubuQueue, npc)
            end
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

-- Kesilebilir Bekleme Yardımcısı
local function interruptibleWait(seconds)
    local elapsed = 0
    while elapsed < seconds and _G.AutoTakeRunning do
        task.wait(0.1)
        elapsed = elapsed + 0.1
    end
    return _G.AutoTakeRunning
end

-- Otomatik Toplama Ana Motor Döngüsü
local function startAutoTake()
    if _G.AutoTakeRunning then return end
    _G.AutoTakeRunning = true

    _G.AutoTakeThread = task.spawn(function()
        while _G.AutoTakeRunning do
            initializeQueue()

            if #labubuQueue == 0 or #baseSlots == 0 then
                warn("[Otomatik Toplama] Hedefle eşleşen NPC veya yuvalar bekleniyor...")
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

                    executePromptFully(pickupPrompt)
                    if not interruptibleWait(0.2) then break end

                    local slotData = baseSlots[slotIndex]
                    if slotData and slotData.part then
                        safeTeleport(slotData.part.CFrame + Vector3.new(0, 2, 0))
                        if not interruptibleWait(0.2) then break end

                        if slotData.placePrompt then
                            executePromptFully(slotData.placePrompt)
                        end
                    end

                    slotIndex = slotIndex + 1
                    if not interruptibleWait(0.3) then break end
                end
            end

            if _G.AutoTakeRunning then
                if _G.KeepLabubus then
                    print("[Otomatik Toplama] Alan dolu! 'Labubu'ları Tut' etkin. Döngü durduruluyor.")
                    _G.AutoTakeRunning = false
                    break
                else
                    print("[Otomatik Toplama] Alan dolu! Satış yapmak için " .. tostring(_G.SellCooldown) .. " saniye bekleniyor...")
                    if interruptibleWait(_G.SellCooldown) then
                        print("[Otomatik Toplama] Satış butonları tetikleniyor...")
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
        print("[Otomatik Toplama] Döngü durduruldu.")
    end
end

-- Arayüz Kurulumu
local guiParent = (gethui and gethui()) or CoreGui or localPlayer:WaitForChild("PlayerGui")
if guiParent:FindFirstChild("AutoTakeGUI") then
    guiParent.AutoTakeGUI:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoTakeGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = guiParent

-- Yüzen Küçültme Butonu ("Z")
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

-- Ana Pencere Çerçevesi
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 230, 0, 400)
mainFrame.Position = UDim2.new(0.02, 0, 0.1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BackgroundTransparency = 0.2
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

-- Başlık
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -86, 0, 30)
titleLabel.Position = UDim2.new(0, 10, 0, 5)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Labubu Oto-Toplama"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.Parent = mainFrame

-- Yenileme Butonu (↻)
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

-- Küçültme Butonu (-)
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

-- Kapatma Butonu (X)
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

-- Hedef Oyuncu Açılır Menüsü
local plrDropBtn = Instance.new("TextButton")
plrDropBtn.Size = UDim2.new(1, -20, 0, 26)
plrDropBtn.Position = UDim2.new(0, 10, 0, 36)
plrDropBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
plrDropBtn.Text = "Oyuncu: Otomatik ▼"
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
plrDropFrame.ZIndex = 25
plrDropFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
plrDropFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
plrDropFrame.Parent = mainFrame

local plrListLayout = Instance.new("UIListLayout")
plrListLayout.Parent = plrDropFrame

local function populatePlayerDropdown()
    for _, child in ipairs(plrDropFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    local playerList = {"Otomatik"}
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
        optionBtn.ZIndex = 26
        optionBtn.Parent = plrDropFrame

        optionBtn.MouseButton1Click:Connect(function()
            _G.SelectedPlayer = plrName
            plrDropBtn.Text = "Oyuncu: " .. plrName .. " ▼"
            plrDropFrame.Visible = false
        end)
    end
end

plrDropBtn.MouseButton1Click:Connect(function()
    if not plrDropFrame.Visible then populatePlayerDropdown() end
    plrDropFrame.Visible = not plrDropFrame.Visible
end)

-- Hedef Plot Açılır Menüsü
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
plotDropFrame.ZIndex = 20
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
    optionBtn.ZIndex = 21
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

-- Hedef Labubu Açılır Menüsü
local labubuDropBtn = Instance.new("TextButton")
labubuDropBtn.Size = UDim2.new(1, -20, 0, 26)
labubuDropBtn.Position = UDim2.new(0, 10, 0, 100)
labubuDropBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
labubuDropBtn.Text = "Hedef: Rastgele ▼"
labubuDropBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
labubuDropBtn.TextSize = 13
labubuDropBtn.Font = Enum.Font.SourceSans
labubuDropBtn.Parent = mainFrame

local labubuDropCorner = Instance.new("UICorner")
labubuDropCorner.CornerRadius = UDim.new(0, 6)
labubuDropCorner.Parent = labubuDropBtn

local labubuDropFrame = Instance.new("ScrollingFrame")
labubuDropFrame.Size = UDim2.new(1, -20, 0, 120)
labubuDropFrame.Position = UDim2.new(0, 10, 0, 128)
labubuDropFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
labubuDropFrame.Visible = false
labubuDropFrame.ZIndex = 15
labubuDropFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
labubuDropFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
labubuDropFrame.Parent = mainFrame

local labubuListLayout = Instance.new("UIListLayout")
labubuListLayout.Parent = labubuDropFrame

local function populateLabubuDropdown()
    for _, child in ipairs(labubuDropFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    local items = {"Herhangi Biri (Rastgele)"}
    local npcFolder = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Zones") and Workspace.Map.Zones:FindFirstChild("Field") and Workspace.Map.Zones.Field:FindFirstChild("NPC")
    
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            if not table.find(items, npc.Name) then
                table.insert(items, npc.Name)
            end
        end
    end

    for _, labName in ipairs(items) do
        local optionBtn = Instance.new("TextButton")
        optionBtn.Size = UDim2.new(1, 0, 0, 24)
        optionBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        optionBtn.Text = labName
        optionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        optionBtn.TextSize = 11
        optionBtn.Font = Enum.Font.SourceSans
        optionBtn.ZIndex = 16
        optionBtn.Parent = labubuDropFrame

        optionBtn.MouseButton1Click:Connect(function()
            _G.SelectedLabubu = labName
            labubuDropBtn.Text = "Hedef: " .. string.sub(labName, 1, 12) .. " ▼"
            labubuDropFrame.Visible = false
        end)
    end
end

labubuDropBtn.MouseButton1Click:Connect(function()
    if not labubuDropFrame.Visible then populateLabubuDropdown() end
    labubuDropFrame.Visible = not labubuDropFrame.Visible
end)

-- Satış Bekleme Süresi Metin Giriş Kutusu
local cdLabel = Instance.new("TextLabel")
cdLabel.Size = UDim2.new(0, 110, 0, 26)
cdLabel.Position = UDim2.new(0, 10, 0, 134)
cdLabel.BackgroundTransparency = 1
cdLabel.Text = "Satış Bekleme (Sn):"
cdLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
cdLabel.TextSize = 13
cdLabel.Font = Enum.Font.SourceSans
cdLabel.Parent = mainFrame

local cdBox = Instance.new("TextBox")
cdBox.Size = UDim2.new(0, 85, 0, 26)
cdBox.Position = UDim2.new(1, -95, 0, 134)
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

-- Etkileşim Yöntemi Değiştirme Butonu
local interactBtn = Instance.new("TextButton")
interactBtn.Size = UDim2.new(1, -20, 0, 26)
interactBtn.Position = UDim2.new(0, 10, 0, 168)
interactBtn.BackgroundColor3 = Color3.fromRGB(50, 90, 140)
interactBtn.Text = "Etkileşim: Otomatik / Tetikle"
interactBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
interactBtn.TextSize = 12
interactBtn.Font = Enum.Font.SourceSansBold
interactBtn.Parent = mainFrame

local interactCorner = Instance.new("UICorner")
interactCorner.CornerRadius = UDim.new(0, 6)
interactCorner.Parent = interactBtn

local modes = {"Otomatik", "E/Q Basılı Tut", "Dokunmatik"}
local modeIndex = 1

interactBtn.MouseButton1Click:Connect(function()
    modeIndex = (modeIndex % #modes) + 1
    _G.InteractionMethod = modes[modeIndex]
    
    if _G.InteractionMethod == "Otomatik" then
        interactBtn.Text = "Etkileşim: Otomatik / Tetikle"
        interactBtn.BackgroundColor3 = Color3.fromRGB(50, 90, 140)
    elseif _G.InteractionMethod == "E/Q Basılı Tut" then
        interactBtn.Text = "Etkileşim: E / Q Basılı Tut"
        interactBtn.BackgroundColor3 = Color3.fromRGB(140, 90, 40)
    elseif _G.InteractionMethod == "Dokunmatik" then
        interactBtn.Text = "Etkileşim: Dokunmatik (Mobil)"
        interactBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 120)
    end
end)

-- Labubu'ları Tut Değiştirme Butonu
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 26)
toggleBtn.Position = UDim2.new(0, 10, 0, 200)
toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
toggleBtn.Text = "Labubu'ları Tut: KAPALI"
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
        toggleBtn.Text = "Labubu'ları Tut: AÇIK"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    else
        toggleBtn.Text = "Labubu'ları Tut: KAPALI"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    end
end)

-- Güvenli Mod Değiştirme Butonu
local safeBtn = Instance.new("TextButton")
safeBtn.Size = UDim2.new(1, -20, 0, 26)
safeBtn.Position = UDim2.new(0, 10, 0, 232)
safeBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
safeBtn.Text = "Güvenli Mod: AÇIK"
safeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
safeBtn.TextSize = 13
safeBtn.Font = Enum.Font.SourceSansBold
safeBtn.Parent = mainFrame

local safeCorner = Instance.new("UICorner")
safeCorner.CornerRadius = UDim.new(0, 6)
safeCorner.Parent = safeBtn

-- Güvenli Mod Açıklama Metni
local safeDesc = Instance.new("TextLabel")
safeDesc.Size = UDim2.new(1, -20, 0, 12)
safeDesc.Position = UDim2.new(0, 10, 0, 260)
safeDesc.BackgroundTransparency = 1
safeDesc.Text = "Hızlı Tween (Açık) vs Anında TP (Kapalı)"
safeDesc.TextColor3 = Color3.fromRGB(160, 160, 160)
safeDesc.TextSize = 10
safeDesc.Font = Enum.Font.SourceSansItalic
safeDesc.Parent = mainFrame

safeBtn.MouseButton1Click:Connect(function()
    _G.SafeMode = not _G.SafeMode
    if _G.SafeMode then
        safeBtn.Text = "Güvenli Mod: AÇIK"
        safeBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    else
        safeBtn.Text = "Güvenli Mod: KAPALI"
        safeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    end
end)

-- Çalıştır Butonu
local runButton = Instance.new("TextButton")
runButton.Size = UDim2.new(1, -20, 0, 32)
runButton.Position = UDim2.new(0, 10, 0, 280)
runButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
runButton.Text = "Oto-Toplamayı Başlat"
runButton.TextColor3 = Color3.fromRGB(255, 255, 255)
runButton.TextSize = 14
runButton.Font = Enum.Font.SourceSansBold
runButton.Parent = mainFrame

local btnCorner1 = Instance.new("UICorner")
btnCorner1.CornerRadius = UDim.new(0, 6)
btnCorner1.Parent = runButton

-- Durdur Butonu
local breakButton = Instance.new("TextButton")
breakButton.Size = UDim2.new(1, -20, 0, 32)
breakButton.Position = UDim2.new(0, 10, 0, 320)
breakButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
breakButton.Text = "Döngüyü Durdur"
breakButton.TextColor3 = Color3.fromRGB(255, 255, 255)
breakButton.TextSize = 14
breakButton.Font = Enum.Font.SourceSansBold
breakButton.Parent = mainFrame

local btnCorner2 = Instance.new("UICorner")
btnCorner2.CornerRadius = UDim.new(0, 6)
btnCorner2.Parent = breakButton

-- Betiği Tamamen Sonlandırma
local function killEverything()
    stopAutoTake()

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)

    screenGui:Destroy()
    print("[Otomatik Toplama] Görevler durduruldu ve Arayüz kapatıldı.")
end

-- Yeniden Yükleme İşlevi
local function reloadScript()
    print("[Otomatik Toplama] Betik güncellemesi çekiliyor...")
    stopAutoTake()

    task.spawn(function()
        pcall(function()
            loadstring(game:HttpGet('https://raw.githubusercontent.com/yusufxbenxs/DontstealtheboboAUTOTAKE/refs/heads/main/Main.lua'))()
        end)
    end)

    task.wait(0.5)
    screenGui:Destroy()
    print("[Otomatik Toplama] Eski örnek başarıyla sonlandırıldı.")
end

-- Sürüklenebilir Arayüz Kurulumu
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
