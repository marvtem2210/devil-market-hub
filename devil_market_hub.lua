--[[
  ============================================================
  DEVIL'S MARKET (Pasar Setan) — AUTO HUB v7
  PURE — tanpa RemoteSpy (remote scan/hook dipisah)
  ============================================================

  Cara kerja:
    1. Auto-farm/cook/serve/buy pakai ProximityPrompt langsung
    2. fireproximityprompt kalau executor support, fallback
       ke VirtualInputManager (tekan E)
    3. Tool di-equip otomatis dari backpack

  KONTROL:
    F1  = Auto-Farm ON/OFF
    F2  = Auto-Cook ON/OFF
    F3  = Auto-Serve ON/OFF
    F4  = Auto-Buy ON/OFF
    F5  = Speed Boost ON/OFF
    F6  = Anti-AFK ON/OFF
    F7  = ESP ON/OFF
    F8  = Teleport ke lokasi terdekat
    F9  = SCAN — dump objek + prompt ke konsol
    F10 = Matikan SEMUA fitur

  MODE HYBRID: kalau remote_spy.lua jalan barengan, hub otomatis
  baca _G.DMHubRemoteData dan replay remote + args asli yang
  ke-tangkep spy (lebih akurat dari prompt). Gak ada data / data
  basi (>10 menit) → fallback ProximityPrompt kayak biasa.
  Urutan: load spy → gerak normal biar args ke-log → nyalain auto.

  MODE KAITUN: kalau kaitun_engine.lua jalan, hub ngikutin phase
  engine (GATHER->COOK->SERVE) — gak asal nyalain semua fitur.
  Engine yang mutusin fitur mana yang aktif tiap saat.
  ============================================================
]]

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    -- Keyword buat fallback ProximityPrompt
    ToolNames     = { "Hoe", "Watering", "Seed", "Sickle", "Axe", "Shovel", "Panen", "Tanam" },
    FarmKeywords  = { "farm", "plant", "plot", "tanam", "panen", "crop", "garden", "tani", "seed", "harvest" },
    CookKeywords  = { "cook", "oven", "pot", "stove", "furnace", "station", "kitchen", "masak", "panci", "kompor", "recipe" },
    ServeKeywords = { "serve", "customer", "ghost", "npc", "counter", "meja", "pelanggan", "layani", "order", "deliver" },
    BuyKeywords   = { "buy", "upgrade", "shop", "market", "purchase", "beli", "toko", "unlock", "store" },
    TeleportSpots = { "stall", "kios", "dapur", "kitchen", "farm", "lahan", "pulau", "island", "home", "rumah", "spawn", "market" },

    ScanRadius        = 30,
    ActionDelay       = 0.35,
    LoopInterval      = 2.0,
    UseSpyRemote      = true,   -- pakai remote data dari remote_spy kalau ada
    SpyRemoteDelay    = 0.2,    -- jeda antar replay remote
    SpyDataFreshness  = 600,    -- detik; data spy dianggap basi setelah ini
    UseKaitunEngine   = true,   -- ikutin phase dari kaitun_engine kalau ada
    EspPlayerColor    = Color3.fromRGB(255, 80, 80),
    EspItemColor      = Color3.fromRGB(80, 255, 120),
    DefaultWalkSpeed  = 16,
    SpeedBoostValue   = 32,
    AntiAfkInterval   = 45,
}

-- ============================================================
-- SERVICES
-- ============================================================
local Players    = game:GetService("Players")
local LP         = Players.LocalPlayer
local UIS        = game:GetService("UserInputService")
local VIM        = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")

-- ============================================================
-- HELPERS UMUM
-- ============================================================
local function char() return LP.Character end
local function hrp()
    local c = char(); return c and c:FindFirstChild("HumanoidRootPart")
end
local function hum()
    local c = char(); return c and c:FindFirstChildOfClass("Humanoid")
end

local function lower(s) return string.lower(tostring(s or "")) end

local function matchesKeywords(name, keywords)
    local n = lower(name)
    for _, kw in ipairs(keywords) do
        if n:find(lower(kw), 1, true) then return true end
    end
    return false
end

local function log(msg)
    print("[DMHub v7] " .. msg)
end

-- Notifikasi native Roblox (pojok kanan atas) — aman dari blokir GUI executor
local function notify(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title or "DMHub v7",
            Text  = text or "",
            Duration = duration or 5,
        })
    end)
end

-- ============================================================
-- PROXIMITY PROMPT HELPERS
-- ============================================================
local firePrompt = fireproximityprompt

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
                if obj:IsA("BasePart") and obj.Position
                and matchesKeywords(obj.Name, keywords) then
                    table.insert(found, obj)
                end
            end)
        end
    end)
    return found
end

-- ============================================================
-- REMOTE REPLAY — baca hasil map dari remote_spy (_G)
-- ============================================================
local spyCache = {}  -- path -> Remote (cache resolve biar gak scan terus)

local function resolveRemoteByPath(path)
    if spyCache[path] and spyCache[path].Parent then return spyCache[path] end
    spyCache[path] = nil
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:GetFullName() == path then
            spyCache[path] = obj
            return obj
        end
    end
    return nil
end

-- Tembak satu remote dengan args
local function fireRemote(remote, ...)
    if not remote or not remote.Parent then return false end
    local args = {...}
    local ok, err = pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(unpack(args))
        elseif remote:IsA("RemoteFunction") then
            remote:InvokeServer(unpack(args))
        end
    end)
    if not ok then
        log("fireRemote error: " .. tostring(err))
    end
    return ok
end

-- Replay remote yang di-map remote_spy untuk satu kategori.
-- Hanya fire remote yang PUNYA sample args (pernah ke-fire game asli).
-- Return true kalau minimal 1 fire sukses → loop skip prompt.
local function fireSpyCategory(category)
    local shared = _G and _G.DMHubRemoteData
    if type(shared) ~= "table" then return false end
    -- Data basi → anggap spy gak jalan, balik ke prompt
    if os.clock() - (shared.updated or 0) > Config.SpyDataFreshness then return false end
    local data = shared[category]
    if type(data) ~= "table" or #data == 0 then return false end
    local fired = false
    for _, e in ipairs(data) do
        if e.lastArgsRaw and e.path then
            local remote = resolveRemoteByPath(e.path)
            if remote and fireRemote(remote, unpack(e.lastArgsRaw)) then
                fired = true
                task.wait(Config.SpyRemoteDelay)
            end
        end
    end
    return fired
end

-- ============================================================
-- KAITUN PHASE — baca keputusan dari kaitun_engine.lua
-- ============================================================
-- Hub jadi "tangan": nyalain/matiin fitur sesuai phase engine.
local function kaitunPhase()
    local k = _G and _G.DMKaitun
    if not k or not k.running then return nil end
    return k.phase
end

-- Fitur yang harus aktif per phase
local function kaitunWantedFeatures()
    local phase = kaitunPhase()
    if not phase then return nil end
    return {
        autoFarm  = phase == "GATHER",
        autoCook  = phase == "COOK",
        autoServe = phase == "SERVE",
        autoBuy   = phase == "GATHER",  -- beli/upgrade pas kumpulin bahan
    }
end

-- Sync fitur hub dengan phase engine (dipanggil tiap detik)
local function syncKaitun()
    local wanted = kaitunWantedFeatures()
    if not wanted then return end
    for feature, enabled in pairs(wanted) do
        if State[feature] ~= enabled then
            setFeature(feature, enabled, "KAITUN")
        end
    end
end

task.spawn(function()
    while true do
        task.wait(2)
        pcall(syncKaitun)
    end
end)

-- ============================================================
-- STATE & LOOP ENGINE
-- ============================================================
local State = {
    autoFarm = false, autoCook = false,
    autoServe = false, autoBuy = false,
    speed = false, antiAfk = false, esp = false,
}
local activeLoops = {}

-- Loop generik — interaksi ProximityPrompt murni
local function runAutoLoop(key, remoteCategory, promptKeywords)
    if activeLoops[key] then return end
    activeLoops[key] = task.spawn(function()
        while State[key] do
            pcall(function()
                -- 1) Replay remote dari remote_spy (kalau ada datanya)
                local firedViaRemote = false
                if Config.UseSpyRemote then
                    firedViaRemote = fireSpyCategory(remoteCategory)
                end

                -- 2) Fallback: ProximityPrompt
                if not firedViaRemote then
                    equipTool()
                    local items = getPromptsInRadius(Config.ScanRadius)
                    for _, item in ipairs(items) do
                        if not State[key] then break end
                        local pname = (item.prompt.Name or "") .. " " .. (item.part.Name or "")
                        if #promptKeywords == 0 or matchesKeywords(pname, promptKeywords) then
                            interactWith(item.prompt)
                            task.wait(Config.ActionDelay)
                        end
                    end
                end
            end)
            task.wait(Config.LoopInterval)
        end
        activeLoops[key] = nil
    end)
end

local function startAutoLoops()
    if State.autoFarm  then runAutoLoop("autoFarm",  "farm",  Config.FarmKeywords)  end
    if State.autoCook  then runAutoLoop("autoCook",  "cook",  Config.CookKeywords)  end
    if State.autoServe then runAutoLoop("autoServe", "serve", Config.ServeKeywords) end
    if State.autoBuy   then runAutoLoop("autoBuy",   "buy",   Config.BuyKeywords)   end
end

local function setFeature(key, enabled, label)
    State[key] = enabled
    log(label .. " " .. (enabled and "ON" or "OFF"))
    if enabled then startAutoLoops() end
end

-- ============================================================
-- SPEED
-- ============================================================
local function setSpeed(on)
    State.speed = on
    if on then
        log("Speed Boost ON (" .. Config.SpeedBoostValue .. ")")
        task.spawn(function()
            while State.speed do
                pcall(function()
                    local h = hum(); if h then h.WalkSpeed = Config.SpeedBoostValue end
                end)
                task.wait(1.5)
            end
        end)
    else
        log("Speed Boost OFF")
        local h = hum(); if h then h.WalkSpeed = Config.DefaultWalkSpeed end
    end
end

-- ============================================================
-- ANTI-AFK
-- ============================================================
local function setAntiAfk(on)
    State.antiAfk = on
    log("Anti-AFK " .. (on and "ON" or "OFF"))
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
                hl.FillColor          = Config.EspPlayerColor
                hl.OutlineColor       = Color3.fromRGB(255, 255, 255)
                hl.FillTransparency   = 0.65
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
                    if (obj.Position - root.Position).Magnitude <= Config.ScanRadius * 3 then
                        local hl = Instance.new("Highlight")
                        hl.FillColor          = Config.EspItemColor
                        hl.OutlineColor       = Color3.fromRGB(255, 255, 255)
                        hl.FillTransparency   = 0.55
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
    State.esp = on
    log("ESP " .. (on and "ON" or "OFF"))
    if on then
        refreshESP()
        task.spawn(function()
            while State.esp do task.wait(5); pcall(refreshESP) end
        end)
    else
        clearESP()
    end
end

-- ============================================================
-- TELEPORT (F8)
-- ============================================================
local function teleportNearest()
    local root = hrp()
    if not root then log("Karakter belum spawn"); return end
    local parts = findPartsByKeywords(Config.TeleportSpots)
    local best, bestDist = nil, math.huge
    for _, p in ipairs(parts) do
        local d = (p.Position - root.Position).Magnitude
        if d < bestDist then best, bestDist = p, d end
    end
    if best then
        root.CFrame = best.CFrame * CFrame.new(0, 4, 0)
        log("Teleport ke " .. best.Name .. " (" .. math.floor(bestDist) .. " stud)")
    else
        log("Tidak ada spot ditemukan. Coba F9 (SCAN).")
    end
end

-- ============================================================
-- SCANNER (F9) — dump prompt + tool terdekat
-- ============================================================
local function runScanner()
    local root = hrp()
    local lines = { "===== SCAN v7 =====" }
    local promptCount = 0
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                promptCount = promptCount + 1
                local par = obj.Parent
                if par and par:IsA("BasePart") and par.Position and root then
                    local dist = math.floor((par.Position - root.Position).Magnitude)
                    if dist <= Config.ScanRadius * 3 then
                        lines[#lines+1] = ("PROMPT: %s | parent: %s | dist: %d"):format(obj.Name, par.Name, dist)
                    end
                end
            end
        end
    end)
    lines[#lines+1] = "Total prompts: " .. promptCount
    pcall(function()
        for _, tool in ipairs(LP.Backpack:GetChildren()) do
            lines[#lines+1] = "TOOL: " .. tool.Name
        end
    end)
    print(table.concat(lines, "\n"))
    log("SCAN selesai. Lihat konsol.")
end

-- ============================================================
-- UI — compact, pojok kanan atas
-- ============================================================
local UI = {}

local function buildUI()
    -- Cleanup kalau udah ada
    local existing = LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("DMHubUI")
    if existing then existing:Destroy() end

    local StarterGui = game:GetService("StarterGui")
    local PlayerGui  = LP:WaitForChild("PlayerGui", 10)
    if not PlayerGui then return end

    -- ScreenGui
    local screen = Instance.new("ScreenGui")
    screen.Name            = "DMHubUI"
    screen.ResetOnSpawn    = false
    screen.DisplayOrder    = 999
    screen.IgnoreGuiInset  = true
    screen.Parent          = PlayerGui

    -- Main frame — kecil, pojok kanan atas
    local frame = Instance.new("Frame")
    frame.Name             = "Main"
    frame.Size             = UDim2.new(0, 155, 0, 310)
    frame.Position         = UDim2.new(1, -160, 0, 45)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BorderSizePixel  = 0
    frame.Active           = true
    frame.Draggable        = true
    frame.Parent           = screen

    -- Title bar
    local title = Instance.new("TextLabel")
    title.Size             = UDim2.new(1, -28, 0, 24)
    title.Position         = UDim2.new(0, 4, 0, 0)
    title.BackgroundTransparency = 1
    title.Text             = "DMHub v7"
    title.TextColor3       = Color3.fromRGB(200, 160, 255)
    title.TextSize         = 13
    title.Font             = Enum.Font.GothamBold
    title.TextXAlignment   = Enum.TextXAlignment.Left
    title.Parent           = frame

    -- Tombol close (X)
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size          = UDim2.new(0, 24, 0, 24)
    closeBtn.Position      = UDim2.new(1, -26, 0, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeBtn.BorderSizePixel  = 0
    closeBtn.Text          = "X"
    closeBtn.TextColor3    = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize      = 11
    closeBtn.Font          = Enum.Font.GothamBold
    closeBtn.Parent        = frame
    closeBtn.MouseButton1Click:Connect(function()
        screen:Destroy()
    end)

    -- Separator
    local sep = Instance.new("Frame")
    sep.Size               = UDim2.new(1, 0, 0, 1)
    sep.Position           = UDim2.new(0, 0, 0, 24)
    sep.BackgroundColor3   = Color3.fromRGB(60, 60, 70)
    sep.BorderSizePixel    = 0
    sep.Parent             = frame

    -- Helper bikin tombol toggle
    local CON = Color3.fromRGB(50, 180, 80)   -- ON  = hijau
    local COFF = Color3.fromRGB(55, 55, 65)   -- OFF = abu

    local function makeToggle(label, yPos, stateKey, onFn)
        local btn = Instance.new("TextButton")
        btn.Name           = stateKey
        btn.Size           = UDim2.new(1, -8, 0, 26)
        btn.Position       = UDim2.new(0, 4, 0, yPos)
        btn.BackgroundColor3 = COFF
        btn.BorderSizePixel  = 0
        btn.Text           = label .. "  OFF"
        btn.TextColor3     = Color3.fromRGB(200, 200, 200)
        btn.TextSize       = 11
        btn.Font           = Enum.Font.Gotham
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent         = frame

        btn.MouseButton1Click:Connect(function()
            onFn()
            -- Update tampilan
            local on = State[stateKey]
            btn.BackgroundColor3 = on and CON or COFF
            btn.Text = label .. (on and "  ON" or "  OFF")
            btn.TextColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(200,200,200)
        end)

        UI[stateKey .. "_btn"] = btn
        return btn
    end

    -- Helper bikin tombol aksi (non-toggle)
    local function makeAction(label, yPos, fn)
        local btn = Instance.new("TextButton")
        btn.Size           = UDim2.new(1, -8, 0, 26)
        btn.Position       = UDim2.new(0, 4, 0, yPos)
        btn.BackgroundColor3 = Color3.fromRGB(40, 80, 140)
        btn.BorderSizePixel  = 0
        btn.Text           = label
        btn.TextColor3     = Color3.fromRGB(200, 220, 255)
        btn.TextSize       = 11
        btn.Font           = Enum.Font.Gotham
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent         = frame

        btn.MouseButton1Click:Connect(fn)
        return btn
    end

    -- Tombol-tombol (yPos mulai dari 28, tiap row 28px)
    local y = 28
    makeToggle("Farm",     y, "autoFarm",  function() setFeature("autoFarm",  not State.autoFarm,  "Auto-Farm")  end) y = y + 28
    makeToggle("Cook",     y, "autoCook",  function() setFeature("autoCook",  not State.autoCook,  "Auto-Cook")  end) y = y + 28
    makeToggle("Serve",    y, "autoServe", function() setFeature("autoServe", not State.autoServe, "Auto-Serve") end) y = y + 28
    makeToggle("Buy",      y, "autoBuy",   function() setFeature("autoBuy",   not State.autoBuy,   "Auto-Buy")   end) y = y + 28
    makeToggle("Speed",    y, "speed",     function() setSpeed(not State.speed)    end) y = y + 28
    makeToggle("Anti-AFK", y, "antiAfk",  function() setAntiAfk(not State.antiAfk) end) y = y + 28
    makeToggle("ESP",      y, "esp",       function() setESP(not State.esp)        end) y = y + 28

    -- Separator
    local sep2 = Instance.new("Frame")
    sep2.Size             = UDim2.new(1, 0, 0, 1)
    sep2.Position         = UDim2.new(0, 0, 0, y)
    sep2.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    sep2.BorderSizePixel  = 0
    sep2.Parent           = frame
    y = y + 4

    makeAction("Teleport",  y, teleportNearest) y = y + 28
    makeAction("Scan",      y, runScanner)

    -- Sesuaikan tinggi frame
    frame.Size = UDim2.new(0, 155, 0, y + 28)

    UI.frame = frame
    log("UI mobile aktif")
end

local function shutdownAll()
    State.autoFarm = false; State.autoCook  = false
    State.autoServe = false; State.autoBuy  = false
    State.speed = false;     State.antiAfk  = false; State.esp = false
    clearESP()
    local h = hum(); if h then h.WalkSpeed = Config.DefaultWalkSpeed end
    log("SEMUA fitur dimatikan. Speed direset.")
end

-- ============================================================
-- KEYBINDS
-- ============================================================
UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local k = input.KeyCode
    if     k == Enum.KeyCode.F1  then setFeature("autoFarm",  not State.autoFarm,  "Auto-Farm")
    elseif k == Enum.KeyCode.F2  then setFeature("autoCook",  not State.autoCook,  "Auto-Cook")
    elseif k == Enum.KeyCode.F3  then setFeature("autoServe", not State.autoServe, "Auto-Serve")
    elseif k == Enum.KeyCode.F4  then setFeature("autoBuy",   not State.autoBuy,   "Auto-Buy")
    elseif k == Enum.KeyCode.F5  then setSpeed(not State.speed)
    elseif k == Enum.KeyCode.F6  then setAntiAfk(not State.antiAfk)
    elseif k == Enum.KeyCode.F7  then setESP(not State.esp)
    elseif k == Enum.KeyCode.F8  then teleportNearest()
    elseif k == Enum.KeyCode.F9  then runScanner()
    elseif k == Enum.KeyCode.F10 then shutdownAll()
    end
end)

-- ============================================================
-- INIT
-- ============================================================
print("==========================================")
print("  DEVIL'S MARKET AUTO HUB v7 — LOADING")
print("==========================================")

-- Bangun UI mobile (di-skip kalau PlayerGui belum ready)
task.spawn(buildUI)

print("  F1  Auto-Farm     F6  Anti-AFK")
print("  F2  Auto-Cook     F7  ESP")
print("  F3  Auto-Serve    F8  Teleport")
print("  F4  Auto-Buy      F9  SCAN")
print("  F5  Speed Boost   F10 Matikan Semua")
print("------------------------------------------")
print("  Mode Hybrid: remote dari remote_spy (kalau ada)")
print("  → replay remote + args asli, fallback ke prompt")
print("  Mode Kaitun: ikutin phase engine kalau jalan")
print("==========================================")
