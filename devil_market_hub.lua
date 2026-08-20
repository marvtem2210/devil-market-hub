--[[
  ============================================================
  DEVIL'S MARKET (Pasar Setan) — AUTO HUB v3
  UI: Rayfield (by Sirius) — render ke PlayerGui, executor-friendly
  Versi bersih: tanpa key system, tanpa webhook, tanpa obfuscation
  ============================================================
]]

-- ============================================================
-- CONFIG — sesuaikan keyword sesuai hasil SCAN
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

local function char() return LP.Character end
local function hrp()
    local c = char(); return c and c:FindFirstChild("HumanoidRootPart")
end
local function hum()
    local c = char(); return c and c:FindFirstChildOfClass("Humanoid")
end

local firePrompt = fireproximityprompt
local fireClick  = fireclickdetector

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
    local ok, _ = pcall(function()
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
    if not ok then
        found = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            pcall(function()
                if obj:IsA("ProximityPrompt") then
                    local par = obj.Parent
                    if par and par:IsA("BasePart") and par.Position then
                        local dist = (par.Position - root.Position).Magnitude
                        if dist <= (radius or Config.ScanRadius) then
                            table.insert(found, { prompt = obj, part = par, dist = dist })
                        end
                    end
                end
            end)
        end
    end
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
local isUnloaded  = false
local activeLoops = {}

-- ============================================================
-- AUTO LOOPS
-- ============================================================
local function runAutoLoop(key, filterKeywords)
    if activeLoops[key] then return end
    local thread = task.spawn(function()
        while State[key] and not isUnloaded do
            pcall(function()
                equipTool()
                local items = getPromptsInRadius(Config.ScanRadius)
                for _, item in ipairs(items) do
                    if not State[key] or isUnloaded then break end
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
    activeLoops[key] = thread
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
            while State.speed and not isUnloaded do
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
            while State.antiAfk and not isUnloaded do
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
            if State.infJump and not isUnloaded then
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
            while State.esp and not isUnloaded do
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
local function runScanner(Rayfield)
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
    Rayfield:Notify({ Title = "SCAN Selesai", Content = promptCount .. " prompt ditemukan — lihat konsol (F9)", Duration = 7 })
end

-- ============================================================
-- LOAD RAYFIELD
-- ============================================================
local Rayfield
local ok, err = pcall(function()
    Rayfield = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/x2Swiftz/UI-Library/main/Libraries/Rayfield%20-%20Library.lua"
    ))()
end)
if not ok then
    warn("[DevilMarketHub] Gagal load Rayfield: " .. tostring(err))
    return
end

-- ============================================================
-- WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name = "Devil's Market Auto Hub",
    LoadingTitle = "Devil's Market Auto Hub",
    LoadingSubtitle = "Clean | No Key | No Webhook",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "DevilMarketHub",
        FileName = "DevilMarket"
    },
    Discord = { Enabled = false },
    KeySystem = false
})

-- ============================================================
-- TABS
-- ============================================================
local Tabs = {
    Farm    = Window:CreateTab("Farming",  4483345998),
    Cook    = Window:CreateTab("Cooking",  4483345998),
    Serve   = Window:CreateTab("Serving",  4483345998),
    Shop    = Window:CreateTab("Shopping", 4483345998),
    Move    = Window:CreateTab("Movement", 4483345998),
    Tele    = Window:CreateTab("Teleport", 4483345998),
    Visual  = Window:CreateTab("Visual",   4483345998),
}

-- ============================================================
-- FARMING TAB
-- ============================================================
Tabs.Farm:CreateSection("Auto Farming")
Tabs.Farm:CreateToggle({
    Name = "Auto-Farm (tanam & panen)",
    CurrentValue = false,
    Flag = "AutoFarm",
    Callback = function(v)
        State.autoFarm = v
        startAutoLoops()
    end
})
Tabs.Farm:CreateParagraph({
    Title = "Tips",
    Content = "Kalau tidak jalan, klik SCAN di tab Visual → sesuaikan keyword di Config."
})

-- ============================================================
-- COOKING TAB
-- ============================================================
Tabs.Cook:CreateSection("Auto Cooking")
Tabs.Cook:CreateToggle({
    Name = "Auto-Cook (masak)",
    CurrentValue = false,
    Flag = "AutoCook",
    Callback = function(v)
        State.autoCook = v
        startAutoLoops()
    end
})

-- ============================================================
-- SERVING TAB
-- ============================================================
Tabs.Serve:CreateSection("Auto Serving")
Tabs.Serve:CreateToggle({
    Name = "Auto-Serve (layani pelanggan)",
    CurrentValue = false,
    Flag = "AutoServe",
    Callback = function(v)
        State.autoServe = v
        startAutoLoops()
    end
})

-- ============================================================
-- SHOPPING TAB
-- ============================================================
Tabs.Shop:CreateSection("Auto Shopping")
Tabs.Shop:CreateToggle({
    Name = "Auto-Buy / Upgrade",
    CurrentValue = false,
    Flag = "AutoBuy",
    Callback = function(v)
        State.autoBuy = v
        startAutoLoops()
    end
})
Tabs.Shop:CreateParagraph({
    Title = "Peringatan",
    Content = "Auto-Buy berinteraksi dengan prompt beli/upgrade terdekat. Matikan kalau takut salah beli."
})

-- ============================================================
-- MOVEMENT TAB
-- ============================================================
Tabs.Move:CreateSection("Speed & Jump")
Tabs.Move:CreateToggle({
    Name = "Speed Boost",
    CurrentValue = false,
    Flag = "SpeedBoost",
    Callback = function(v)
        State.speed = v
        setSpeed(v)
    end
})
Tabs.Move:CreateSlider({
    Name = "WalkSpeed",
    Range = { 16, 120 },
    Increment = 1,
    CurrentValue = Config.DefaultWalkSpeed,
    Flag = "WalkSpeed",
    Callback = function(v)
        Config.DefaultWalkSpeed = v
        if State.speed then pcall(applySpeed) end
    end
})
Tabs.Move:CreateSlider({
    Name = "JumpPower",
    Range = { 50, 300 },
    Increment = 5,
    CurrentValue = Config.DefaultJumpPower,
    Flag = "JumpPower",
    Callback = function(v)
        Config.DefaultJumpPower = v
        if State.speed then pcall(applySpeed) end
    end
})
Tabs.Move:CreateSection("Utility")
Tabs.Move:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Flag = "AntiAfk",
    Callback = function(v)
        State.antiAfk = v
        setAntiAfk(v)
    end
})
Tabs.Move:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Flag = "InfJump",
    Callback = function(v)
        State.infJump = v
        setInfJump(v)
    end
})

-- ============================================================
-- TELEPORT TAB
-- ============================================================
Tabs.Tele:CreateSection("Teleport Lokasi")
Tabs.Tele:CreateParagraph({
    Title = "Cara pakai",
    Content = "Pilih lokasi dari dropdown, atau ketik nama part di kolom Custom."
})

-- Dropdown statis dengan lokasi umum (bisa diganti hasil SCAN nanti)
local TeleDropdown = Tabs.Tele:CreateDropdown({
    Name = "Pilih Lokasi",
    Options = { "Stall", "Dapur", "Farm", "Pulau", "Spawn", "Market" },
    CurrentOption = { "Stall" },
    MultipleOptions = false,
    Flag = "TeleportSpot",
    Callback = function(option)
        if not option or option == "" then return end
        local part = findPartsByKeywords({ option })[1]
        if part and teleportTo(part) then
            Rayfield:Notify({ Title = "Teleport", Content = "Ke " .. option, Duration = 4 })
        else
            Rayfield:Notify({ Title = "Teleport", Content = "Lokasi '" .. option .. "' tidak ditemukan. Coba SCAN.", Duration = 5 })
        end
    end
})

Tabs.Tele:CreateButton({
    Name = "Scan & Cari Lokasi Terdekat",
    Callback = function()
        local root = hrp()
        if not root then
            Rayfield:Notify({ Title = "Teleport", Content = "Karakter belum spawn.", Duration = 4 })
            return
        end
        -- Cari part teleport terdekat yang cocok keyword
        local parts = findPartsByKeywords(Config.TeleportSpots)
        local best, bestDist = nil, math.huge
        for _, p in ipairs(parts) do
            local d = (p.Position - root.Position).Magnitude
            if d < bestDist then
                best, bestDist = p, d
            end
        end
        if best then
            teleportTo(best)
            Rayfield:Notify({
                Title = "Teleport",
                Content = "Ke " .. best.Name .. " (" .. math.floor(bestDist) .. " stud)",
                Duration = 5
            })
        else
            Rayfield:Notify({ Title = "Teleport", Content = "Tidak ada spot ditemukan di sekitar.", Duration = 5 })
        end
    end
})

Tabs.Tele:CreateSection("Custom")
Tabs.Tele:CreateInput({
    Name = "Teleport ke Nama Part",
    PlaceholderText = "cth: Stall, Dapur, Farm",
    RemoveTextAfterFocusLost = false,
    Callback = function(v)
        if v and v ~= "" then
            local part = findPartsByKeywords({ v })[1]
            if part and teleportTo(part) then
                Rayfield:Notify({ Title = "Teleport", Content = "Ke " .. v, Duration = 4 })
            else
                Rayfield:Notify({ Title = "Teleport", Content = "Part '" .. v .. "' tidak ditemukan", Duration = 5 })
            end
        end
    end
})

-- ============================================================
-- VISUAL TAB
-- ============================================================
Tabs.Visual:CreateSection("ESP")
Tabs.Visual:CreateToggle({
    Name = "ESP (highlight pemain & objek)",
    CurrentValue = false,
    Flag = "ESP",
    Callback = function(v)
        State.esp = v
        setESP(v)
    end
})
Tabs.Visual:CreateColorPicker({
    Name = "Warna ESP Pemain",
    Color = Config.EspPlayerColor,
    Flag = "EspPlayerColor",
    Callback = function(c)
        Config.EspPlayerColor = c
        if State.esp then pcall(refreshESP) end
    end
})
Tabs.Visual:CreateColorPicker({
    Name = "Warna ESP Objek",
    Color = Config.EspItemColor,
    Flag = "EspItemColor",
    Callback = function(c)
        Config.EspItemColor = c
        if State.esp then pcall(refreshESP) end
    end
})
Tabs.Visual:CreateSection("Tools")
Tabs.Visual:CreateButton({
    Name = "SCAN — Dump Nama Objek ke Konsol",
    Callback = function() runScanner(Rayfield) end
})
Tabs.Visual:CreateButton({
    Name = "Respawn Karakter",
    Callback = function()
        local h = hum()
        if h then pcall(function() h.Health = 0 end) end
    end
})

-- ============================================================
-- NOTIFIKASI AWAL
-- ============================================================
Rayfield:Notify({
    Title = "Devil's Market Auto Hub",
    Content = "Dimuat! Klik SCAN di tab Visual kalau auto-fiturnya tidak akurat.",
    Duration = 7
})

print("[DevilMarketHub v3] Loaded — Rayfield UI")
