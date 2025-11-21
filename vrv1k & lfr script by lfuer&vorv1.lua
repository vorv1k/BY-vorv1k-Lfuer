local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local localPlayer = Players.LocalPlayer

local cache = {
    esp = {},
    chams = {},
    xray = {},
    drone = {}
}
local connections = {}
local ui = {
    screenGui = nil,
    mainFrame = nil
}

local state = {
    isMinimized = false,
    isMenuVisible = true,
    originalFOV = 70,
    lastUpdate = 0,
    UPDATE_INTERVAL = 0.033,
    camera = workspace.CurrentCamera
}

local Settings = {
    ESP = {
        Enabled = true,
        ShowEnemies = true,
        ShowDrones = true,
        MaxDistance = 1000,
        ShowNames = true,
        DroneDistance = 500
    },
    Visuals = {
        ShowDistance = true,
        ShowHealth = true,
        OutlineModels = true,
        Chams = false,
        ChamsColor = Color3.fromRGB(255, 255, 255),
        ChamsTransparency = 0.3,
        XRay = false,
        XRayTransparency = 0.5
    },
    FOV = {
        Enabled = false,
        Value = 70,
        MaxFOV = 120
    }
}

local COLORS = {
    Background = Color3.fromRGB(10, 10, 10),
    Surface = Color3.fromRGB(20, 20, 20),
    Primary = Color3.fromRGB(255, 255, 255),
    Secondary = Color3.fromRGB(180, 180, 180),
    Accent = Color3.fromRGB(220, 220, 220),
    Border = Color3.fromRGB(50, 50, 50),
    Success = Color3.fromRGB(100, 255, 100),
    Warning = Color3.fromRGB(255, 255, 100),
    Error = Color3.fromRGB(255, 100, 100)
}

local teamsModel = nil
local localPlayerTeam = nil
local enemyTeams = {}

local function findTeamsModel()
    teamsModel = workspace:FindFirstChild("teams__") or workspace:FindFirstChild("Teams")
    if not teamsModel then
        for _, obj in pairs(workspace:GetChildren()) do
            if obj.Name:lower():find("team") then
                teamsModel = obj
                break
            end
        end
    end
    return teamsModel
end

local function getPlayerTeam(player)
    if not teamsModel then return nil end
    
    for _, teamFolder in pairs(teamsModel:GetChildren()) do
        if teamFolder:FindFirstChild(player.Name) then
            return teamFolder
        end
        for _, playerObj in pairs(teamFolder:GetChildren()) do
            if playerObj:IsA("ObjectValue") and playerObj.Value == player then
                return teamFolder
            elseif playerObj.Name == player.Name then
                return teamFolder
            end
        end
    end
    
    return nil
end

local function updateTeams()
    if not findTeamsModel() then return end
    
    localPlayerTeam = getPlayerTeam(localPlayer)
    enemyTeams = {}
    
    for _, teamFolder in pairs(teamsModel:GetChildren()) do
        if teamFolder ~= localPlayerTeam then
            table.insert(enemyTeams, teamFolder)
        end
    end
end

local function isEnemyPlayer(player)
    if not teamsModel then return player ~= localPlayer end
    if not localPlayerTeam then return player ~= localPlayer end
    
    local playerTeam = getPlayerTeam(player)
    return playerTeam ~= localPlayerTeam
end

local function createGUI()
    if ui.screenGui then ui.screenGui:Destroy() end
    
    ui.screenGui = Instance.new("ScreenGui")
    ui.screenGui.Name = "ESP"
    ui.screenGui.Parent = CoreGui
    ui.screenGui.DisplayOrder = 999
    ui.screenGui.ResetOnSpawn = false
    
    return ui.screenGui
end

local function findTargets()
    local targets = {}
    
    updateTeams()
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character and isEnemyPlayer(player) then
            local character = player.Character
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                targets[character] = {
                    Object = character,
                    Type = "Enemy",
                    Name = player.Name,
                    Player = player
                }
            end
        end
    end
    
    if Settings.ESP.ShowDrones then
        for _, obj in pairs(workspace:GetChildren()) do
            if obj:IsA("Model") then
                local nameLower = obj.Name:lower()
                if nameLower:find("drone") or nameLower:find("fpv") or nameLower:find("quadcopter") or nameLower:find("uav") then
                    local rootPart = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Head") or obj.PrimaryPart
                    if not rootPart then
                        for _, part in pairs(obj:GetDescendants()) do
                            if part:IsA("BasePart") then
                                rootPart = part
                                break
                            end
                        end
                    end
                    
                    if rootPart and not targets[obj] then
                        local isFlying = rootPart.Position.Y > 5 or rootPart.AssemblyLinearVelocity.Magnitude > 1
                        if isFlying then
                            targets[obj] = {
                                Object = obj,
                                Type = "Drone",
                                Name = "FPV Дрон",
                                RootPart = rootPart
                            }
                        end
                    end
                end
            end
        end
    end
    
    return targets
end

local function applyXRay()
    if not Settings.Visuals.XRay then
        for part, originalTransparency in pairs(cache.xray) do
            if part and part.Parent then
                pcall(function() part.Transparency = originalTransparency end)
            end
        end
        cache.xray = {}
        return
    end
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Transparency < Settings.Visuals.XRayTransparency then
            if not cache.xray[obj] then
                cache.xray[obj] = obj.Transparency
            end
            pcall(function() obj.Transparency = Settings.Visuals.XRayTransparency end)
        end
    end
end

local function applyChams(target)
    if not target or not target.Parent then return end
    
    if cache.chams[target] then
        cache.chams[target]:Destroy()
        cache.chams[target] = nil
    end
    
    if not Settings.Visuals.Chams then return end
    
    local highlight = Instance.new("Highlight")
    highlight.Name = "Chams"
    highlight.Adornee = target
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Settings.Visuals.ChamsColor
    highlight.OutlineColor = Settings.Visuals.ChamsColor
    highlight.FillTransparency = Settings.Visuals.ChamsTransparency
    highlight.OutlineTransparency = 0
    highlight.Parent = target
    
    cache.chams[target] = highlight
end

local function removeChams(target)
    if cache.chams[target] then
        cache.chams[target]:Destroy()
        cache.chams[target] = nil
    end
end

local function createModelOutline(target)
    if not target then return nil end
    
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Outline"
    highlight.Adornee = target.Object
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 1.0
    highlight.OutlineColor = target.Type == "Drone" and COLORS.Warning or Settings.Visuals.ChamsColor
    highlight.OutlineTransparency = 0
    highlight.FillColor = target.Type == "Drone" and COLORS.Warning or Settings.Visuals.ChamsColor
    highlight.Parent = ui.screenGui
    
    return highlight
end

local function createBoxESP(target)
    if not target or not target.Object then return nil end
    
    local boxFrame = Instance.new("Frame")
    boxFrame.Name = "BoxESP_" .. target.Object.Name
    boxFrame.BackgroundTransparency = 1
    boxFrame.BorderSizePixel = 2
    boxFrame.BorderColor3 = target.Type == "Drone" and COLORS.Warning or Settings.Visuals.ChamsColor
    boxFrame.ZIndex = 10
    boxFrame.Visible = false
    boxFrame.Parent = ui.screenGui
    
    return boxFrame
end

local function createESP(target)
    if cache.esp[target.Object] then return end
    
    local espFrame = Instance.new("Frame")
    espFrame.Name = "ESP_" .. target.Object.Name
    espFrame.BackgroundTransparency = 1
    espFrame.Size = UDim2.new(1, 0, 1, 0)
    espFrame.ZIndex = 10
    espFrame.Visible = false
    espFrame.Parent = ui.screenGui
    
    local outline = Settings.Visuals.OutlineModels and createModelOutline(target)
    local boxESP = createBoxESP(target)
    
    if Settings.Visuals.Chams then
        applyChams(target.Object)
    end
    
    local infoPanel = Instance.new("Frame")
    infoPanel.Name = "InfoPanel"
    infoPanel.BackgroundTransparency = 0.85
    infoPanel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    infoPanel.Size = UDim2.new(0, 120, 0, 45)
    infoPanel.ZIndex = 12
    infoPanel.Visible = Settings.ESP.ShowNames
    infoPanel.Parent = espFrame
    
    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 6)
    UICorner.Parent = infoPanel
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Text = target.Name
    nameLabel.TextColor3 = target.Type == "Drone" and COLORS.Warning or Settings.Visuals.ChamsColor
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(1, -8, 0, 18)
    nameLabel.Position = UDim2.new(0, 4, 0, 2)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 11
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.ZIndex = 13
    nameLabel.Parent = infoPanel
    
    local distanceLabel = Instance.new("TextLabel")
    distanceLabel.Name = "DistanceLabel"
    distanceLabel.Text = "0m"
    distanceLabel.TextColor3 = COLORS.Secondary
    distanceLabel.BackgroundTransparency = 1
    distanceLabel.Size = UDim2.new(1, -8, 0, 14)
    distanceLabel.Position = UDim2.new(0, 4, 0, 20)
    distanceLabel.Font = Enum.Font.Gotham
    distanceLabel.TextSize = 10
    distanceLabel.TextXAlignment = Enum.TextXAlignment.Left
    distanceLabel.ZIndex = 13
    distanceLabel.Visible = Settings.Visuals.ShowDistance
    distanceLabel.Parent = infoPanel
    
    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.BackgroundColor3 = COLORS.Surface
    healthBar.BorderSizePixel = 0
    healthBar.Size = UDim2.new(1, -8, 0, 4)
    healthBar.Position = UDim2.new(0, 4, 0, 36)
    healthBar.ZIndex = 12
    healthBar.Visible = Settings.Visuals.ShowHealth and target.Type ~= "Drone"
    healthBar.Parent = infoPanel
    
    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(1, 0)
    healthCorner.Parent = healthBar
    
    local healthFill = Instance.new("Frame")
    healthFill.Name = "HealthFill"
    healthFill.BorderSizePixel = 0
    healthFill.Size = UDim2.new(1, 0, 1, 0)
    healthFill.ZIndex = 13
    healthFill.Parent = healthBar
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = healthFill
    
    cache.esp[target.Object] = {
        Frame = espFrame,
        Target = target,
        Outline = outline,
        BoxESP = boxESP,
        LastUpdate = 0,
        LastScreenPos = Vector2.new(0, 0),
        HealthPercent = 1.0
    }
end

local function updateBoxESP(boxFrame, character, screenPos, size)
    if not boxFrame or not character then return end
    
    local head = character:FindFirstChild("Head")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not head or not rootPart then return end
    
    local headPos, headOnScreen = state.camera:WorldToViewportPoint(head.Position)
    local rootPos, rootOnScreen = state.camera:WorldToViewportPoint(rootPart.Position)
    
    if not headOnScreen or not rootOnScreen then return end
    
    local height = math.abs(headPos.Y - rootPos.Y) * 1.2
    local width = height * 0.6
    
    boxFrame.Size = UDim2.new(0, width, 0, height)
    boxFrame.Position = UDim2.new(0, headPos.X - width/2, 0, headPos.Y - height/3)
    boxFrame.Visible = true
end

local function updateESP(targetData)
    local target = targetData.Target.Object
    local espFrame = targetData.Frame
    
    if not target or not target.Parent then
        espFrame.Visible = false
        if targetData.Outline then targetData.Outline.Enabled = false end
        if targetData.BoxESP then targetData.BoxESP.Visible = false end
        removeChams(target)
        return false
    end
    
    local rootPart = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head") or target.PrimaryPart or targetData.Target.RootPart
    if not rootPart then
        espFrame.Visible = false
        if targetData.Outline then targetData.Outline.Enabled = false end
        if targetData.BoxESP then targetData.BoxESP.Visible = false end
        removeChams(target)
        return false
    end
    
    local success, screenPos, onScreen = pcall(function()
        return state.camera:WorldToViewportPoint(rootPart.Position)
    end)
    
    if not success then
        espFrame.Visible = false
        if targetData.Outline then targetData.Outline.Enabled = false end
        if targetData.BoxESP then targetData.BoxESP.Visible = false end
        removeChams(target)
        return false
    end
    
    local distance = (state.camera.CFrame.Position - rootPart.Position).Magnitude
    local maxDistance = targetData.Target.Type == "Drone" and Settings.ESP.DroneDistance or Settings.ESP.MaxDistance
    
    if Settings.ESP.Enabled and onScreen and distance <= maxDistance then
        if targetData.Target.Type == "Enemy" and not Settings.ESP.ShowEnemies then
            espFrame.Visible = false
            if targetData.Outline then targetData.Outline.Enabled = false end
            if targetData.BoxESP then targetData.BoxESP.Visible = false end
            return false
        end
        
        if targetData.Target.Type == "Drone" and not Settings.ESP.ShowDrones then
            espFrame.Visible = false
            if targetData.Outline then targetData.Outline.Enabled = false end
            if targetData.BoxESP then targetData.BoxESP.Visible = false end
            return false
        end
        
        if targetData.Target.Type == "Enemy" and targetData.Target.Player then
            if not isEnemyPlayer(targetData.Target.Player) then
                espFrame.Visible = false
                if targetData.Outline then targetData.Outline.Enabled = false end
                if targetData.BoxESP then targetData.BoxESP.Visible = false end
                return false
            end
        end
        
        if Settings.Visuals.Chams then
            applyChams(target)
        else
            removeChams(target)
        end
        
        if targetData.Outline then
            targetData.Outline.Enabled = Settings.Visuals.OutlineModels
            targetData.Outline.OutlineColor = targetData.Target.Type == "Drone" and COLORS.Warning or Settings.Visuals.ChamsColor
            targetData.Outline.FillColor = targetData.Target.Type == "Drone" and COLORS.Warning or Settings.Visuals.ChamsColor
        end
        
        if targetData.BoxESP and targetData.Target.Type == "Enemy" then
            updateBoxESP(targetData.BoxESP, target, screenPos, 100)
            targetData.BoxESP.BorderColor3 = targetData.Target.Type == "Drone" and COLORS.Warning or Settings.Visuals.ChamsColor
            targetData.BoxESP.Visible = Settings.Visuals.OutlineModels
        elseif targetData.BoxESP then
            targetData.BoxESP.Visible = false
        end
        
        local infoPanel = espFrame:FindFirstChild("InfoPanel")
        if infoPanel then
            -- Убрана плавная анимация для мгновенного обновления позиции
            local targetPosition = UDim2.new(0, screenPos.X - 60, 0, screenPos.Y - 50)
            infoPanel.Position = targetPosition
            
            infoPanel.Visible = Settings.ESP.ShowNames
            
            local nameLabel = infoPanel:FindFirstChild("NameLabel")
            local distanceLabel = infoPanel:FindFirstChild("DistanceLabel")
            local healthBar = infoPanel:FindFirstChild("HealthBar")
            
            if nameLabel then
                nameLabel.Text = targetData.Target.Name
                nameLabel.TextColor3 = targetData.Target.Type == "Drone" and COLORS.Warning or Settings.Visuals.ChamsColor
            end
            
            if distanceLabel then
                distanceLabel.Text = math.floor(distance) .. "m"
                distanceLabel.Visible = Settings.Visuals.ShowDistance
                distanceLabel.TextColor3 = targetData.Target.Type == "Drone" and COLORS.Warning or COLORS.Secondary
            end
            
            if healthBar and targetData.Target.Type == "Enemy" then
                local humanoid = target:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.MaxHealth > 0 then
                    -- Убрана плавная анимация здоровья для мгновенного обновления
                    local newHealthPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                    targetData.HealthPercent = newHealthPercent
                    
                    local healthFill = healthBar:FindFirstChild("HealthFill")
                    if healthFill then
                        healthFill.Size = UDim2.new(targetData.HealthPercent, 0, 1, 0)
                        if targetData.HealthPercent > 0.5 then
                            healthFill.BackgroundColor3 = Color3.fromRGB((1 - targetData.HealthPercent) * 255 * 2, 255, 0)
                        else
                            healthFill.BackgroundColor3 = Color3.fromRGB(255, targetData.HealthPercent * 255 * 2, 0)
                        end
                    end
                    healthBar.Visible = Settings.Visuals.ShowHealth
                else
                    healthBar.Visible = false
                end
            else
                if healthBar then healthBar.Visible = false end
            end
        end
        
        espFrame.Visible = true
        targetData.LastUpdate = tick()
        targetData.LastScreenPos = Vector2.new(screenPos.X, screenPos.Y)
        return true
    else
        espFrame.Visible = false
        if targetData.Outline then targetData.Outline.Enabled = false end
        if targetData.BoxESP then targetData.BoxESP.Visible = false end
        removeChams(target)
        return false
    end
end

local function updateESPSystem()
    local currentTime = tick()
    
    if currentTime - state.lastUpdate < state.UPDATE_INTERVAL then return end
    state.lastUpdate = currentTime
    
    if not Settings.ESP.Enabled then
        for target, data in pairs(cache.esp) do
            data.Frame.Visible = false
            if data.Outline then data.Outline.Enabled = false end
            if data.BoxESP then data.BoxESP.Visible = false end
            removeChams(target)
        end
        return
    end
    
    local targets = findTargets()
    local currentTargets = {}
    
    for target, targetData in pairs(targets) do
        if not cache.esp[target] then createESP(targetData) end
        currentTargets[target] = true
    end
    
    for target, data in pairs(cache.esp) do
        if not currentTargets[target] then
            data.Frame:Destroy()
            if data.Outline then data.Outline:Destroy() end
            if data.BoxESP then data.BoxESP:Destroy() end
            removeChams(target)
            cache.esp[target] = nil
        end
    end
    
    for target, data in pairs(cache.esp) do
        updateESP(data)
    end
end

local function updateFOV()
    if state.camera then
        if Settings.FOV.Enabled then
            state.camera.FieldOfView = Settings.FOV.Value
        else
            state.camera.FieldOfView = state.originalFOV
        end
    end
end

local function createToggle(name, settingTable, settingKey, yPos, parentFrame)
    local toggleFrame = Instance.new("Frame")
    toggleFrame.Size = UDim2.new(1, -20, 0, 35)
    toggleFrame.Position = UDim2.new(0, 10, 0, yPos)
    toggleFrame.BackgroundColor3 = COLORS.Surface
    toggleFrame.BackgroundTransparency = 0.1
    toggleFrame.Parent = parentFrame
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 8)
    toggleCorner.Parent = toggleFrame
    
    local toggleStroke = Instance.new("UIStroke")
    toggleStroke.Color = COLORS.Border
    toggleStroke.Thickness = 1
    toggleStroke.Parent = toggleFrame
    
    local label = Instance.new("TextLabel")
    label.Text = name
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = COLORS.Primary
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = toggleFrame
    
    local switchContainer = Instance.new("Frame")
    switchContainer.Size = UDim2.new(0, 50, 0, 25)
    switchContainer.Position = UDim2.new(0.85, -25, 0.5, -12)
    switchContainer.BackgroundColor3 = COLORS.Surface
    switchContainer.Parent = toggleFrame
    
    local switchCorner = Instance.new("UICorner")
    switchCorner.CornerRadius = UDim.new(1, 0)
    switchCorner.Parent = switchContainer
    
    local switchStroke = Instance.new("UIStroke")
    switchStroke.Color = COLORS.Border
    switchStroke.Thickness = 2
    switchStroke.Parent = switchContainer
    
    local switchCircle = Instance.new("Frame")
    switchCircle.Size = UDim2.new(0, 19, 0, 19)
    switchCircle.Position = UDim2.new(0, 3, 0.5, -9)
    switchCircle.BackgroundColor3 = settingTable[settingKey] and COLORS.Success or COLORS.Error
    switchCircle.Parent = switchContainer
    
    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(1, 0)
    circleCorner.Parent = switchCircle
    
    local circleStroke = Instance.new("UIStroke")
    circleStroke.Color = COLORS.Primary
    circleStroke.Thickness = 1
    circleStroke.Parent = switchCircle
    
    local toggleButton = Instance.new("TextButton")
    toggleButton.Text = ""
    toggleButton.Size = UDim2.new(1, 0, 1, 0)
    toggleButton.BackgroundTransparency = 1
    toggleButton.Parent = toggleFrame
    
    local function animateToggle(isEnabled)
        local targetPosition = isEnabled and UDim2.new(1, -22, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        local targetColor = isEnabled and COLORS.Success or COLORS.Error
        
        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local positionTween = TweenService:Create(switchCircle, tweenInfo, {Position = targetPosition})
        local colorTween = TweenService:Create(switchCircle, tweenInfo, {BackgroundColor3 = targetColor})
        
        positionTween:Play()
        colorTween:Play()
    end
    
    animateToggle(settingTable[settingKey])
    
    toggleButton.MouseButton1Click:Connect(function()
        settingTable[settingKey] = not settingTable[settingKey]
        animateToggle(settingTable[settingKey])
        
        if settingTable == Settings.FOV then
            updateFOV()
        elseif settingKey == "XRay" then
            applyXRay()
        end
    end)
    
    return toggleFrame
end

local function createSlider(name, settingTable, settingKey, minValue, maxValue, yPos, parentFrame)
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(1, -20, 0, 50)
    sliderFrame.Position = UDim2.new(0, 10, 0, yPos)
    sliderFrame.BackgroundColor3 = COLORS.Surface
    sliderFrame.BackgroundTransparency = 0.1
    sliderFrame.Parent = parentFrame
    
    local sliderCorner = Instance.new("UICorner")
    sliderCorner.CornerRadius = UDim.new(0, 8)
    sliderCorner.Parent = sliderFrame
    
    local sliderStroke = Instance.new("UIStroke")
    sliderStroke.Color = COLORS.Border
    sliderStroke.Thickness = 1
    sliderStroke.Parent = sliderFrame
    
    local label = Instance.new("TextLabel")
    label.Text = name .. ": " .. settingTable[settingKey]
    label.Size = UDim2.new(1, -10, 0, 20)
    label.Position = UDim2.new(0, 5, 0, 5)
    label.BackgroundTransparency = 1
    label.TextColor3 = COLORS.Primary
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = sliderFrame
    
    local sliderTrack = Instance.new("Frame")
    sliderTrack.Size = UDim2.new(1, -10, 0, 10)
    sliderTrack.Position = UDim2.new(0, 5, 0, 30)
    sliderTrack.BackgroundColor3 = COLORS.Background
    sliderTrack.Parent = sliderFrame
    
    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = sliderTrack
    
    local sliderFill = Instance.new("Frame")
    local fillPercentage = (settingTable[settingKey] - minValue) / (maxValue - minValue)
    sliderFill.Size = UDim2.new(fillPercentage, 0, 1, 0)
    sliderFill.BackgroundColor3 = COLORS.Primary
    sliderFill.Parent = sliderTrack
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = sliderFill
    
    local sliderButton = Instance.new("TextButton")
    sliderButton.Text = ""
    sliderButton.Size = UDim2.new(1, 0, 2, 0)
    sliderButton.Position = UDim2.new(0, 0, -0.5, 0)
    sliderButton.BackgroundTransparency = 1
    sliderButton.Parent = sliderTrack
    
    local function updateSliderValue(xPos)
        local relativeX = math.clamp(xPos, 0, sliderTrack.AbsoluteSize.X)
        local value = math.floor(minValue + (relativeX / sliderTrack.AbsoluteSize.X) * (maxValue - minValue))
        
        settingTable[settingKey] = value
        label.Text = name .. ": " .. value
        
        local newFillPercentage = (value - minValue) / (maxValue - minValue)
        sliderFill.Size = UDim2.new(newFillPercentage, 0, 1, 0)
        
        if settingTable == Settings.FOV then
            updateFOV()
        end
    end
    
    sliderButton.MouseButton1Down:Connect(function()
        local connection
        connection = RunService.RenderStepped:Connect(function()
            if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                connection:Disconnect()
                return
            end
            
            local mousePos = UserInputService:GetMouseLocation()
            local trackPos = sliderTrack.AbsolutePosition
            local xPos = mousePos.X - trackPos.X
            
            updateSliderValue(xPos)
        end)
    end)
    
    return sliderFrame
end

local function createColorEditor()
    local colorEditor = Instance.new("Frame")
    colorEditor.Size = UDim2.new(0, 320, 0, 400)
    colorEditor.Position = UDim2.new(0.5, -160, 0.5, -200)
    colorEditor.BackgroundColor3 = COLORS.Background
    colorEditor.BackgroundTransparency = 0.05
    colorEditor.Visible = false
    colorEditor.ZIndex = 100
    colorEditor.Parent = ui.screenGui
    
    local editorCorner = Instance.new("UICorner")
    editorCorner.CornerRadius = UDim.new(0, 15)
    editorCorner.Parent = colorEditor
    
    local editorStroke = Instance.new("UIStroke")
    editorStroke.Color = COLORS.Border
    editorStroke.Thickness = 2
    editorStroke.Parent = colorEditor
    
    local closeButton = Instance.new("TextButton")
    closeButton.Text = "×"
    closeButton.Size = UDim2.new(0, 25, 0, 25)
    closeButton.Position = UDim2.new(0, 5, 0, 5)
    closeButton.BackgroundColor3 = COLORS.Error
    closeButton.TextColor3 = COLORS.Primary
    closeButton.Font = Enum.Font.GothamBlack
    closeButton.TextSize = 18
    closeButton.ZIndex = 101
    closeButton.Parent = colorEditor
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(1, 0)
    closeCorner.Parent = closeButton
    
    local closeStroke = Instance.new("UIStroke")
    closeStroke.Color = COLORS.Border
    closeStroke.Thickness = 1
    closeStroke.Parent = closeButton
    
    closeButton.MouseButton1Click:Connect(function()
        colorEditor.Visible = false
    end)
    
    local title = Instance.new("TextLabel")
    title.Text = "🎨 Редактор цветов"
    title.Size = UDim2.new(1, -40, 0, 40)
    title.Position = UDim2.new(0, 35, 0, 10)
    title.BackgroundTransparency = 1
    title.TextColor3 = COLORS.Primary
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 18
    title.ZIndex = 101
    title.Parent = colorEditor
    
    local colorPreview = Instance.new("Frame")
    colorPreview.Size = UDim2.new(0, 60, 0, 60)
    colorPreview.Position = UDim2.new(1, -70, 0, 10)
    colorPreview.BackgroundColor3 = Settings.Visuals.ChamsColor
    colorPreview.ZIndex = 101
    colorPreview.Parent = colorEditor
    
    local previewCorner = Instance.new("UICorner")
    previewCorner.CornerRadius = UDim.new(0, 8)
    previewCorner.Parent = colorPreview
    
    local previewStroke = Instance.new("UIStroke")
    previewStroke.Color = COLORS.Primary
    previewStroke.Thickness = 2
    previewStroke.Parent = colorPreview
    
    local colorPalette = Instance.new("Frame")
    colorPalette.Size = UDim2.new(1, -20, 0, 200)
    colorPalette.Position = UDim2.new(0, 10, 0, 80)
    colorPalette.BackgroundTransparency = 1
    colorPalette.ZIndex = 101
    colorPalette.Parent = colorEditor
    
    local colors = {
        Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 50, 50), Color3.fromRGB(255, 100, 100), Color3.fromRGB(255, 150, 150),
        Color3.fromRGB(200, 0, 0), Color3.fromRGB(200, 50, 50), Color3.fromRGB(200, 100, 100), Color3.fromRGB(200, 150, 150),
        
        Color3.fromRGB(0, 255, 0), Color3.fromRGB(50, 255, 50), Color3.fromRGB(100, 255, 100), Color3.fromRGB(150, 255, 150),
        Color3.fromRGB(0, 200, 0), Color3.fromRGB(50, 200, 50), Color3.fromRGB(100, 200, 100), Color3.fromRGB(150, 200, 150),
        
        Color3.fromRGB(0, 0, 255), Color3.fromRGB(50, 50, 255), Color3.fromRGB(100, 100, 255), Color3.fromRGB(150, 150, 255),
        Color3.fromRGB(0, 0, 200), Color3.fromRGB(50, 50, 200), Color3.fromRGB(100, 100, 200), Color3.fromRGB(150, 150, 200),
        
        Color3.fromRGB(255, 255, 0), Color3.fromRGB(255, 200, 0), Color3.fromRGB(255, 150, 0), Color3.fromRGB(255, 100, 0),
        Color3.fromRGB(200, 200, 0), Color3.fromRGB(200, 150, 0), Color3.fromRGB(200, 100, 0), Color3.fromRGB(200, 50, 0),
        
        Color3.fromRGB(255, 0, 255), Color3.fromRGB(255, 50, 200), Color3.fromRGB(255, 100, 150), Color3.fromRGB(255, 150, 200),
        Color3.fromRGB(200, 0, 200), Color3.fromRGB(200, 50, 150), Color3.fromRGB(200, 100, 100), Color3.fromRGB(200, 150, 150),
        
        Color3.fromRGB(0, 255, 255), Color3.fromRGB(50, 255, 200), Color3.fromRGB(100, 255, 150), Color3.fromRGB(150, 255, 200),
        Color3.fromRGB(0, 200, 200), Color3.fromRGB(50, 200, 150), Color3.fromRGB(100, 200, 100), Color3.fromRGB(150, 200, 150),
        
        Color3.fromRGB(128, 0, 255), Color3.fromRGB(150, 50, 255), Color3.fromRGB(180, 100, 255), Color3.fromRGB(200, 150, 255),
        Color3.fromRGB(100, 0, 200), Color3.fromRGB(120, 50, 200), Color3.fromRGB(150, 100, 200), Color3.fromRGB(180, 150, 200),
        
        Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200), Color3.fromRGB(150, 150, 150), Color3.fromRGB(100, 100, 100),
        Color3.fromRGB(50, 50, 50), Color3.fromRGB(0, 0, 0), Color3.fromRGB(128, 128, 128), Color3.fromRGB(180, 180, 180)
    }
    
    local cellSize = 35
    local spacing = 2
    local colorsPerRow = 8
    
    for i = 1, #colors do
        local row = math.floor((i-1) / colorsPerRow)
        local col = (i-1) % colorsPerRow
        
        local colorCell = Instance.new("TextButton")
        colorCell.Size = UDim2.new(0, cellSize, 0, cellSize)
        colorCell.Position = UDim2.new(0, col * (cellSize + spacing), 0, row * (cellSize + spacing))
        colorCell.BackgroundColor3 = colors[i]
        colorCell.BorderSizePixel = 0
        colorCell.AutoButtonColor = false
        colorCell.Text = ""
        colorCell.ZIndex = 102
        colorCell.Parent = colorPalette
        
        local cellCorner = Instance.new("UICorner")
        cellCorner.CornerRadius = UDim.new(0, 4)
        cellCorner.Parent = colorCell
        
        local cellStroke = Instance.new("UIStroke")
        cellStroke.Color = COLORS.Primary
        cellStroke.Thickness = 1
        cellStroke.Parent = colorCell
        
        colorCell.MouseButton1Click:Connect(function()
            Settings.Visuals.ChamsColor = colors[i]
            colorPreview.BackgroundColor3 = colors[i]
            
            for target, _ in pairs(cache.esp) do
                if cache.chams[target] then
                    cache.chams[target].FillColor = colors[i]
                    cache.chams[target].OutlineColor = colors[i]
                end
            end
        end)
    end
    
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == Enum.KeyCode.Escape and colorEditor.Visible then
            colorEditor.Visible = false
        end
    end)
    
    return colorEditor
end

local function createSettingsButton(yPos, parentFrame, onClick)
    local button = Instance.new("TextButton")
    button.Text = "⚙️ Настройки цветов"
    button.Size = UDim2.new(1, -20, 0, 35)
    button.Position = UDim2.new(0, 10, 0, yPos)
    button.BackgroundColor3 = COLORS.Surface
    button.TextColor3 = COLORS.Primary
    button.Font = Enum.Font.GothamBold
    button.TextSize = 14
    button.Parent = parentFrame
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = button
    
    local buttonStroke = Instance.new("UIStroke")
    buttonStroke.Color = COLORS.Border
    buttonStroke.Thickness = 1
    buttonStroke.Parent = button
    
    button.MouseButton1Click:Connect(onClick)
    
    return button
end

local function createCheatMenu()
    if ui.mainFrame then ui.mainFrame:Destroy() end
    
    local mainFrameInstance = Instance.new("Frame")
    mainFrameInstance.Name = "ESP"
    mainFrameInstance.Size = UDim2.new(0, 350, 0, 500)
    mainFrameInstance.Position = UDim2.new(0.02, 0, 0.02, 0)
    mainFrameInstance.BackgroundColor3 = COLORS.Background
    mainFrameInstance.BackgroundTransparency = 0.05
    mainFrameInstance.BorderSizePixel = 0
    mainFrameInstance.ClipsDescendants = true
    mainFrameInstance.Visible = state.isMenuVisible
    mainFrameInstance.Parent = ui.screenGui
    
    ui.mainFrame = mainFrameInstance
    
    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 15)
    UICorner.Parent = mainFrameInstance
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.Border
    stroke.Thickness = 2
    stroke.Parent = mainFrameInstance
    
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, -20, 0, 50)
    titleBar.Position = UDim2.new(0, 10, 0, 10)
    titleBar.BackgroundColor3 = COLORS.Surface
    titleBar.BackgroundTransparency = 0.1
    titleBar.Parent = mainFrameInstance
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 10)
    titleCorner.Parent = titleBar
    
    local titleStroke = Instance.new("UIStroke")
    titleStroke.Color = COLORS.Border
    titleStroke.Thickness = 2
    titleStroke.Parent = titleBar
    
    local minimizeButton = Instance.new("TextButton")
    minimizeButton.Name = "MinimizeButton"
    minimizeButton.Text = "▲"
    minimizeButton.Size = UDim2.new(0, 25, 0, 25)
    minimizeButton.Position = UDim2.new(1, -30, 0.5, -12)
    minimizeButton.AnchorPoint = Vector2.new(1, 0.5)
    minimizeButton.BackgroundColor3 = COLORS.Surface
    minimizeButton.TextColor3 = COLORS.Primary
    minimizeButton.Font = Enum.Font.GothamBold
    minimizeButton.TextSize = 14
    minimizeButton.Parent = titleBar
    
    local minimizeCorner = Instance.new("UICorner")
    minimizeCorner.CornerRadius = UDim.new(0, 6)
    minimizeCorner.Parent = minimizeButton
    
    local minimizeStroke = Instance.new("UIStroke")
    minimizeStroke.Color = COLORS.Border
    minimizeStroke.Thickness = 1
    minimizeStroke.Parent = minimizeButton
    
    local title = Instance.new("TextLabel")
    title.Text = "vrv1k & lfr script."
    title.Size = UDim2.new(1, -40, 0.6, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = COLORS.Primary
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar
    
    local subtitle = Instance.new("TextLabel")
    subtitle.Text = "by Vorv1k & lfuer"
    subtitle.Size = UDim2.new(1, -40, 0.4, 0)
    subtitle.Position = UDim2.new(0, 10, 0.6, 0)
    subtitle.BackgroundTransparency = 1
    subtitle.TextColor3 = COLORS.Secondary
    subtitle.Font = Enum.Font.GothamBold
    subtitle.TextSize = 10
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = titleBar
    
    local contentContainer = Instance.new("Frame")
    contentContainer.Name = "ContentContainer"
    contentContainer.Size = UDim2.new(1, 0, 1, -70)
    contentContainer.Position = UDim2.new(0, 0, 0, 70)
    contentContainer.BackgroundTransparency = 1
    contentContainer.Parent = mainFrameInstance
    
    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(1, -20, 0, 40)
    tabContainer.Position = UDim2.new(0, 10, 0, 0)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = contentContainer
    
    local tabs = {"ESP", "Visuals", "Misc"}
    local currentTab = "ESP"
    
    local contentFrames = {}
    
    for i, tabName in pairs(tabs) do
        local tabButton = Instance.new("TextButton")
        tabButton.Text = tabName
        tabButton.Size = UDim2.new(0.3, 0, 1, 0)
        tabButton.Position = UDim2.new(0.3 * (i-1), 0, 0, 0)
        tabButton.BackgroundColor3 = i == 1 and COLORS.Surface or COLORS.Background
        tabButton.TextColor3 = COLORS.Primary
        tabButton.Font = Enum.Font.GothamBold
        tabButton.TextSize = 14
        tabButton.Parent = tabContainer
        
        local tabCorner = Instance.new("UICorner")
        tabCorner.CornerRadius = UDim.new(0, 8)
        tabCorner.Parent = tabButton
        
        local tabStroke = Instance.new("UIStroke")
        tabStroke.Color = COLORS.Border
        tabStroke.Thickness = 1
        tabStroke.Parent = tabButton
        
        local contentFrame = Instance.new("ScrollingFrame")
        contentFrame.Size = UDim2.new(1, -20, 1, -55)
        contentFrame.Position = UDim2.new(0, 10, 0, 50)
        contentFrame.BackgroundTransparency = 1
        contentFrame.ScrollBarThickness = 4
        contentFrame.ScrollBarImageColor3 = COLORS.Primary
        contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        contentFrame.Visible = i == 1
        contentFrame.Parent = contentContainer
        
        contentFrames[tabName] = contentFrame
        
        tabButton.MouseButton1Click:Connect(function()
            currentTab = tabName
            for name, frame in pairs(contentFrames) do
                frame.Visible = (name == tabName)
                for _, btn in pairs(tabContainer:GetChildren()) do
                    if btn:IsA("TextButton") then
                        btn.BackgroundColor3 = btn.Text == tabName and COLORS.Surface or COLORS.Background
                    end
                end
            end
        end)
    end
    
    local colorEditor = createColorEditor()
    
    local espContent = contentFrames["ESP"]
    local yPos = 0
    createToggle("ESP Включено", Settings.ESP, "Enabled", yPos, espContent)
    yPos = yPos + 40
    createToggle("Показывать врагов", Settings.ESP, "ShowEnemies", yPos, espContent)
    yPos = yPos + 40
    createToggle("Показывать дронов", Settings.ESP, "ShowDrones", yPos, espContent)
    yPos = yPos + 40
    createToggle("Показывать имена", Settings.ESP, "ShowNames", yPos, espContent)
    yPos = yPos + 40
    createSlider("Дальность ESP", Settings.ESP, "MaxDistance", 100, 2000, yPos, espContent)
    yPos = yPos + 55
    createSlider("Дальность дронов", Settings.ESP, "DroneDistance", 100, 1000, yPos, espContent)
    yPos = yPos + 55
    
    espContent.CanvasSize = UDim2.new(0, 0, 0, yPos)
    
    local visualsContent = contentFrames["Visuals"]
    yPos = 0
    createToggle("Обводка моделей", Settings.Visuals, "OutlineModels", yPos, visualsContent)
    yPos = yPos + 40
    createToggle("Показывать здоровье", Settings.Visuals, "ShowHealth", yPos, visualsContent)
    yPos = yPos + 40
    createToggle("Показывать дистанцию", Settings.Visuals, "ShowDistance", yPos, visualsContent)
    yPos = yPos + 40
    createToggle("Chams", Settings.Visuals, "Chams", yPos, visualsContent)
    yPos = yPos + 40
    createToggle("X-Ray", Settings.Visuals, "XRay", yPos, visualsContent)
    yPos = yPos + 40
    
    createSettingsButton(yPos, visualsContent, function()
        colorEditor.Visible = true
    end)
    yPos = yPos + 45
    
    visualsContent.CanvasSize = UDim2.new(0, 0, 0, yPos)
    
    local miscContent = contentFrames["Misc"]
    yPos = 0
    createToggle("Изменение FOV", Settings.FOV, "Enabled", yPos, miscContent)
    yPos = yPos + 40
    createSlider("Значение FOV", Settings.FOV, "Value", 30, 120, yPos, miscContent)
    yPos = yPos + 55
    
    miscContent.CanvasSize = UDim2.new(0, 0, 0, yPos)
    
    local bottomPanel = Instance.new("Frame")
    bottomPanel.Size = UDim2.new(1, -20, 0, 30)
    bottomPanel.Position = UDim2.new(0, 10, 1, -35)
    bottomPanel.BackgroundColor3 = COLORS.Surface
    bottomPanel.BackgroundTransparency = 0.1
    bottomPanel.Parent = contentContainer
    
    local bottomCorner = Instance.new("UICorner")
    bottomCorner.CornerRadius = UDim.new(0, 8)
    bottomCorner.Parent = bottomPanel
    
    local bottomStroke = Instance.new("UIStroke")
    bottomStroke.Color = COLORS.Border
    bottomStroke.Thickness = 1
    bottomStroke.Parent = bottomPanel
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Text = "🟢 СИСТЕМА АКТИВНА | FPS: 60"
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = COLORS.Success
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 11
    statusLabel.Parent = bottomPanel
    
    spawn(function()
        while true do
            wait(1)
            if statusLabel and statusLabel.Parent then
                local fps = math.floor(1/RunService.RenderStepped:Wait())
                statusLabel.Text = "🟢 СИСТЕМА АКТИВНА | FPS: " .. fps
            end
        end
    end)
    
    minimizeButton.MouseButton1Click:Connect(function()
        state.isMinimized = not state.isMinimized
        local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        
        if state.isMinimized then
            local sizeTween = TweenService:Create(mainFrameInstance, tweenInfo, {Size = UDim2.new(0, 350, 0, 70)})
            sizeTween:Play()
            contentContainer.Visible = false
            minimizeButton.Text = "▼"
        else
            local sizeTween = TweenService:Create(mainFrameInstance, tweenInfo, {Size = UDim2.new(0, 350, 0, 500)})
            sizeTween:Play()
            contentContainer.Visible = true
            minimizeButton.Text = "▲"
        end
    end)
    
    local dragging = false
    local dragStart, startPos
    
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrameInstance.Position
        end
    end)
    
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            mainFrameInstance.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    return mainFrameInstance
end

local function setupRespawn()
    local function onCharacterAdded(character)
        if character:WaitForChild("Humanoid") then
            wait(1)
            state.camera = workspace.CurrentCamera
            updateTeams()
        end
    end
    
    localPlayer.CharacterAdded:Connect(onCharacterAdded)
    
    if localPlayer.Character then
        onCharacterAdded(localPlayer.Character)
    end
end

local function setupHotkeys()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == Enum.KeyCode.Escape then
            state.isMenuVisible = not state.isMenuVisible
            if ui.mainFrame then
                ui.mainFrame.Visible = state.isMenuVisible
            end
        elseif input.KeyCode == Enum.KeyCode.Insert then
            Settings.ESP.Enabled = not Settings.ESP.Enabled
        elseif input.KeyCode == Enum.KeyCode.Home then
            Settings.Visuals.Chams = not Settings.Visuals.Chams
        elseif input.KeyCode == Enum.KeyCode.End then
            Settings.Visuals.XRay = not Settings.Visuals.XRay
            applyXRay()
        elseif input.KeyCode == Enum.KeyCode.PageUp then
            Settings.ESP.ShowDrones = not Settings.ESP.ShowDrones
        elseif input.KeyCode == Enum.KeyCode.R then
            updateTeams()
        end
    end)
end

local function main()
    state.camera = workspace.CurrentCamera
    if state.camera then
        state.originalFOV = state.camera.FieldOfView
    end
    
    findTeamsModel()
    updateTeams()
    
    createGUI()
    createCheatMenu()
    setupRespawn()
    setupHotkeys()
    
    connections.render = RunService.RenderStepped:Connect(function()
        updateESPSystem()
        updateFOV()
    end)
    
    spawn(function()
        while true do
            wait(10)
            updateTeams()
        end
    end)
    
    print("🟢 ESP загружена!")
    print("🎮 Горячие клавиши:")
    print("   ESC - Показать/скрыть меню")
    print("   INSERT - Включить/выключить ESP")
    print("   HOME - Включить/выключить Chams")
    print("   END - Включить/выключить X-Ray")
    print("   PAGE UP - Включить/выключить ESP дронов")
    print("   R - Принудительное обновление команд")
    print("🎯 Режим: Только противники (система команд)")
    print("🎨 Упрощенный редактор цветов доступен в разделе Visuals")
    print("С уважением Lfuer&Vorv1k")
end

main()
