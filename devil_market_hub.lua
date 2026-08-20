--[[
  ============================================================
  DEVIL'S MARKET (Pasar Setan) — AUTO HUB v4 FINAL
  UI: 100% CUSTOM (buatan sendiri, tanpa library eksternal)
  Tanpa download, tanpa key system, tanpa webhook, tanpa obfuscation.

  FITUR:
    1. Auto-Farm / Auto-Cook / Auto-Serve / Auto-Buy
    2. Speed Boost (WalkSpeed & JumpPower slider)
    3. Anti-AFK
    4. Infinite Jump
    5. Teleport (dropdown + input custom + scan terdekat)
    6. ESP (highlight pemain & objek + colorpicker)
    7. SCAN dump nama objek ke konsol
  ============================================================
]]

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    ToolNames     = { "Hoe", "Watering", "Seed", "Sickle", "Axe", "Shovel", "Panen", "Tanam" },
    FarmKeywords  = { "farm", "plant", "plot", "tanam", "panen", "crop", "garden", "tani", "seed" },
    CookKeywords  = { "cook", "oven", "pot", "stove", "furnace", "station", "kitchen", "masak", "panci", "kompor" },
    ServeKeywords = { "serve", "customer", "ghost", "npc", "counter", "meja", "pelanggan", "layani", "order" },
    BuyKeywords   = { "buy", "upgrade", "shop", "market", "purchase", "beli", "toko" },
    TeleportSpots = { "stall", "kios", "dapur", "kitchen", "farm", "lahan", "pulau", "island", "home", "rumah", "spawn", "market" },
    ScanRadius    = 30,
    ActionDelay   = 0.35,
    LoopInterval  = 2.0,
    EspPlayerColor = Color3.fromRGB(255, 80, 80),
    EspItemColor   = Color3.fromRGB(80, 255, 120),
    DefaultWalkSpeed = 16,
    DefaultJumpPower = 50,
    AntiAfkInterval  = 45,
}

-- ============================================================
-- SERVICES & HELPERS
-- ============================================================
local Players = game:GetService("Players")
local LP       = Players.LocalPlayer
local UIS      = game:GetService("UserInputService")
local VIM      = game:GetService("VirtualInputManager")
local PlayerGui = LP:WaitForChild("PlayerGui")

local function char() return LP.Character end
local function hrp()
    local c = char(); return c and c:FindFirstChild("HumanoidRootPart")
end
local function hum()
    local c = char(); return c and c:FindFirstChildOfClass("Humanoid")
end

local firePrompt = fireproximityprompt

local function lower(s) return string.lower(tostring(s or "")) end
local function matchesKeywords(name, keywords)
    local n = lower(name)
    for _, kw in ipairs(keywords) do
        if n:find(lower(kw), 1, true) then return true end
    end
    return false
end

local function getPromptsInRadius(radius)
    local root = hrp()
    if not root then return {} end
    local found = {}
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                local par = obj.Parent
                if par and par:IsA("BasePart") and par.Position then
                    local dist = (par.Position - root.Position).Magnitude
                    if dist <= (radius or Config.ScanRadius) then
                        table.insert(found, { prompt = obj, part = par, dist = dist })
                    end
                end
            end
        end
    end)
    table.sort(found, function(a, b) return a.dist < b.dist end)
    return found
end

local function interactWith(prompt)
    if not prompt then return false end
    if firePrompt then return pcall(firePrompt, prompt) end
    local root = hrp()
    if not root then return false end
    local part = prompt.Parent
    if part and part:IsA("BasePart") and part.Position then
        local dist = (part.Position - root.Position).Magnitude
        local maxDist = prompt.MaxActivationDistance or 10
        if dist > maxDist then
            root.CFrame = part.CFrame * CFrame.new(0, 0, -(maxDist * 0.5))
            task.wait(0.1)
        end
        VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.06)
        VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        return true
    end
    return false
end

local function equipTool()
    local h = hum()
    if not h then return end
    if char() and char():FindFirstChildOfClass("Tool") then return end
    for _, name in ipairs(Config.ToolNames) do
        local tool = LP.Backpack:FindFirstChild(name)
        if tool then pcall(function() h:EquipTool(tool) end); return end
    end
end

local function findPartsByKeywords(keywords)
    local found = {}
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            pcall(function()
                if obj:IsA("BasePart") and obj.Position and matchesKeywords(obj.Name, keywords) then
                    table.insert(found, obj)
                end
            end)
        end
    end)
    return found
end

local function teleportTo(part)
    local root = hrp()
    if not root or not part then return false end
    local cf = part.CFrame
    if not cf then return false end
    root.CFrame = cf * CFrame.new(0, 4, 0)
    return true
end

-- ============================================================
-- STATE
-- ============================================================
local State = {
    autoFarm = false, autoCook = false, autoServe = false, autoBuy = false,
    speed = false, antiAfk = false, esp = false, infJump = false,
}
local activeLoops = {}

-- ============================================================
-- AUTO LOOPS
-- ============================================================
local function runAutoLoop(key, filterKeywords)
    if activeLoops[key] then return end
    activeLoops[key] = task.spawn(function()
        while State[key] do
            pcall(function()
                equipTool()
                local items = getPromptsInRadius(Config.ScanRadius)
                for _, item in ipairs(items) do
                    if not State[key] then break end
                    local pname = (item.prompt.Name or "") .. " " .. (item.part.Name or "")
                    if #filterKeywords == 0 or matchesKeywords(pname, filterKeywords) then
                        interactWith(item.prompt)
                        task.wait(Config.ActionDelay)
                    end
                end
            end)
            task.wait(Config.LoopInterval)
        end
        activeLoops[key] = nil
    end)
end

local function startAutoLoops()
    if State.autoFarm  then runAutoLoop("autoFarm",  Config.FarmKeywords)  end
    if State.autoCook  then runAutoLoop("autoCook",  Config.CookKeywords)  end
    if State.autoServe then runAutoLoop("autoServe", Config.ServeKeywords) end
    if State.autoBuy   then runAutoLoop("autoBuy",   Config.BuyKeywords)   end
end

-- ============================================================
-- MOVEMENT
-- ============================================================
local function applySpeed()
    local h = hum()
    if not h then return end
    h.WalkSpeed = Config.DefaultWalkSpeed
    h.JumpPower = Config.DefaultJumpPower
end

local function setSpeed(on)
    if on then
        task.spawn(function()
            while State.speed do
                pcall(applySpeed)
                task.wait(1.5)
            end
        end)
    else
        local h = hum()
        if h then h.WalkSpeed = 16; h.JumpPower = 50 end
    end
end

local function setAntiAfk(on)
    if on then
        task.spawn(function()
            while State.antiAfk do
                pcall(function()
                    VIM:SendMouseMoveEvent(1, 1, game)
                    task.wait(0.05)
                    VIM:SendMouseMoveEvent(0, 0, game)
                    local h = hum()
                    if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
                end)
                task.wait(Config.AntiAfkInterval)
            end
        end)
    end
end

local infJumpConn = nil
local function setInfJump(on)
    if infJumpConn then pcall(function() infJumpConn:Disconnect() end); infJumpConn = nil end
    if on then
        infJumpConn = UIS.JumpRequest:Connect(function()
            if State.infJump then
                local h = hum()
                if h and h.Health > 0 then h:ChangeState(Enum.HumanoidStateType.Jumping) end
            end
        end)
    end
end

-- ============================================================
-- ESP
-- ============================================================
local espHighlights = {}
local ESP_MAX_ITEMS = 40
local function clearESP()
    for _, hl in ipairs(espHighlights) do pcall(function() hl:Destroy() end) end
    espHighlights = {}
end

local function refreshESP()
    clearESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            pcall(function()
                local hl = Instance.new("Highlight")
                hl.FillColor = Config.EspPlayerColor
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl.FillTransparency = 0.65
                hl.OutlineTransparency = 0.2
                hl.Parent = p.Character
                table.insert(espHighlights, hl)
            end)
        end
    end
    local root = hrp()
    if root then
        local count = 0
        for _, obj in ipairs(workspace:GetDescendants()) do
            if count >= ESP_MAX_ITEMS then break end
            pcall(function()
                if obj:IsA("BasePart") and obj.Position
                and (obj:FindFirstChildOfClass("ProximityPrompt") or obj:FindFirstChildOfClass("ClickDetector")) then
                    local dist = (obj.Position - root.Position).Magnitude
                    if dist <= Config.ScanRadius * 3 then
                        local hl = Instance.new("Highlight")
                        hl.FillColor = Config.EspItemColor
                        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                        hl.FillTransparency = 0.55
                        hl.Parent = obj
                        table.insert(espHighlights, hl)
                        count = count + 1
                    end
                end
            end)
        end
    end
end

local function setESP(on)
    if on then
        refreshESP()
        task.spawn(function()
            while State.esp do
                task.wait(5); pcall(refreshESP)
            end
        end)
    else
        clearESP()
    end
end

-- ============================================================
-- SCANNER
-- ============================================================
local function runScanner()
    local root = hrp()
    local lines = { "===== SCAN RESULT =====" }
    local promptCount = 0
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                promptCount = promptCount + 1
                local par = obj.Parent
                if par and par:IsA("BasePart") and par.Position and root then
                    local dist = math.floor((par.Position - root.Position).Magnitude)
                    if dist <= Config.ScanRadius * 3 then
                        table.insert(lines, ("PROMPT: %s | parent: %s | dist: %d"):format(obj.Name, par.Name, dist))
                    end
                end
            end
        end
    end)
    table.insert(lines, "Total prompts: " .. promptCount)
    pcall(function()
        for _, tool in ipairs(LP.Backpack:GetChildren()) do
            table.insert(lines, "TOOL: " .. tool.Name)
        end
    end)
    local seen, count = {}, 0
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Position and root
            and (obj.Position - root.Position).Magnitude <= Config.ScanRadius then
                if not seen[obj.Name] then
                    seen[obj.Name] = true
                    table.insert(lines, "PART: " .. obj.Name)
                    count = count + 1
                end
                if count >= 20 then break end
            end
        end
    end)
    print(table.concat(lines, "\n"))
    notify("SCAN Selesai", promptCount .. " prompt ditemukan — lihat konsol (F9)", 7)
end

-- ============================================================
-- CUSTOM UI (murni Instance.new, tanpa library)
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DevilMarketHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local theme = {
    bg       = Color3.fromRGB(18, 19, 26),
    panel    = Color3.fromRGB(26, 28, 38),
    panel2   = Color3.fromRGB(34, 36, 48),
    accent   = Color3.fromRGB(255, 130, 60),
    accent2  = Color3.fromRGB(60, 140, 255),
    text     = Color3.fromRGB(235, 237, 245),
    subtext  = Color3.fromRGB(160, 164, 180),
    danger   = Color3.fromRGB(220, 70, 70),
    toggleOn = Color3.fromRGB(255, 130, 60),
    toggleOff= Color3.fromRGB(70, 72, 85),
}

local function new(className, props, children)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do obj[k] = v end
    for _, child in ipairs(children or {}) do
        child.Parent = obj
        -- Simpan referensi child bernama ke parent (seperti perilaku Roblox)
        if child.Name and child.Name ~= "" then
            obj[child.Name] = child
        end
    end
    return obj
end

-- Window
local Window = new("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(360, 540),
    Position = UDim2.new(0.5, -180, 0.5, -270),
    BackgroundColor3 = theme.bg,
    BorderSizePixel = 0,
    Active = true,
}, {
    new("UICorner", { CornerRadius = UDim.new(0, 10) }),
    new("UIStroke", { Color = theme.accent, Thickness = 1.5, Transparency = 0.4 }),
})
Window.Parent = ScreenGui  -- PENTING: window harus di-parent ke ScreenGui

-- Title bar (drag)
local CloseBtn = new("TextButton", {
    Name = "CloseBtn",
    Size = UDim2.fromOffset(22, 22),
    Position = UDim2.new(1, -28, 0, 6),
    BackgroundColor3 = Color3.fromRGB(60, 22, 22),
    Text = "X",
    TextColor3 = theme.danger,
    TextSize = 13,
    Font = Enum.Font.GothamBold,
})
local TitleBar = new("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundColor3 = theme.panel,
    BorderSizePixel = 0,
}, {
    new("UICorner", { CornerRadius = UDim.new(0, 10) }),
    new("Frame", {  -- bottom rounding fix
        Size = UDim2.new(1, 0, 0, 10),
        Position = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = theme.panel,
        BorderSizePixel = 0,
    }),
    new("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -70, 1, 0),
        BackgroundTransparency = 1,
        Text = "DEVIL'S MARKET AUTO HUB",
        TextColor3 = theme.text,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
    }),
    CloseBtn,
})
TitleBar.Parent = Window

-- Drag logic
local dragging, dragOffset = false, Vector2.new()
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragOffset = input.Position - Window.Position
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        Window.Position = UDim2.fromOffset(input.Position.X - dragOffset.X, input.Position.Y - dragOffset.Y)
    end
end)
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- Tab bar
local TabBar = new("Frame", {
    Name = "TabBar",
    Size = UDim2.new(1, 0, 0, 34),
    Position = UDim2.new(0, 0, 0, 34),
    BackgroundColor3 = theme.panel2,
    BorderSizePixel = 0,
})
TabBar.Parent = Window

local TabButtons = {}
local Pages = {}

local tabDefs = {
    { "FARM",  "Auto Farm/Cook/Serve/Buy" },
    { "MOVE",  "Speed, Anti-AFK, Inf Jump" },
    { "TELE",  "Teleport lokasi" },
    { "VIS",   "ESP & SCAN" },
}

local function buildTabs()
    local count = #tabDefs
    for i, def in ipairs(tabDefs) do
        local btn = new("TextButton", {
            Name = "Tab_" .. def[1],
            Size = UDim2.new(1 / count, -2, 1, -4),
            Position = UDim2.new((i - 1) / count, 2, 0, 2),
            BackgroundColor3 = i == 1 and theme.accent or theme.panel2,
            Text = def[1],
            TextColor3 = i == 1 and Color3.fromRGB(20, 20, 25) or theme.subtext,
            TextSize = 12,
            Font = Enum.Font.GothamBold,
            AutoButtonColor = false,
            BorderSizePixel = 0,
        })
        btn.Parent = TabBar
        local corner = new("UICorner", { CornerRadius = UDim.new(0, 6) })
        corner.Parent = btn
        TabButtons[i] = btn

        -- Page container
        local page = new("ScrollingFrame", {
            Name = "Page_" .. def[1],
            Size = UDim2.new(1, -12, 1, -12),
            Position = UDim2.new(0, 6, 0, 6),
            BackgroundTransparency = 1,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = i == 1,
        })
        page.Parent = Window
        Pages[i] = page

        btn.MouseButton1Click:Connect(function()
            for j, b in ipairs(TabButtons) do
                b.BackgroundColor3 = (j == i) and theme.accent or theme.panel2
                b.TextColor3 = (j == i) and Color3.fromRGB(20, 20, 25) or theme.subtext
            end
            for j, p in ipairs(Pages) do p.Visible = (j == i) end
        end)
    end
end

-- UI helpers
local function addSection(page, title)
    local sec = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.panel,
        BorderSizePixel = 0,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 8) }),
        new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("TextLabel", {
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = theme.accent,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
    })
    sec.Parent = page
    return sec
end

local function addParagraph_note(section, content)
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = content,
        TextColor3 = theme.subtext,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    })
    lbl.Parent = section
    return lbl
end

local function addToggle(section, text, stateKey, onChange)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
    }, {
        new("TextLabel", {
            Size = UDim2.new(1, -44, 1, 0),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = theme.text,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
    })
    row.Parent = section

    local btn = new("TextButton", {
        Size = UDim2.fromOffset(36, 20),
        Position = UDim2.new(1, -40, 0, 6),
        BackgroundColor3 = theme.toggleOff,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
    })
    btn.Parent = row

    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(0, 3, 0, 3),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
    })
    knob.Parent = btn

    local function refresh()
        local on = State[stateKey]
        btn.BackgroundColor3 = on and theme.toggleOn or theme.toggleOff
        knob.Position = on and UDim2.new(0, 19, 0, 3) or UDim2.new(0, 3, 0, 3)
    end
    btn.MouseButton1Click:Connect(function()
        State[stateKey] = not State[stateKey]
        refresh()
        if onChange then pcall(onChange, State[stateKey]) end
    end)
    refresh()
end

local function addSlider(section, text, min, max, default, suffix, onChanged)
    local value = default
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
    }, {
        new("TextLabel", {
            Name = "Lbl",
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Text = text .. ": " .. default .. (suffix or ""),
            TextColor3 = theme.text,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        new("Frame", {
            Name = "Bar",
            Size = UDim2.new(1, -20, 0, 6),
            Position = UDim2.new(0, 0, 0, 28),
            BackgroundColor3 = Color3.fromRGB(50, 52, 64),
            BorderSizePixel = 0,
        }, {
            new("UICorner", { CornerRadius = UDim.new(1, 0) }),
            new("Frame", {
                Name = "Fill",
                Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
                BackgroundColor3 = theme.accent,
                BorderSizePixel = 0,
            }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
        }),
    })
    row.Parent = section

    local bar = row.Bar
    local fill = bar.Fill
    local lbl = row.Lbl
    local dragging = false

    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        value = math.floor(min + rel * (max - min) + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text = text .. ": " .. value .. (suffix or "")
        if onChanged then pcall(onChanged, value) end
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            setFromX(input.Position.X)
        end
    end)
    return row
end

local function addButton(section, text, onClick)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = theme.panel2,
        Text = text,
        TextColor3 = theme.text,
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true,
        BorderSizePixel = 0,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 7) }) })
    btn.Parent = section
    btn.MouseButton1Click:Connect(function()
        pcall(onClick)
    end)
    return btn
end

local function addInput(section, text, placeholder, onSubmit)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundTransparency = 1,
    }, {
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = theme.text,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        new("TextBox", {
            Name = "Box",
            Size = UDim2.new(1, 0, 0, 30),
            Position = UDim2.new(0, 0, 0, 22),
            BackgroundColor3 = Color3.fromRGB(14, 15, 20),
            PlaceholderText = placeholder,
            PlaceholderColor3 = theme.subtext,
            Text = "",
            TextColor3 = theme.text,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            ClearTextOnFocus = false,
            BorderSizePixel = 0,
        }, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) }),
    })
    row.Parent = section
    row.Box.FocusLost:Connect(function(enterPressed)
        if enterPressed and onSubmit then pcall(onSubmit, row.Box.Text) end
    end)
    return row
end

local function addDropdown(section, text, options, defaultIdx, onChange)
    local selected = options[defaultIdx or 1]
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 60),
        BackgroundTransparency = 1,
    }, {
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = theme.text,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        new("TextButton", {
            Name = "Btn",
            Size = UDim2.new(1, 0, 0, 32),
            Position = UDim2.new(0, 0, 0, 22),
            BackgroundColor3 = Color3.fromRGB(14, 15, 20),
            Text = selected,
            TextColor3 = theme.text,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            AutoButtonColor = true,
            BorderSizePixel = 0,
        }, {
            new("UICorner", { CornerRadius = UDim.new(0, 6) }),
        }),
    })
    row.Parent = section

    local btn = row.Btn
    local listFrame = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.new(0, 0, 0, 58),
        BackgroundColor3 = Color3.fromRGB(14, 15, 20),
        Visible = false,
        BorderSizePixel = 0,
        ZIndex = 5,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 6) }),
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
    })
    listFrame.Parent = row

    local function close()
        listFrame.Visible = false
        listFrame.Size = UDim2.new(1, 0, 0, 0)
    end

    btn.MouseButton1Click:Connect(function()
        listFrame.Visible = not listFrame.Visible
        if listFrame.Visible then
            listFrame.Size = UDim2.new(1, 0, 0, #options * 30 + 8)
        else
            close()
        end
    end)

    for _, opt in ipairs(options) do
        local optBtn = new("TextButton", {
            Size = UDim2.new(1, -8, 0, 26),
            BackgroundColor3 = opt == selected and theme.accent or Color3.fromRGB(30, 32, 42),
            Text = opt,
            TextColor3 = opt == selected and Color3.fromRGB(20, 20, 25) or theme.text,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            AutoButtonColor = true,
            BorderSizePixel = 0,
        }, { new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
        optBtn.Parent = listFrame
        optBtn.MouseButton1Click:Connect(function()
            selected = opt
            btn.Text = opt
            close()
            if onChange then pcall(onChange, opt) end
        end)
    end

    return row, function(newOptions)
        for _, child in ipairs(listFrame:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        options = newOptions
        selected = newOptions[1]
        btn.Text = selected
    end
end

local function addColorPicker(section, text, defaultColor, onChanged)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
    }, {
        new("TextLabel", {
            Size = UDim2.new(1, -40, 1, 0),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = theme.text,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
    })
    row.Parent = section
    local swatch = new("TextButton", {
        Size = UDim2.fromOffset(32, 20),
        Position = UDim2.new(1, -36, 0, 6),
        BackgroundColor3 = defaultColor,
        Text = "",
        AutoButtonColor = true,
        BorderSizePixel = 0,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
    swatch.Parent = row
    -- siklus warna sederhana (merah -> hijau -> biru -> putih -> kembali)
    local cycle = {
        Color3.fromRGB(255, 80, 80),
        Color3.fromRGB(80, 255, 120),
        Color3.fromRGB(80, 140, 255),
        Color3.fromRGB(255, 255, 255),
        defaultColor,
    }
    local idx = 1
    for i, c in ipairs(cycle) do
        if c == defaultColor then idx = i break end
    end
    swatch.MouseButton1Click:Connect(function()
        idx = idx % #cycle + 1
        swatch.BackgroundColor3 = cycle[idx]
        if onChanged then pcall(onChanged, cycle[idx]) end
    end)
end

local function notify(title, content, duration)
    local n = new("Frame", {
        Size = UDim2.fromOffset(280, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(1, -290, 0, 10),
        BackgroundColor3 = theme.panel,
        BorderSizePixel = 0,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 8) }),
        new("UIStroke", { Color = theme.accent, Thickness = 1, Transparency = 0.5 }),
        new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = theme.accent,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = content or "",
            TextColor3 = theme.text,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
        }),
    })
    n.Parent = ScreenGui
    -- animasi masuk
    n.Position = UDim2.new(1, -290, 0, 10)
    task.delay(duration or 5, function()
        pcall(function() n:Destroy() end)
    end)
    -- susun notifikasi ke bawah
    task.wait(0.1)
    local y = 10
    for _, child in ipairs(ScreenGui:GetChildren()) do
        if child:IsA("Frame") and child ~= Window and child.Name ~= "Notification" then
            child.Position = UDim2.new(1, -290, 0, y)
            y = y + child.AbsoluteSize.Y + 10
        end
    end
end

-- ============================================================
-- BUILD UI
-- ============================================================
buildTabs()

-- ============ TAB 1: FARM ============
local secFarm = addSection(Pages[1], "AUTO FARMING")
addToggle(secFarm, "Auto-Farm (tanam & panen)", "autoFarm", function(v)
    startAutoLoops()
end)
addToggle(secFarm, "Auto-Cook (masak)", "autoCook", function(v)
    startAutoLoops()
end)
addToggle(secFarm, "Auto-Serve (layani pelanggan)", "autoServe", function(v)
    startAutoLoops()
end)
addToggle(secFarm, "Auto-Buy / Upgrade", "autoBuy", function(v)
    startAutoLoops()
end)
addParagraph_note(secFarm, "Keyword di Config (atas script) menentukan objek yang diinteraksi. Kalau tidak akurat, klik SCAN di tab VIS.")

-- ============ TAB 2: MOVE ============
local secMove = addSection(Pages[2], "SPEED & JUMP")
addToggle(secMove, "Speed Boost", "speed", setSpeed)
addSlider(secMove, "WalkSpeed", 16, 120, Config.DefaultWalkSpeed, "", function(v)
    Config.DefaultWalkSpeed = v
    if State.speed then pcall(applySpeed) end
end)
addSlider(secMove, "JumpPower", 50, 300, Config.DefaultJumpPower, "", function(v)
    Config.DefaultJumpPower = v
    if State.speed then pcall(applySpeed) end
end)
local secUtil = addSection(Pages[2], "UTILITY")
addToggle(secUtil, "Anti-AFK", "antiAfk", setAntiAfk)
addToggle(secUtil, "Infinite Jump", "infJump", setInfJump)

-- ============ TAB 3: TELE ============
local secTele = addSection(Pages[3], "TELEPORT")
local teleDropdown, teleSetOptions = addDropdown(secTele, "Pilih Lokasi", { "Stall", "Dapur", "Farm", "Pulau", "Spawn", "Market" }, 1, function(opt)
    if not opt then return end
    local part = findPartsByKeywords({ opt })[1]
    if part and teleportTo(part) then
        notify("Teleport", "Ke " .. opt, 4)
    else
        notify("Teleport", "Lokasi '" .. opt .. "' tidak ditemukan", 4)
    end
end)
addButton(secTele, "Scan & Teleport ke Lokasi Terdekat", function()
    local root = hrp()
    if not root then notify("Teleport", "Karakter belum spawn", 4) return end
    local parts = findPartsByKeywords(Config.TeleportSpots)
    local best, bestDist = nil, math.huge
    for _, p in ipairs(parts) do
        local d = (p.Position - root.Position).Magnitude
        if d < bestDist then best, bestDist = p, d end
    end
    if best then
        teleportTo(best)
        notify("Teleport", "Ke " .. best.Name .. " (" .. math.floor(bestDist) .. " stud)", 5)
    else
        notify("Teleport", "Tidak ada spot ditemukan di sekitar", 5)
    end
end)
addInput(secTele, "Teleport ke Nama Part", "cth: Stall, Dapur, Farm", function(v)
    if v and v ~= "" then
        local part = findPartsByKeywords({ v })[1]
        if part and teleportTo(part) then
            notify("Teleport", "Ke " .. v, 4)
        else
            notify("Teleport", "Part '" .. v .. "' tidak ditemukan", 4)
        end
    end
end)

-- ============ TAB 4: VIS ============
local secEsp = addSection(Pages[4], "ESP")
addToggle(secEsp, "ESP (highlight pemain & objek)", "esp", setESP)
addColorPicker(secEsp, "Warna ESP Pemain", Config.EspPlayerColor, function(c)
    Config.EspPlayerColor = c
    if State.esp then pcall(refreshESP) end
end)
addColorPicker(secEsp, "Warna ESP Objek", Config.EspItemColor, function(c)
    Config.EspItemColor = c
    if State.esp then pcall(refreshESP) end
end)
local secTool = addSection(Pages[4], "TOOLS")
addButton(secTool, "SCAN — Dump Nama Objek", runScanner)
addButton(secTool, "Respawn Karakter", function()
    local h = hum()
    if h then pcall(function() h.Health = 0 end) end
end)

-- ============================================================
-- FINALIZE
-- ============================================================

notify("Devil's Market Auto Hub", "Dimuat! Klik SCAN di tab VIS kalau auto-fiturnya tidak akurat.", 7)

print("[DevilMarketHub v4] Loaded — Custom UI (tanpa library eksternal)")

-- cleanup saat ScreenGui dihapus
ScreenGui.Destroying:Connect(function()
    -- matikan semua state (loop berhenti karena cek State[key])
    State.autoFarm = false; State.autoCook = false
    State.autoServe = false; State.autoBuy = false
    State.speed = false; State.antiAfk = false; State.esp = false
    if infJumpConn then pcall(function() infJumpConn:Disconnect() end) end
    clearESP()
    local h = hum()
    if h then h.WalkSpeed = 16; h.JumpPower = 50 end
end)
