-- ============================================================
--  ABANG HUB | BLOCK SPIN - RAYFIELD UI VERSION
-- ============================================================

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "ABANG HUB | BLOCK SPIN",
    LoadingTitle = "ABANG HUB Loading...",
    LoadingSubtitle = "by Block spin",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AbangHub",
        FileName = "BlockSpinConfig"
    },
    KeySystem = false,
})

-- สร้าง Tabs หลัก
local CombatTab = Window:CreateTab("Combat", "crosshair")
local WeaponTab = Window:CreateTab("Weapon", "layers")
local ESPTab = Window:CreateTab("ESP", "eye")
local CharTab = Window:CreateTab("Character", "user")

-- ============================================================
--  ระบบฟังก์ชันทั้งหมด (Backend Functions)
-- ============================================================

local SERVICE_ID = "22934"
local API_KEY = "19d0ed2a-7f57-41cf-9f63-f089d56f570a"
local WEBHOOK = "https://discord.com/api/webhooks/100250800715456/Kbfj8zPWM2Ufruk5HN5GDqlcnKXVfcB6mc6pB_iXvqaemAELdSu2Yqt0Svy-FuJ5RMdT"

local GREEN = Color3.fromHex("00FF00")

-- Webhook Executed Notification
pcall(function()
    local HttpService = game:GetService("HttpService")
    local player = game:GetService("Players").LocalPlayer
    local UIS = game:GetService("UserInputService")
    local hwid = pcall(gethwid) and gethwid() or "Unknown"
    local executor = identifyexecutor and identifyexecutor() or "Unknown"
    local platform = UIS.TouchEnabled and not UIS.KeyboardEnabled and "Mobile" or "PC"
    local data = {
        embeds = {{
            title = "🔐 Script Executed",
            color = 0x7000FF,
            fields = {
                { name = "User", value = player.Name, inline = true },
                { name = "Executor", value = executor, inline = true },
                { name = "Platform", value = platform, inline = true },
                { name = "HWID", value = hwid, inline = false },
            },
            footer = { text = "ABANG HUB | " .. os.date("%d/%m/%Y %H:%M:%S") }
        }}
    }
    request({ Url = WEBHOOK, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode(data) })
end)

-- Services & Variables
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local UserInputService    = game:GetService("UserInputService")
local Workspace           = game:GetService("Workspace")

local LocalPlayer  = Players.LocalPlayer
local Character    = LocalPlayer.Character
local Humanoid     = Character and Character:FindFirstChild("Humanoid")
local HRP          = Character and Character:FindFirstChild("HumanoidRootPart")
local Camera       = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")

task.spawn(function()
    if not Character then Character = LocalPlayer.CharacterAdded:Wait() end
    Humanoid = Character:WaitForChild("Humanoid")
    HRP = Character:WaitForChild("HumanoidRootPart")
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    HRP = char:WaitForChild("HumanoidRootPart")
end)

local DroppedItems    = Workspace:WaitForChild("DroppedItems")
local itemDrawings    = {}
local positionHistory = {}
local excludedPlayers = {}
local itemPickupTrack = {}

-- State Variables สำหรับควบคุมฟังก์ชัน
local silentAimEnabled    = false
local fovRadius           = 120
local aimTarget           = nil
local shotMultiplier      = 1
local nameESPEnabled      = false
local highlightEnabled    = false
local jumpPowerEnabled    = false

local autoShootEnabled    = false
local autoShootDelay      = 0.05

_G.WalkSpeedEnabled    = false
_G.WalkSpeedMultiplier = 0.10
local autoPickupEnabled   = false

local getEnv = (type(getgenv) == "function" and getgenv) or function() return _G end
getEnv().Sky = false
getEnv().SkyAmount = 1500

local Counter
pcall(function()
    for _, v in ipairs(getgc(true)) do
        if typeof(v) == "table" and rawget(v, "event") and rawget(v, "func") then
            Counter = v
            break
        end
    end
end)

local SendRemote
pcall(function()
    SendRemote = ReplicatedStorage:WaitForChild("Remotes", 5):WaitForChild("Send", 5)
end)

-- Prediction / Aim Helpers
RunService.Heartbeat:Connect(function()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local root = player.Character:FindFirstChild("HumanoidRootPart")
            local hum  = player.Character:FindFirstChild("Humanoid")
            if root and hum and hum.Health > 0 then
                positionHistory[player] = positionHistory[player] or {}
                table.insert(positionHistory[player], { time = os.clock(), pos = root.Position })
                if #positionHistory[player] > 10 then
                    table.remove(positionHistory[player], 1)
                end
            else positionHistory[player] = nil end
        end
    end
end)

Players.PlayerRemoving:Connect(function(player) positionHistory[player] = nil end)

local function calculateVelocity(player)
    local history = positionHistory[player]
    if not history or #history < 2 then return Vector3.new() end
    local sum, totalWeight = Vector3.new(), 0
    for i = 2, #history do
        local dt = history[i].time - history[i - 1].time
        if dt > 0 then
            local raw = (history[i].pos - history[i - 1].pos) / dt
            local clamped = Vector3.new(
                math.clamp(raw.X, -120, 120), math.clamp(raw.Y, -150, 150), math.clamp(raw.Z, -120, 120)
            )
            local weight = i
            sum = sum + clamped * weight
            totalWeight = totalWeight + weight
        end
    end
    if totalWeight == 0 then return Vector3.new() end
    return sum / totalWeight
end

local function predictPosition(part, root)
    if not part then return Vector3.zero end
    local parentModel = part.Parent
    local player = parentModel and Players:GetPlayerFromCharacter(parentModel)
    local velocity = (player and calculateVelocity(player)) or Vector3.zero
    local horizontal = Vector3.new(velocity.X, 0, velocity.Z) * 0.15 * 1.15
    local vertical = Vector3.new(0, math.clamp(velocity.Y * 0.15 * 0.30, -4, 4), 0)
    return part.Position + horizontal + vertical
end

local function getClosestTarget()
    local best, bestDist = nil, fovRadius
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local head = player.Character:FindFirstChild("Head")
            local hum  = player.Character:FindFirstChildOfClass("Humanoid")
            local root = player.Character:FindFirstChild("HumanoidRootPart")
            if head and hum and hum.Health > 0 and root then
                local pos, visible = Camera:WorldToViewportPoint(head.Position)
                if visible then
                    local screenPos = Vector2.new(pos.X, pos.Y)
                    local dist = (screenPos - center).Magnitude
                    if dist <= fovRadius and not table.find(excludedPlayers, player.Name) then
                        if dist < bestDist then bestDist = dist; best = player end
                    end
                end
            end
        end
    end
    return best
end

-- FOV Circle Drawing
local FovSegments = 16
local FovLines = {}
for i = 1, FovSegments do
    local Line = Drawing.new("Line")
    Line.Visible = false
    Line.Thickness = 1.5
    Line.Color = GREEN
    FovLines[i] = Line
end
local fovCircle = { Visible = false, _lines = FovLines, _segments = FovSegments }

-- Debug Bullet
local function SpawnDebugBullet(startPos, targetPos)
    local dist = (targetPos - startPos).Magnitude
    if dist < 0.1 then return end
    local beam = Instance.new("Part")
    beam.Anchored = true
    beam.CanCollide = false
    beam.Material = Enum.Material.Neon
    beam.Size = Vector3.new(0.03, 0.03, dist)
    beam.Color = GREEN
    beam.Transparency = 0.1
    beam.CFrame = CFrame.new(startPos, targetPos) * CFrame.new(0, 0, -dist / 2)
    beam.Parent = workspace
    task.delay(0.5, function() if beam then beam:Destroy() end end)
end

-- Auto Shoot System
local function getEquippedGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Handle") then
            return tool
        end
    end
    return nil
end

local function fireAutoShot()
    if not SendRemote then return end
    local target = getClosestTarget()
    if not target or not target.Character then return end
    local head = target.Character:FindFirstChild("Head")
    local root = target.Character:FindFirstChild("HumanoidRootPart")
    local hum  = target.Character:FindFirstChildOfClass("Humanoid")
    if not (head and root and hum and hum.Health > 0) then return end

    local tool = getEquippedGun()
    if not tool then return end

    local myHead = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
    local originPos = myHead and myHead.Position or (root.Position + Vector3.new(0, 50, 0))
    local aimPos = predictPosition(head, root)

    local lookCF = CFrame.new(originPos, aimPos)
    local rayResult = { [1] = { [1] = { Instance = head, Normal = Vector3.new(0, 1, 0), Position = aimPos }}}

    pcall(function()
        if Counter then Counter.event = (Counter.event or 0) + 1 end
        SendRemote:FireServer(Counter.event or 1, "shoot_gun", tool, lookCF, rayResult)
    end)
    SpawnDebugBullet(originPos, aimPos)
end

task.spawn(function()
    while true do
        if autoShootEnabled then
            pcall(fireAutoShot)
            task.wait(autoShootDelay)
        else
            task.wait(0.1)
        end
    end
end)

-- Silent Aim Hook
local originalFireServer
local _hookBusy = false
task.spawn(function()
if SendRemote and SendRemote.FireServer then
    pcall(function()
        originalFireServer = hookfunction(SendRemote.FireServer, function(self, ...)
            if self ~= SendRemote or _hookBusy then return originalFireServer(self, ...) end
            _hookBusy = true
            local args = { ... }
            if silentAimEnabled and args[2] == "shoot_gun" and aimTarget then
                local head = aimTarget.Character and aimTarget.Character:FindFirstChild("Head")
                local root = aimTarget.Character and aimTarget.Character:FindFirstChild("HumanoidRootPart")
                if head and root then
                    local aimPos = predictPosition(head, root)
                    local myHead = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
                    local originPos = myHead and myHead.Position or nil
                    args[4] = CFrame.new(originPos, aimPos)
                    args[5] = { [1] = { [1] = { Instance = head, Normal = Vector3.new(0, 1, 0), Position = aimPos }}}
                end
            end
            local _origResult = originalFireServer(self, unpack(args))
            if shotMultiplier > 1 and args[2] == "shoot_gun" then
                for _i = 1, shotMultiplier - 1 do
                    pcall(function()
                        if Counter then Counter.event = Counter.event + 1 end
                        originalFireServer(SendRemote, Counter.event, args[2], args[3], args[4], args[5])
                    end)
                end
            end
            _hookBusy = false
            return _origResult
        end)
    end)
end
end)

-- RenderStepped Update (FOV)
RunService.RenderStepped:Connect(function()
    pcall(function()
        aimTarget = silentAimEnabled and getClosestTarget() or nil
        if fovCircle then
            local Center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
            for i = 1, fovCircle._segments do
                local angle1 = math.rad((i - 1) * (360 / fovCircle._segments))
                local angle2 = math.rad(i * (360 / fovCircle._segments))
                fovCircle._lines[i].From = Center + Vector2.new(math.cos(angle1) * fovRadius, math.sin(angle1) * fovRadius)
                fovCircle._lines[i].To   = Center + Vector2.new(math.cos(angle2) * fovRadius, math.sin(angle2) * fovRadius)
                fovCircle._lines[i].Visible = silentAimEnabled
            end
        end
    end)
end)

-- WalkSpeed Loop
local jumpConn
local function setupCharacter(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    HRP = char:WaitForChild("HumanoidRootPart")
    if jumpConn then pcall(function() jumpConn:Disconnect() end) end
    jumpConn = RunService.RenderStepped:Connect(function(delta)
        if _G.WalkSpeedEnabled and Humanoid and HRP and HRP.Parent then
            if Humanoid.MoveDirection.Magnitude > 0 then
                HRP.CFrame = HRP.CFrame + (Humanoid.MoveDirection.Unit * _G.WalkSpeedMultiplier * delta * 60)
            end
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(setupCharacter)
if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end

-- Auto Pickup Items
RunService.Heartbeat:Connect(function()
    if not autoPickupEnabled or not HRP then return end
    local dropped = Workspace:FindFirstChild("DroppedItems")
    if not dropped then return end
    local now = tick()
    for _, model in ipairs(dropped:GetChildren()) do
        if model:IsA("Model") then
            local part = model:FindFirstChildWhichIsA("BasePart")
            if part then
                local dist = (HRP.Position - part.Position).Magnitude
                if dist <= 20 and (now - (itemPickupTrack[model] or 0)) >= 1 then
                    itemPickupTrack[model] = now
                    task.spawn(function() 
                        if Counter and Counter.func then
                            Counter.func = Counter.func + 1
                            pcall(function() ReplicatedStorage.Remotes.Get:InvokeServer(Counter.func, "pickup_dropped_item", model) end)
                        end
                    end)
                end
            end
        end
    end
end)

-- Anti-Lock
RunService.Heartbeat:Connect(function()
    if getEnv().Sky and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local root = LocalPlayer.Character.HumanoidRootPart
        local prevVel = root.Velocity
        local angle = math.rad(tick() * 1500 % 360)
        root.Velocity = Vector3.new(math.cos(angle) * 1500, math.random(280, 480), math.sin(angle) * 1500)
        RunService.RenderStepped:Wait()
        root.Velocity = prevVel
    end
end)

-- Gun Modifiers
getEnv().AccuracyValue = 1
getEnv().RecoilValue = 0
getEnv().Durability = 999999999
getEnv().AutoValue = true
getEnv().GunModsAutoApply = false

RunService.Heartbeat:Connect(function()
    if not getEnv().GunModsAutoApply then return end
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    for _, container in ipairs({char, backpack}) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    pcall(function()
                        tool:SetAttribute("accuracy", getEnv().AccuracyValue)
                        tool:SetAttribute("Recoil", getEnv().RecoilValue)
                        tool:SetAttribute("Durability", getEnv().Durability)
                        tool:SetAttribute("automatic", getEnv().AutoValue)
                    end)
                end
            end
        end
    end
end)

-- ESP Manager
local ESP = {}
local function createESP(player)
    if player == LocalPlayer then return end
    local highlight = Instance.new("Highlight")
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.FillColor = GREEN
    highlight.OutlineColor = GREEN
    highlight.Enabled = false
    highlight.Parent = game.CoreGui
    local name = Drawing.new("Text")
    name.Size = 12; name.Center = true; name.Outline = true
    name.Color = GREEN; name.Visible = false
    ESP[player] = {Highlight = highlight, Name = name}
end

for _, p in pairs(Players:GetPlayers()) do createESP(p) end
Players.PlayerAdded:Connect(createESP)

RunService.RenderStepped:Connect(function()
    for player, data in pairs(ESP) do
        if player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            local head = player.Character:FindFirstChild("Head")
            if hum and head and hum.Health > 0 then
                if highlightEnabled then
                    data.Highlight.Enabled = true
                    data.Highlight.Adornee = player.Character
                else 
                    data.Highlight.Enabled = false 
                end
                local posHead, visHead = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1, 0))
                if nameESPEnabled and visHead then
                    data.Name.Visible = true
                    data.Name.Text = player.Name
                    data.Name.Position = Vector2.new(posHead.X, posHead.Y)
                else 
                    data.Name.Visible = false 
                end
            else
                data.Highlight.Enabled = false
                data.Name.Visible = false
            end
        end
    end
end)


-- ============================================================
--  การผูกฟังก์ชันเข้ากับ Rayfield UI Elements
-- ============================================================

-- Tab: Combat
CombatTab:CreateToggle({
    Name = "Silent Aim",
    CurrentValue = false,
    Callback = function(Value)
        silentAimEnabled = Value
    end,
})

CombatTab:CreateSlider({
    Name = "FOV Radius",
    Range = {20, 800},
    Increment = 1,
    CurrentValue = 120,
    Callback = function(Value)
        fovRadius = Value
    end,
})

CombatTab:CreateSlider({
    Name = "Multiplier Shot",
    Range = {1, 5},
    Increment = 1,
    CurrentValue = 1,
    Callback = function(Value)
        shotMultiplier = Value
    end,
})

CombatTab:CreateToggle({
    Name = "Auto Shoot",
    CurrentValue = false,
    Callback = function(Value)
        autoShootEnabled = Value
    end,
})

CombatTab:CreateSlider({
    Name = "Auto Shoot Delay",
    Range = {0.01, 1},
    Increment = 0.01,
    CurrentValue = 0.05,
    Callback = function(Value)
        autoShootDelay = Value
    end,
})

-- Tab: Weapon
WeaponTab:CreateSlider({
    Name = "Accuracy Mod",
    Range = {0, 1},
    Increment = 0.01,
    CurrentValue = 1,
    Callback = function(Value)
        getEnv().AccuracyValue = Value
    end,
})

WeaponTab:CreateSlider({
    Name = "Recoil Mod",
    Range = {0, 10},
    Increment = 0.1,
    CurrentValue = 0,
    Callback = function(Value)
        getEnv().RecoilValue = Value
    end,
})

WeaponTab:CreateToggle({
    Name = "Auto Modify Guns",
    CurrentValue = false,
    Callback = function(Value)
        getEnv().GunModsAutoApply = Value
    end,
})

-- Tab: ESP
ESPTab:CreateToggle({
    Name = "Name ESP",
    CurrentValue = false,
    Callback = function(Value)
        nameESPEnabled = Value
    end,
})

ESPTab:CreateToggle({
    Name = "Highlight ESP",
    CurrentValue = false,
    Callback = function(Value)
        highlightEnabled = Value
    end,
})

-- Tab: Character
CharTab:CreateToggle({
    Name = "Walk Speed Hack",
    CurrentValue = false,
    Callback = function(Value)
        _G.WalkSpeedEnabled = Value
    end,
})

CharTab:CreateSlider({
    Name = "Speed Multiplier",
    Range = {0.01, 0.15},
    Increment = 0.01,
    CurrentValue = 0.10,
    Callback = function(Value)
        _G.WalkSpeedMultiplier = Value
    end,
})

CharTab:CreateToggle({
    Name = "Auto Pickup Items",
    CurrentValue = false,
    Callback = function(Value)
        autoPickupEnabled = Value
    end,
})

CharTab:CreateToggle({
    Name = "Anti Lock",
    CurrentValue = false,
    Callback = function(Value)
        getEnv().Sky = Value
    end,
})

Rayfield:LoadConfiguration()