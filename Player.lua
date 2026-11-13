-- HORIZON / Functions / Player.lua
-- Player movement features. The main HORIZON UI is never created here.
-- Usage: local factory = loadstring(game:HttpGet(URL))(); local flight = factory.new(context)

local Flight = {}
Flight.__index = Flight

local function make(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    return object
end

local function rounded(parent, amount)
    make("UICorner", {CornerRadius = UDim.new(0, amount)}, parent)
end

function Flight.new(context)
    assert(type(context) == "table" and context.screenGui and context.player
        and context.userInput and context.tweens, "HORIZON Fly: invalid context")
    local self = setmetatable({}, Flight)
    self.context = context
    self.enabled = false
    self.flightActive = false
    self.noclipEnabled = false
    self.noclipConnection = nil
    -- Weak keys avoid retaining obsolete character parts after respawn.
    self.noclipOriginals = setmetatable({}, {__mode = "k"})
    self.speed = 50
    self.sliderValue = 50
    self.manualValue = 50
    self.connections = {}
    self.moving = {W = false, A = false, S = false, D = false, Up = false, Down = false}
    self.upHeld = false
    self.downHeld = false
    self.runService = game:GetService("RunService")
    self:_build()
    self:_bind()
    return self
end

function Flight:_listen(signal, callback)
    local c = signal:Connect(callback)
    table.insert(self.connections, c)
    return c
end

function Flight:_build()
    local gui = self.context.screenGui
    local panel = make("Frame", {
        Name = "HorizonFlyMiniPanel", Size = UDim2.fromOffset(235, 260),
        Position = UDim2.new(1, -12, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5), Visible = false,
        BackgroundColor3 = Color3.fromRGB(36, 33, 30), BorderSizePixel = 0,
        Active = true, ZIndex = 110
    }, gui)
    rounded(panel, 14)
    make("UIStroke", {Color = Color3.fromRGB(106, 85, 64),
        Thickness = 1}, panel)
    self.panel = panel
    self.scale = make("UIScale", {Scale = 1}, panel)

    local function text(name, value, position, size, fontSize, color, alignment)
        return make("TextLabel", {
            Name = name, Text = value, Position = position, Size = size,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Font = Enum.Font.Gotham, TextSize = fontSize,
            TextColor3 = color or Color3.fromRGB(235, 219, 199),
            TextXAlignment = alignment or Enum.TextXAlignment.Left,
            ZIndex = 112, Active = false
        }, panel)
    end
    local function button(name, value, position, size)
        local b = make("TextButton", {
            Name = name, Text = value, Size = size, Position = position,
            Font = Enum.Font.GothamMedium, TextSize = 12,
            TextColor3 = Color3.fromRGB(239, 216, 188),
            BackgroundColor3 = Color3.fromRGB(60, 49, 40),
            BorderSizePixel = 0, AutoButtonColor = true,
            ZIndex = 113, Active = true
        }, panel)
        rounded(b, 8)
        return b
    end
    local drag = button("FlyDragHandle", "", UDim2.fromOffset(0, 0),
        UDim2.new(1, -38, 0, 37))
    drag.BackgroundTransparency = 1
    drag.ZIndex = 113
    self.drag = drag
    local title = text("FlyTitle", "FLY", UDim2.fromOffset(12, 6),
        UDim2.fromOffset(130, 26), 15, Color3.fromRGB(240, 214, 184))
    title.Font = Enum.Font.GothamBold
    title.ZIndex = 114
    self.collapse = button("FlyCollapse", "−",
        UDim2.new(1, -37, 0, 5), UDim2.fromOffset(28, 27))
    self.collapse.TextSize = 20
    make("Frame", {
        Position = UDim2.fromOffset(10, 37),
        Size = UDim2.new(1, -20, 0, 1),
        BackgroundColor3 = Color3.fromRGB(80, 68, 56),
        BorderSizePixel = 0, ZIndex = 112
    }, panel)

    self.speedLabel = text("FlySpeedCaption", "Скорость полёта",
        UDim2.fromOffset(12, 40), UDim2.fromOffset(135, 21), 11)
    self.speedReadout = text("FlySpeedValue", "50",
        UDim2.new(1, -92, 0, 40), UDim2.fromOffset(80, 21), 11,
        Color3.fromRGB(234, 193, 143), Enum.TextXAlignment.Right)
    self.speedReadout.Font = Enum.Font.GothamBold

    self.slider = make("TextButton", {
        Name = "FlySlider", Text = "", Position = UDim2.fromOffset(12, 65),
        Size = UDim2.new(1, -24, 0, 23), BackgroundTransparency = 1,
        AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 113
    }, panel)
    local rail = make("Frame", {
        Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 0.5, -3), BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(84, 72, 60), ZIndex = 113,
        Active = false
    }, self.slider)
    rounded(rail, 3)
    self.fill = make("Frame", {
        Size = UDim2.fromScale(0.05, 1),
        BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(204, 159, 111),
        Active = false, ZIndex = 114
    }, rail)
    rounded(self.fill, 3)
    self.knob = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.05, 0.5), Size = UDim2.fromOffset(17, 17),
        BackgroundColor3 = Color3.fromRGB(227, 190, 151),
        BorderSizePixel = 0, Active = false, ZIndex = 115
    }, self.slider)
    rounded(self.knob, 9)
    text("FlyMin", "0", UDim2.fromOffset(12, 89),
        UDim2.fromOffset(45, 17), 10, Color3.fromRGB(179, 166, 148))
    text("FlyMax", "1000", UDim2.new(1, -57, 0, 89),
        UDim2.fromOffset(50, 17), 10, Color3.fromRGB(179, 166, 148),
        Enum.TextXAlignment.Right)

    self.manualPanel = make("Frame", {
        Name = "FlyManualPanel", Position = UDim2.fromOffset(10, 106),
        Size = UDim2.new(1, -20, 0, 101),
        BackgroundColor3 = Color3.fromRGB(48, 43, 39),
        BorderSizePixel = 0, ZIndex = 111
    }, panel)
    rounded(self.manualPanel, 9)
    self.manualLabel = text("FlyManualCaption", "Ручной ввод скорости",
        UDim2.fromOffset(19, 109), UDim2.new(1, -38, 0, 20), 11)
    self.manualBox = make("TextBox", {
        Name = "FlyManualSpeed", Text = "50",
        PlaceholderText = "0 - 100000000",
        Size = UDim2.new(1, -38, 0, 29), Position = UDim2.fromOffset(19, 131),
        BackgroundColor3 = Color3.fromRGB(35, 32, 29),
        TextColor3 = Color3.fromRGB(242, 223, 205),
        PlaceholderColor3 = Color3.fromRGB(163, 150, 134),
        TextSize = 13, Font = Enum.Font.Gotham, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Center,
        BorderSizePixel = 0, ZIndex = 113
    }, panel)
    rounded(self.manualBox, 8)
    make("UIStroke", {Color = Color3.fromRGB(95, 77, 60),
        Thickness = 1}, self.manualBox)
    self.power = button("FlyPower", "Выключить Fly",
        UDim2.fromOffset(19, 166), UDim2.new(1, -38, 0, 32))
    self.power.BackgroundColor3 = Color3.fromRGB(104, 57, 53)
    self.up = button("FlyAscend", "↑  Вверх",
        UDim2.fromOffset(10, 216), UDim2.new(0.5, -15, 0, 35))
    self.down = button("FlyDescend", "↓  Вниз",
        UDim2.new(0.5, 5, 0, 216), UDim2.new(0.5, -15, 0, 35))
end

function Flight:_readSlider(x)
    local width = self.slider.AbsoluteSize.X
    if width <= 0 then return end
    self.sliderValue = math.floor(math.clamp(
        (x - self.slider.AbsolutePosition.X) / width, 0, 1) * 1000 + 0.5)
    self.speed = self.sliderValue
    -- Never overwrite manualBox.Text while the slider is moving.
    self.speedReadout.Text = tostring(self.speed)
    local fraction = self.sliderValue / 1000
    self.fill.Size = UDim2.fromScale(fraction, 1)
    self.knob.Position = UDim2.fromScale(fraction, 0.5)
end

function Flight:_applyManual()
    local candidate = self.manualBox.Text:match("^%s*(%d+)%s*$")
    local value = candidate and tonumber(candidate)
    if not value or value > 100000000 then
        self.manualBox.TextColor3 = Color3.fromRGB(248, 128, 128)
        return
    end
    self.manualValue = value
    self.manualBox.Text = tostring(value)
    self.manualBox.TextColor3 = Color3.fromRGB(242, 223, 205)
    self.speed = value
    self.speedReadout.Text = tostring(value)
end

-- The main Fly switch and the mini-panel button request flight independently
-- of whether a valid character has finished loading.
function Flight:_physicsReady()
    local character = self.context.player.Character
    return self.heartbeat ~= nil
        and character ~= nil
        and self.humanoid ~= nil and self.humanoid.Parent == character
        and self.humanoid.Health > 0
        and self.root ~= nil and self.root.Parent == character
        and self.velocity ~= nil and self.velocity.Parent == self.root
        and self.gyro ~= nil and self.gyro.Parent == self.root
end

function Flight:_stopPhysics()
    if self.heartbeat then self.heartbeat:Disconnect(); self.heartbeat = nil end
    if self.velocity then self.velocity:Destroy(); self.velocity = nil end
    if self.gyro then self.gyro:Destroy(); self.gyro = nil end
    if self.humanoid and self.humanoid.Parent then
        self.humanoid.PlatformStand = self.oldPlatformStand == true
        self.humanoid.AutoRotate = self.oldAutoRotate ~= false
        if not self.oldPlatformStand and self.humanoid.Health > 0 then
            pcall(function()
                self.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
    end
    if self.root and self.root.Parent then
        self.root.AssemblyLinearVelocity = Vector3.zero
        self.root.AssemblyAngularVelocity = Vector3.zero
    end
    self.humanoid = nil
    self.root = nil
    self.upHeld = false
    self.downHeld = false
    self.smoothedVelocity = Vector3.zero
    if self.power then self:_refreshPower() end
end

-- Roblox has two generations of built-in controls. Resolve asynchronously:
-- requires must never suspend the live physics callback or HORIZON startup.
function Flight:_resolveControls()
    if self.controls or (self.moveAction and self.moveAction.Parent) then return end
    if self.controlsResolving or os.clock() < (self.nextControlResolve or 0) then return end
    self.controlsResolving = true
    self.nextControlResolve = os.clock() + 2
    task.spawn(function()
        local ok, err = pcall(function()
            local scripts = self.context.player:FindFirstChild("PlayerScripts")
            local playerModule = scripts and scripts:FindFirstChild("PlayerModule")
            local starterModule = game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
            -- In the 2026 Input Action System the old GetControls may be absent.
            for _, module in ipairs({playerModule, starterModule}) do
                if module then
                    local contexts = module:FindFirstChild("InputContexts")
                    local moveAction = contexts and contexts:FindFirstChild("MoveAction", true)
                    if moveAction and moveAction:IsA("InputAction") then
                        self.moveAction = moveAction
                        return
                    end
                end
            end
            if playerModule then
                local required, api = pcall(require, playerModule)
                if required and api then
                    local got, controls = pcall(function() return api:GetControls() end)
                    if got and controls and type(controls.GetMoveVector) == "function" then
                        self.controls = controls
                        return
                    end
                end
                local oldModule = playerModule:FindFirstChild("ControlModule")
                if oldModule then
                    local loaded, controls = pcall(require, oldModule)
                    if loaded and controls
                        and type(controls.GetMoveVector) == "function" then
                        self.controls = controls
                    end
                end
            end
        end)
        self.controlsResolving = false
        if not ok and not self.warnedControls then
            self.warnedControls = true
            warn("[HORIZON Fly] Control resolution: " .. tostring(err))
        end
    end)
end

function Flight:_getMoveVector()
    self:_resolveControls()
    if self.moveAction and self.moveAction.Parent then
        local ok, vector = pcall(function() return self.moveAction:GetState() end)
        if ok and typeof(vector) == "Vector3" then return vector end
        if ok and typeof(vector) == "Vector2" then
            -- MoveAction's Up is +Y; the legacy fly controller's forward is -Z.
            return Vector3.new(vector.X, 0, -vector.Y)
        end
    end
    if self.controls then
        local ok, vector = pcall(function()
            return self.controls:GetMoveVector()
        end)
        if ok and typeof(vector) == "Vector3" then return vector end
        if ok and typeof(vector) == "Vector2" then
            return Vector3.new(vector.X, 0, -vector.Y)
        end
    end
    return nil
end

function Flight:_startPhysics()
    self:_stopPhysics()
    if not self.enabled or not self.flightActive then return false end
    local character = self.context.player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return false end

    -- Remove orphaned constraints left by a previous HORIZON instance.
    for _, name in ipairs({"HorizonFlyVelocity", "HorizonFlyGyro"}) do
        local stale = root:FindFirstChild(name)
        if stale then stale:Destroy() end
    end

    self.humanoid, self.root = humanoid, root
    self.oldPlatformStand = humanoid.PlatformStand
    self.oldAutoRotate = humanoid.AutoRotate
    humanoid.PlatformStand = true
    humanoid.AutoRotate = false

    local velocity = Instance.new("BodyVelocity")
    velocity.Name = "HorizonFlyVelocity"
    velocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    velocity.P = 1250
    velocity.Velocity = Vector3.zero
    velocity.Parent = root
    self.velocity = velocity

    local gyro = Instance.new("BodyGyro")
    gyro.Name = "HorizonFlyGyro"
    gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    gyro.P = 1000
    gyro.D = 50
    gyro.CFrame = root.CFrame
    gyro.Parent = root
    self.gyro = gyro
    self.smoothedVelocity = Vector3.zero

    self.heartbeat = self.runService.Heartbeat:Connect(function(dt)
        if not self.enabled or not self.flightActive or not self:_physicsReady() then
            self:_stopPhysics()
            return
        end
        local camera = workspace.CurrentCamera
        if not camera then
            velocity.Velocity = Vector3.zero
            return
        end

        local keys = self.moving
        local keyX = (keys.D and 1 or 0) - (keys.A and 1 or 0)
        local keyZ = (keys.S and 1 or 0) - (keys.W and 1 or 0)
        local input = self:_getMoveVector()
        local x = input and input.X or keyX
        local z = input and input.Z or keyZ
        if input and input.Magnitude <= 0.01 and (keyX ~= 0 or keyZ ~= 0) then
            x, z = keyX, keyZ
        end

        local direction = camera.CFrame.RightVector * x
            - camera.CFrame.LookVector * z
        -- Use world-space fallback only when no working module/keys are moving.
        if math.abs(x) < 0.01 and math.abs(z) < 0.01 then
            local move = humanoid.MoveDirection
            if move.Magnitude > 0.01 then
                direction = move
            end
        end
        local vertical = ((self.upHeld or keys.Up) and 1 or 0)
            - ((self.downHeld or keys.Down) and 1 or 0)
        direction = direction + Vector3.new(0, vertical, 0)
        if direction.Magnitude > 1 then direction = direction.Unit end

        -- Responsive easing rather than snapping the avatar to a hard velocity.
        local target = direction * self.speed
        local alpha = math.clamp((dt or 1 / 60) * 12, 0, 1)
        self.smoothedVelocity = self.smoothedVelocity:Lerp(target, alpha)
        velocity.Velocity = self.smoothedVelocity
        -- Match the reference Fly: follow the camera with gentler BodyGyro.
        gyro.CFrame = camera.CFrame
    end)
    self:_refreshPower()
    return true
end

-- Retry on delayed character loading, respawn and destroyed constraints.
-- A failed first attempt must never permanently strand an enabled toggle.
function Flight:_ensurePhysics()
    if not self.enabled or not self.flightActive then return end
    if self:_physicsReady() then
        if not self.humanoid.PlatformStand then
            self.humanoid.PlatformStand = true
        end
        return
    end
    local ok, err = pcall(function() self:_startPhysics() end)
    if not ok then
        self:_stopPhysics()
        if os.clock() >= (self.nextPhysicsWarning or 0) then
            warn("[HORIZON Fly] Retry after physics error: " .. tostring(err))
            self.nextPhysicsWarning = os.clock() + 5
        end
    end
end

function Flight:_bind()
    local uis = self.context.userInput
    local dragging, dragPointer, dragOrigin, dragPosition = false, nil, nil, nil
    local sliding, sliderPointer = false, nil

    self:_listen(self.slider.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            sliding, sliderPointer = true, input
            self:_readSlider(input.Position.X)
        end
    end)
    self:_listen(self.drag.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragPointer = true, input
            dragOrigin = Vector2.new(input.Position.X, input.Position.Y)
            dragPosition = self.panel.AbsolutePosition
        end
    end)
    self:_listen(uis.InputChanged, function(input)
        if sliding and (input == sliderPointer
            or (sliderPointer and sliderPointer.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            self:_readSlider(input.Position.X)
        end
        if dragging and dragOrigin and dragPosition
            and (input == dragPointer
                or (dragPointer and dragPointer.UserInputType == Enum.UserInputType.MouseButton1
                    and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - dragOrigin
            local parent = self.panel.Parent
            if not parent then return end
            local view = parent.AbsoluteSize
            local size = self.panel.AbsoluteSize
            local x = math.clamp(dragPosition.X + delta.X, 2,
                math.max(2, view.X - size.X - 2))
            local y = math.clamp(dragPosition.Y + delta.Y, 2,
                math.max(2, view.Y - size.Y - 2))
            self.panel.Position = UDim2.fromOffset(x + size.X, y + size.Y * 0.5)
        end
    end)
    self:_listen(uis.InputEnded, function(input)
        if input == sliderPointer
            or (sliderPointer and sliderPointer.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseButton1) then
            sliding, sliderPointer = false, nil
        end
        if input == dragPointer
            or (dragPointer and dragPointer.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseButton1) then
            dragging, dragPointer = false, nil
        end
        local keys = self.moving
        if input.KeyCode == Enum.KeyCode.W then keys.W = false
        elseif input.KeyCode == Enum.KeyCode.A then keys.A = false
        elseif input.KeyCode == Enum.KeyCode.S then keys.S = false
        elseif input.KeyCode == Enum.KeyCode.D then keys.D = false
        elseif input.KeyCode == Enum.KeyCode.Space then keys.Up = false
        elseif input.KeyCode == Enum.KeyCode.LeftControl then keys.Down = false
        end
    end)
    self:_listen(uis.InputBegan, function(input, processed)
        if processed or uis:GetFocusedTextBox() then return end
        local keys = self.moving
        if input.KeyCode == Enum.KeyCode.W then keys.W = true
        elseif input.KeyCode == Enum.KeyCode.A then keys.A = true
        elseif input.KeyCode == Enum.KeyCode.S then keys.S = true
        elseif input.KeyCode == Enum.KeyCode.D then keys.D = true
        elseif input.KeyCode == Enum.KeyCode.Space then keys.Up = true
        elseif input.KeyCode == Enum.KeyCode.LeftControl then keys.Down = true
        end
    end)
    local function hold(button, positive)
        self:_listen(button.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                if positive then self.upHeld = true else self.downHeld = true end
            end
        end)
        self:_listen(button.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                if positive then self.upHeld = false else self.downHeld = false end
            end
        end)
    end
    hold(self.up, true)
    hold(self.down, false)
    self:_listen(self.power.Activated, function()
        if self.flightActive then self:pauseFlight()
        else self:resumeFlight() end
    end)
    self:_listen(self.manualBox.FocusLost, function(enter)
        if enter then self:_applyManual() end
    end)
    self:_listen(self.collapse.Activated, function()
        -- Hiding the panel does not disable flight.
        self.panel.Visible = false
    end)
    self:_listen(self.context.player.CharacterAdded, function(character)
        if not self.enabled or not self.flightActive then return end
        task.defer(function()
            if character:WaitForChild("HumanoidRootPart", 10)
                and self.enabled and self.flightActive then self:_ensurePhysics() end
        end)
    end)
    -- Lightweight 5 Hz watchdog; does nothing expensive while Fly is disabled.
    local elapsed = 0
    self:_listen(self.runService.Heartbeat, function(dt)
        if not self.enabled or not self.flightActive then return end
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        self:_ensurePhysics()
    end)
end

function Flight:_refreshPower()
    local requested = self.enabled and self.flightActive
    self.power.Text = requested and "Выключить Fly" or "Включить Fly"
    -- Amber means requested but waiting for a valid character/physics.
    self.power.BackgroundColor3 = requested
        and (self:_physicsReady() and Color3.fromRGB(104, 57, 53)
            or Color3.fromRGB(130, 94, 47))
        or Color3.fromRGB(65, 106, 69)
end

function Flight:pauseFlight()
    self.flightActive = false
    self:_stopPhysics()
    self:_refreshPower()
end

function Flight:resumeFlight()
    if not self.enabled then return end
    self.flightActive = true
    self:_ensurePhysics()
    self:_refreshPower()
end

function Flight:enable()
    if self.enabled then
        self.panel.Visible = true
        if self.flightActive then self:_ensurePhysics() end
        self:_refreshPower()
        return
    end
    self.enabled = true
    self.flightActive = true
    local camera = workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(600, 400)
    local target = math.max(0.3, math.min(1,
        (size.X - 12) / 235, (size.Y - 12) / 260))
    self.panel.Visible = true
    self.scale.Scale = target * 0.94
    self.context.tweens:Create(self.scale,
        TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Scale = target}):Play()
    self:_ensurePhysics()
    self:_refreshPower()
end

function Flight:disable()
    self.enabled = false
    self.flightActive = false
    self:_stopPhysics()
    self.panel.Visible = false
    self:_refreshPower()
end

-- Noclip uses the same idea as the user's Stepped loop: collisions are
-- disabled again before simulation, because some games reset CanCollide.
-- Each original value is remembered once and restored when switched off.
function Flight:enableNoclip()
    if self.noclipEnabled then return end
    self.noclipEnabled = true
    self.noclipOriginals = setmetatable({}, {__mode = "k"})

    local function enforce()
        if not self.noclipEnabled then return end
        local char = self.context.player.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if self.noclipOriginals[part] == nil then
                    -- Lua tables cannot store nil, so use a boolean wrapper.
                    self.noclipOriginals[part] = {original = part.CanCollide}
                end
                if part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end

    enforce()
    -- PreSimulation (or the older Stepped event) avoids the wait(0.21)
    -- that could let collisions return between physical updates.
    local event = self.runService.PreSimulation or self.runService.Stepped
    self.noclipConnection = event:Connect(enforce)
end

function Flight:disableNoclip()
    self.noclipEnabled = false
    if self.noclipConnection then
        self.noclipConnection:Disconnect()
        self.noclipConnection = nil
    end
    for part, info in pairs(self.noclipOriginals) do
        if part and part.Parent and info then
            pcall(function() part.CanCollide = info.original end)
        end
    end
    self.noclipOriginals = setmetatable({}, {__mode = "k"})
end

function Flight:destroy()
    self:disableNoclip()
    self:disable()
    for _, connection in ipairs(self.connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(self.connections)
    if self.panel then self.panel:Destroy(); self.panel = nil end
end

return {
    new = function(context)
        return Flight.new(context)
    end
}
