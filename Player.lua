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
        Name = "HorizonFlyMiniPanel", Size = UDim2.fromOffset(268, 305),
        Position = UDim2.new(1, -12, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5), Visible = false,
        BackgroundColor3 = Color3.fromRGB(36, 33, 30), BorderSizePixel = 0,
        Active = true, ZIndex = 110
    }, gui)
    rounded(panel, 16)
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
    local drag = button("FlyDragHandle", "", UDim2.fromOffset(6, 5),
        UDim2.new(1, -54, 0, 35))
    drag.BackgroundTransparency = 1
    self.drag = drag
    local title = text("FlyTitle", "FLY", UDim2.fromOffset(14, 10),
        UDim2.fromOffset(130, 28), 16, Color3.fromRGB(240, 214, 184))
    title.Font = Enum.Font.GothamBold
    self.collapse = button("FlyCollapse", "−",
        UDim2.new(1, -42, 0, 8), UDim2.fromOffset(30, 28))
    self.collapse.TextSize = 20
    make("Frame", {
        Position = UDim2.fromOffset(12, 44),
        Size = UDim2.new(1, -24, 0, 1),
        BackgroundColor3 = Color3.fromRGB(80, 68, 56),
        BorderSizePixel = 0, ZIndex = 112
    }, panel)

    self.speedLabel = text("FlySpeedCaption", "Скорость полёта",
        UDim2.fromOffset(14, 52), UDim2.fromOffset(155, 25), 12)
    self.speedReadout = text("FlySpeedValue", "50",
        UDim2.new(1, -104, 0, 52), UDim2.fromOffset(90, 25), 13,
        Color3.fromRGB(234, 193, 143), Enum.TextXAlignment.Right)
    self.speedReadout.Font = Enum.Font.GothamBold

    self.slider = make("TextButton", {
        Name = "FlySlider", Text = "", Position = UDim2.fromOffset(16, 86),
        Size = UDim2.new(1, -32, 0, 24), BackgroundTransparency = 1,
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
    text("FlyMin", "0", UDim2.fromOffset(16, 113),
        UDim2.fromOffset(45, 17), 10, Color3.fromRGB(179, 166, 148))
    text("FlyMax", "1000", UDim2.new(1, -65, 0, 113),
        UDim2.fromOffset(50, 17), 10, Color3.fromRGB(179, 166, 148),
        Enum.TextXAlignment.Right)

    self.manualLabel = text("FlyManualCaption", "Ручной ввод скорости",
        UDim2.fromOffset(14, 140), UDim2.new(1, -28, 0, 20), 12)
    self.manualBox = make("TextBox", {
        Name = "FlyManualSpeed", Text = "50",
        PlaceholderText = "0 - 100000000",
        Size = UDim2.new(1, -28, 0, 34), Position = UDim2.fromOffset(14, 165),
        BackgroundColor3 = Color3.fromRGB(48, 43, 39),
        TextColor3 = Color3.fromRGB(242, 223, 205),
        PlaceholderColor3 = Color3.fromRGB(163, 150, 134),
        TextSize = 14, Font = Enum.Font.Gotham, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Center,
        BorderSizePixel = 0, ZIndex = 113
    }, panel)
    rounded(self.manualBox, 8)
    make("UIStroke", {Color = Color3.fromRGB(95, 77, 60),
        Thickness = 1}, self.manualBox)
    self.apply = button("FlyApply", "Применить",
        UDim2.fromOffset(14, 206), UDim2.new(1, -28, 0, 30))
    self.apply.BackgroundColor3 = Color3.fromRGB(87, 63, 44)
    self.up = button("FlyAscend", "↑  Вверх",
        UDim2.fromOffset(14, 250), UDim2.new(0.5, -18, 0, 37))
    self.down = button("FlyDescend", "↓  Вниз",
        UDim2.new(0.5, 4, 0, 250), UDim2.new(0.5, -18, 0, 37))
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

function Flight:_stopPhysics()
    if self.heartbeat then self.heartbeat:Disconnect(); self.heartbeat = nil end
    if self.velocity then self.velocity:Destroy(); self.velocity = nil end
    if self.gyro then self.gyro:Destroy(); self.gyro = nil end
    if self.humanoid and self.humanoid.Parent then
        self.humanoid.PlatformStand = self.oldPlatformStand
        self.humanoid.AutoRotate = self.oldAutoRotate
    end
    if self.root and self.root.Parent then
        self.root.AssemblyLinearVelocity = Vector3.zero
        self.root.AssemblyAngularVelocity = Vector3.zero
    end
    self.humanoid = nil
    self.root = nil
    self.upHeld = false
    self.downHeld = false
end

function Flight:_startPhysics()
    self:_stopPhysics()
    if not self.enabled then return end
    local char = self.context.player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return end
    self.humanoid = hum
    self.root = root
    self.oldPlatformStand = hum.PlatformStand
    self.oldAutoRotate = hum.AutoRotate
    hum.PlatformStand = true
    hum.AutoRotate = false
    local velocity = Instance.new("BodyVelocity")
    velocity.Name = "HorizonFlyVelocity"
    velocity.MaxForce = Vector3.new(1e12, 1e12, 1e12)
    velocity.P = 12500
    velocity.Velocity = Vector3.zero
    velocity.Parent = root
    self.velocity = velocity
    local gyro = Instance.new("BodyGyro")
    gyro.Name = "HorizonFlyGyro"
    gyro.MaxTorque = Vector3.new(1e12, 1e12, 1e12)
    gyro.P = 12000
    gyro.D = 600
    gyro.CFrame = root.CFrame
    gyro.Parent = root
    self.gyro = gyro

    self.heartbeat = self.runService.Heartbeat:Connect(function()
        if not self.enabled or not root.Parent or hum.Health <= 0 then
            self:_stopPhysics()
            return
        end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local look = camera.CFrame.LookVector
        local right = camera.CFrame.RightVector
        local fwd = Vector3.new(look.X, 0, look.Z)
        fwd = fwd.Magnitude > 0.001 and fwd.Unit or Vector3.new(0, 0, -1)
        local sideways = Vector3.new(right.X, 0, right.Z)
        sideways = sideways.Magnitude > 0.001 and sideways.Unit or Vector3.new(1, 0, 0)
        local move = hum.MoveDirection
        local horizontal = Vector3.new(move.X, 0, move.Z)
        local keys = self.moving
        local forwardAxis = (keys.W and 1 or 0) - (keys.S and 1 or 0)
        local rightAxis = (keys.D and 1 or 0) - (keys.A and 1 or 0)
        if forwardAxis ~= 0 or rightAxis ~= 0 then
            horizontal = fwd * forwardAxis + sideways * rightAxis
        end
        if horizontal.Magnitude > 1 then horizontal = horizontal.Unit end
        local vertical = ((self.upHeld or keys.Up) and 1 or 0)
            - ((self.downHeld or keys.Down) and 1 or 0)
        local direction = horizontal + Vector3.new(0, vertical, 0)
        if direction.Magnitude > 1 then direction = direction.Unit end
        velocity.Velocity = direction * self.speed
        gyro.CFrame = CFrame.lookAt(root.Position, root.Position + fwd)
    end)
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
            dragOrigin = input.Position
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
            local delta = input.Position - dragOrigin
            local camera = workspace.CurrentCamera
            if not camera then return end
            local view = camera.ViewportSize
            local size = self.panel.AbsoluteSize
            local x = math.clamp(dragPosition.X + delta.X, 4,
                math.max(4, view.X - size.X - 4))
            local y = math.clamp(dragPosition.Y + delta.Y, 4,
                math.max(4, view.Y - size.Y - 4))
            self.panel.Position = UDim2.fromOffset(x + size.X, y + size.Y * 0.5)
        end
    end)
    self:_listen(uis.InputEnded, function(input)
        if input == sliderPointer or input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding, sliderPointer = false, nil
        end
        if input == dragPointer or input.UserInputType == Enum.UserInputType.MouseButton1 then
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
    self:_listen(self.apply.Activated, function() self:_applyManual() end)
    self:_listen(self.manualBox.FocusLost, function(enter)
        if enter then self:_applyManual() end
    end)
    self:_listen(self.collapse.Activated, function()
        -- Hiding the panel does not disable flight.
        self.panel.Visible = false
    end)
    self:_listen(self.context.player.CharacterAdded, function(character)
        if not self.enabled then return end
        task.defer(function()
            if character:WaitForChild("HumanoidRootPart", 10)
                and self.enabled then self:_startPhysics() end
        end)
    end)
end

function Flight:enable()
    if self.enabled then
        self.panel.Visible = true
        return
    end
    self.enabled = true
    local camera = workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(600, 400)
    local target = math.max(0.3, math.min(1,
        (size.X - 18) / 268, (size.Y - 18) / 305))
    self.panel.Visible = true
    self.scale.Scale = target * 0.94
    self.context.tweens:Create(self.scale,
        TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Scale = target}):Play()
    self:_startPhysics()
end

function Flight:disable()
    self.enabled = false
    self:_stopPhysics()
    self.panel.Visible = false
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
