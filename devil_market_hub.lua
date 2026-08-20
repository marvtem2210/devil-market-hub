--[[
  ============================================================
  DEVIL'S MARKET (Pasar Setan) — AUTO HUB v2.1 (FIXED)
  UI: FluentUI (dawid-scripts)
  Versi bersih: tanpa key system, tanpa webhook, tanpa obfuscation

  PERBAIKAN v2.1:
    [FIX-1] Load FluentUI dengan pcall + fallback pesan error (tidak crash)
    [FIX-2] findPartsByKeywords dibungkus pcall + skip objek rusak
    [FIX-3] startAutoLoops guard: cegah loop ganda per fitur
    [FIX-4] interactWith fallback: verifikasi jarak sebelum pindah & tekan
    [FIX-5] Infinite Jump: disconnect koneksi lama sebelum connect baru
    [FIX-6] ESP: batasi jumlah highlight + hapus yg rusak (anti leak)
    [FIX-7] teleportTo: validasi CFrame sebelum set
    [FIX-8] TeleDropdown OnChanged: guard nilai nil
    [FIX-9] setSpeed(false): reset WalkSpeed/JumpPower ke default
    [FIX-10] SetValues dropdown dibungkus pcall

  FITUR:
    1. Auto-Farm        (tanam & panen otomatis)
    2. Auto-Cook        (masak otomatis)
    3. Auto-Serve       (layani pelanggan otomatis)
    4. Auto-Buy/Upgrade (beli/upgrade otomatis)
    5. Teleport         (dropdown lokasi + custom)
    6. Anti-AFK
    7. Speed Boost      (WalkSpeed & JumpPower)
    8. ESP              (highlight pemain & objek)
    9. Infinite Jump
    +  SaveManager (simpan config) & InterfaceManager (theme)
  ============================================================
]]

-- ============================================================
-- CONFIG — sesuaikan keyword sesuai hasil SCAN
-- ============================================================
local Config = {
    ToolNames = { "Hoe", "Watering", "Seed", "Sickle", "Axe", "Shovel", "Panen", "Tanam" },

    FarmKeywords  = { "farm", "plant", "plot", "tanam", "panen", "crop", "garden", "tani", "seed" },
    CookKeywords  = { "cook", "oven", "pot", "stove", "furnace", "station", "kitchen", "masak", "panci", "kompor" },
    ServeKeywords = { "serve", "customer", "ghost", "npc", "counter", "meja", "pelanggan", "layani", "order" },
    BuyKeywords   = { "buy", "upgrade", "shop", "market", "purchase", "beli", "toko" },

    TeleportSpots = { "stall", "kios", "dapur", "kitchen", "farm", "lahan", "tani", "pulau", "island", "home", "rumah", "spawn", "market" },

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
local Players    = game:GetService("Players")
local LP         = Players.LocalPlayer
local UIS        = game:GetService("UserInputService")
local VIM        = game:GetService("VirtualInputManager")
local CoreGui    = game:GetService("CoreGui")

local function char() return LP.Character end
local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function hum()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
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

-- [FIX-2] getPromptsInRadius dibungkus pcall + skip objek rusak
local function getPromptsInRadius(radius)
    local root = hrp()
    if not root then return {} end
    local found = {}
    local ok, err = pcall(function()
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
        -- workspace berubah saat iterasi (GetDescendants) — pakai snapshot aman
        -- fallback: coba lagi sekali dengan pcall per-objek
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

-- [FIX-4] interactWith: verifikasi jarak sebelum fallback
local function interactWith(prompt)
    if not prompt then return false end
    if firePrompt then
        return pcall(firePrompt, prompt)
    end
    local root = hrp()
    if not root then return false end
    local part = prompt.Parent
    if part and part:IsA("BasePart") and part.Position then
        local dist = (part.Position - root.Position).Magnitude
        local maxDist = prompt.MaxActivationDistance or 10
        -- kalau sudah dalam jarak, langsung tekan E (tanpa pindah)
        if dist <= maxDist then
            VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.06)
            VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            return true
        end
        -- kalau jauh, pindah ke posisi valid dekat part, lalu tekan E
        local target = part.CFrame * CFrame.new(0, 0, -(maxDist * 0.5))
        if target then
            root.CFrame = target
            task.wait(0.1)
            VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.06)
            VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            return true
        end
    end
    return false
end

local function equipTool()
    local h = hum()
    if not h then return end
    if char() and char():FindFirstChildOfClass("Tool") then return end
    for _, name in ipairs(Config.ToolNames) do
        local tool = LP.Backpack:FindFirstChild(name)
        if tool then
            pcall(function() h:EquipTool(tool) end)
            return
        end
    end
end

-- ============================================================
-- FLUENT UI SETUP — [FIX-1] pcall + fallback
-- ============================================================
local Fluent, SaveManager, InterfaceManager
local function loadLibrary(url, name)
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    if not ok then
        warn("[DevilMarketHub] Gagal load " .. name .. ": " .. tostring(lib))
        return nil
    end
    return lib
end

Fluent = loadLibrary("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua", "FluentUI")
if not Fluent then
    warn("[DevilMarketHub] FluentUI gagal dimuat. Script berhenti.")
    return
end
SaveManager = loadLibrary("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua", "SaveManager")
InterfaceManager = loadLibrary("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua", "InterfaceManager")

-- Kalau addons gagal, lanjut tanpa mereka (fitur utama tetap jalan)
if not SaveManager or not InterfaceManager then
    warn("[DevilMarketHub] Addons tidak dimuat — Settings tab dikurangi.")
end

local Window = Fluent:CreateWindow({
    Title = "Devil's Market Auto Hub",
    SubTitle = "by Hermes | bersih tanpa key/webhook",
    TabWidth = 140,
    Size = UDim2.fromOffset(560, 480),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Farm    = Window:AddTab({ Title = "Farming", Icon = "sprout" }),
    Cook    = Window:AddTab({ Title = "Cooking", Icon = "chef-hat" }),
    Serve   = Window:AddTab({ Title = "Serving", Icon = "hand" }),
    Shop    = Window:AddTab({ Title = "Shopping", Icon = "shopping-cart" }),
    Move    = Window:AddTab({ Title = "Movement", Icon = "person-standing" }),
    Tele    = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Visual  = Window:AddTab({ Title = "Visual", Icon = "eye" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Options = Fluent.Options

-- ============================================================
-- STATE
-- ============================================================
local State = {
    autoFarm = false, autoCook = false, autoServe = false, autoBuy = false,
    speed = false, antiAfk = false, esp = false, infJump = false,
}
local isUnloaded = false
local activeLoops = {} -- [FIX-3] lacak loop aktif per fitur

-- ============================================================
-- AUTO LOOPS — [FIX-3] cegah loop ganda
-- ============================================================
local function runAutoLoop(key, filterKeywords)
    -- kalau loop untuk fitur ini sudah jalan, jangan spawn lagi
    if activeLoops[key] then return end
    local thread = task.spawn(function()
        while State[key] and not isUnloaded do
            pcall(function()
                equipTool()
                local items = getPromptsInRadius(Config.ScanRadius)
                for _, item in ipairs(items) do
                    if not State[key] or isUnloaded then break end
                    local pname = (item.prompt.Name or "") .. " " .. (item.part.Name or "")
                    local ok = #filterKeywords == 0 or matchesKeywords(pname, filterKeywords)
                    if ok then
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
    if State.autoFarm then runAutoLoop("autoFarm", Config.FarmKeywords) end
    if State.autoCook then runAutoLoop("autoCook", Config.CookKeywords) end
    if State.autoServe then runAutoLoop("autoServe", Config.ServeKeywords) end
    if State.autoBuy then runAutoLoop("autoBuy", Config.BuyKeywords) end
end

-- ============================================================
-- MOVEMENT FEATURES
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
        -- [FIX-9] reset ke default saat dimatikan
        local h = hum()
        if h then
            h.WalkSpeed = 16
            h.JumpPower = 50
        end
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

-- [FIX-5] Infinite Jump: disconnect koneksi lama sebelum connect baru
local infJumpConn = nil
local function setInfJump(on)
    if infJumpConn then
        infJumpConn:Disconnect()
        infJumpConn = nil
    end
    if on then
        infJumpConn = UIS.JumpRequest:Connect(function()
            if State.infJump and not isUnloaded then
                local h = hum()
                if h and h.Health > 0 then
                    h:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end
        end)
    end
end

-- ============================================================
-- ESP — [FIX-6] batasi jumlah highlight, hapus yg rusak
-- ============================================================
local espHighlights = {}
local ESP_MAX_ITEMS = 40 -- batas aman highlight objek

local function clearESP()
    for _, hl in ipairs(espHighlights) do
        pcall(function() hl:Destroy() end)
    end
    espHighlights = {}
end

local function refreshESP()
    clearESP()
    -- pemain
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
    -- objek interaktif (dibatasi)
    local root = hrp()
    if root then
        local count = 0
        for _, obj in ipairs(workspace:GetDescendants()) do
            if count >= ESP_MAX_ITEMS then break end
            pcall(function()
                if obj:IsA("BasePart") and obj.Position and (obj:FindFirstChildOfClass("ProximityPrompt") or obj:FindFirstChildOfClass("ClickDetector")) then
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
                task.wait(5)
                pcall(refreshESP)
            end
        end)
    else
        clearESP()
    end
end

-- ============================================================
-- TELEPORT — [FIX-7] validasi CFrame
-- ============================================================
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
-- SCANNER — dump nama objek asli di game
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
                        table.insert(lines, string.format("PROMPT: %s | parent: %s | jarak: %d", obj.Name, par.Name, dist))
                    end
                end
            end
        end
    end)
    table.insert(lines, "Total prompt di radius: " .. promptCount)
    pcall(function()
        for _, tool in ipairs(LP.Backpack:GetChildren()) do
            table.insert(lines, "TOOL: " .. tool.Name)
        end
    end)
    local seen, count = {}, 0
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Position and root and (obj.Position - root.Position).Magnitude <= Config.ScanRadius then
                if not seen[obj.Name] then
                    seen[obj.Name] = true
                    table.insert(lines, "PART: " .. obj.Name)
                    count = count + 1
                end
                if count >= 15 then break end
            end
        end
    end)
    local text = table.concat(lines, "\n")
    print(text)
    Fluent:Notify({
        Title = "SCAN Selesai",
        Content = promptCount .. " prompt ditemukan. Hasil ada di konsol executor (F9).",
        Duration = 8
    })
end

-- ============================================================
-- BUILD UI
-- ============================================================
do
    -- ============================================================
    -- FARMING TAB
    -- ============================================================
    Tabs.Farm:AddParagraph({
        Title = "Auto Farming",
        Content = "Tanam & panen otomatis. Sesuaikan keyword di Config kalau hasil SCAN berbeda."
    })
    local ToggleFarm = Tabs.Farm:AddToggle("AutoFarm", { Title = "Auto-Farm (tanam & panen)", Default = false })
    ToggleFarm:OnChanged(function(v)
        State.autoFarm = v
        startAutoLoops()
    end)

    -- ============================================================
    -- COOKING TAB
    -- ============================================================
    local ToggleCook = Tabs.Cook:AddToggle("AutoCook", { Title = "Auto-Cook (masak)", Default = false })
    ToggleCook:OnChanged(function(v)
        State.autoCook = v
        startAutoLoops()
    end)

    -- ============================================================
    -- SERVING TAB
    -- ============================================================
    local ToggleServe = Tabs.Serve:AddToggle("AutoServe", { Title = "Auto-Serve (layani pelanggan)", Default = false })
    ToggleServe:OnChanged(function(v)
        State.autoServe = v
        startAutoLoops()
    end)

    -- ============================================================
    -- SHOPPING TAB
    -- ============================================================
    local ToggleBuy = Tabs.Shop:AddToggle("AutoBuy", { Title = "Auto-Buy / Upgrade", Default = false })
    ToggleBuy:OnChanged(function(v)
        State.autoBuy = v
        startAutoLoops()
    end)

    Tabs.Shop:AddParagraph({
        Title = "Catatan",
        Content = "Auto-Buy menginteraksi prompt beli/upgrade terdekat dalam radius. Matikan kalau takut salah beli."
    })

    -- ============================================================
    -- MOVEMENT TAB
    -- ============================================================
    local ToggleSpeed = Tabs.Move:AddToggle("Speed", { Title = "Speed Boost", Default = false })
    ToggleSpeed:OnChanged(function(v)
        State.speed = v
        setSpeed(v)
    end)

    local SliderWalk = Tabs.Move:AddSlider("WalkSpeed", {
        Title = "WalkSpeed", Default = Config.DefaultWalkSpeed, Min = 16, Max = 120, Rounding = 1,
        Callback = function(v) Config.DefaultWalkSpeed = v; if State.speed then pcall(applySpeed) end end
    })

    local SliderJump = Tabs.Move:AddSlider("JumpPower", {
        Title = "JumpPower", Default = Config.DefaultJumpPower, Min = 50, Max = 300, Rounding = 1,
        Callback = function(v) Config.DefaultJumpPower = v; if State.speed then pcall(applySpeed) end end
    })

    local ToggleAfk = Tabs.Move:AddToggle("AntiAfk", { Title = "Anti-AFK", Default = false })
    ToggleAfk:OnChanged(function(v)
        State.antiAfk = v
        setAntiAfk(v)
    end)

    local ToggleInf = Tabs.Move:AddToggle("InfJump", { Title = "Infinite Jump", Default = false })
    ToggleInf:OnChanged(function(v)
        State.infJump = v
        setInfJump(v)
    end)

    -- ============================================================
    -- TELEPORT TAB
    -- ============================================================
    Tabs.Tele:AddParagraph({
        Title = "Teleport",
        Content = "Pilih lokasi dari dropdown (hasil scan otomatis saat tab dibuka) atau ketik nama part."
    })

    local TeleDropdown = Tabs.Tele:AddDropdown("TeleportSpot", {
        Title = "Lokasi (scan otomatis)",
        Values = { "— scan dulu —" },
        Multi = false,
        Default = 1,
    })

    local function rescanTeleport()
        local parts = findPartsByKeywords(Config.TeleportSpots)
        local names, seen = {}, {}
        for _, p in ipairs(parts) do
            if not seen[p.Name] then
                seen[p.Name] = true
                table.insert(names, p.Name)
            end
        end
        if #names == 0 then
            -- [FIX-10] SetValues dibungkus pcall
            pcall(function() TeleDropdown:SetValues({ "— tidak ada spot ditemukan —" }) end)
            Fluent:Notify({ Title = "Teleport", Content = "Tidak ada spot ditemukan. Jalankan SCAN di tab Visual.", Duration = 6 })
        else
            pcall(function() TeleDropdown:SetValues(names) end)
            Fluent:Notify({ Title = "Teleport", Content = #names .. " lokasi ditemukan.", Duration = 5 })
        end
    end

    Tabs.Tele:AddButton({
        Title = "Scan Lokasi",
        Description = "Cari part stall/dapur/farm/pulau di sekitar",
        Callback = rescanTeleport
    })

    -- [FIX-8] guard nilai nil
    TeleDropdown:OnChanged(function(value)
        if not value or value:find("—") then return end
        local part = findPartsByKeywords({ value })[1]
        if part and teleportTo(part) then
            Fluent:Notify({ Title = "Teleport", Content = "Ke " .. value, Duration = 4 })
        end
    end)

    local TeleInput = Tabs.Tele:AddInput("TeleportCustom", {
        Title = "Nama part custom",
        Default = "",
        Placeholder = "cth: Stall",
        Numeric = false,
        Finished = true,
        Callback = function(v)
            if v and v ~= "" then
                local part = findPartsByKeywords({ v })[1]
                if part and teleportTo(part) then
                    Fluent:Notify({ Title = "Teleport", Content = "Ke " .. v, Duration = 4 })
                else
                    Fluent:Notify({ Title = "Teleport", Content = "Part '" .. v .. "' tidak ditemukan", Duration = 5 })
                end
            end
        end
    })

    -- ============================================================
    -- VISUAL TAB
    -- ============================================================
    local ToggleEsp = Tabs.Visual:AddToggle("ESP", { Title = "ESP (highlight pemain & objek)", Default = false })
    ToggleEsp:OnChanged(function(v)
        State.esp = v
        setESP(v)
    end)

    local EspPlayerColor = Tabs.Visual:AddColorpicker("EspPlayerColor", {
        Title = "Warna ESP Pemain",
        Default = Config.EspPlayerColor
    })
    EspPlayerColor:OnChanged(function()
        Config.EspPlayerColor = EspPlayerColor.Value
        if State.esp then pcall(refreshESP) end
    end)

    local EspItemColor = Tabs.Visual:AddColorpicker("EspItemColor", {
        Title = "Warna ESP Objek",
        Default = Config.EspItemColor
    })
    EspItemColor:OnChanged(function()
        Config.EspItemColor = EspItemColor.Value
        if State.esp then pcall(refreshESP) end
    end)

    Tabs.Visual:AddButton({
        Title = "SCAN — Dump Nama Objek",
        Description = "Cetak daftar prompt/tool/part ke konsol (F9)",
        Callback = runScanner
    })

    -- ============================================================
    -- SETTINGS TAB — [FIX-1] hanya kalau addons ada
    -- ============================================================
    if SaveManager and InterfaceManager then
        SaveManager:SetLibrary(Fluent)
        InterfaceManager:SetLibrary(Fluent)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({})
        InterfaceManager:SetFolder("DevilMarketHub")
        SaveManager:SetFolder("DevilMarketHub")
        InterfaceManager:BuildInterfaceSection(Tabs.Settings)
        SaveManager:BuildConfigSection(Tabs.Settings)
    else
        Tabs.Settings:AddParagraph({
            Title = "Addons tidak tersedia",
            Content = "SaveManager/InterfaceManager gagal dimuat. Fitur save/theme nonaktif."
        })
    end

    -- ============================================================
    -- FINALIZE
    -- ============================================================
    Window:SelectTab(1)

    Fluent:Notify({
        Title = "Devil's Market Auto Hub",
        Content = "Dimuat. Klik SCAN di tab Visual kalau auto-fiturnya kurang akurat.",
        Duration = 8
    })

    if SaveManager then
        pcall(function() SaveManager:LoadAutoloadConfig() end)
    end

    -- [FIX-5] Bersihkan koneksi saat unload
    Fluent.OnUnload = function()
        isUnloaded = true
        State.autoFarm = false; State.autoCook = false
        State.autoServe = false; State.autoBuy = false
        State.speed = false; State.antiAfk = false; State.esp = false
        if infJumpConn then
            pcall(function() infJumpConn:Disconnect() end)
            infJumpConn = nil
        end
        clearESP()
        local h = hum()
        if h then h.WalkSpeed = 16; h.JumpPower = 50 end
    end

    print("[DevilMarketHub v2.1] Loaded — FluentUI (fixed)")
end
