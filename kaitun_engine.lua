--[[
  ============================================================
  KAITUN ENGINE — Devil's Market (Pasar Setan)
  Otak phase-based: kumpulin bahan dulu, BARU proses.
  ============================================================

  FILOSOFI (sesuai permintaan):
    JANGAN langsung cook/serve pas bahan baru dikit.
    GATHER dulu sampe SEMUA bahan cukup → baru COOK →
    baru SERVE → balik GATHER. Upgrade di sela-sela.

  PHASE FLOW:
    GATHER ──(semua bahan >= threshold)──▶ COOK
      ▲                                      │
      │        (bahan abis / resep selesai)  ▼
      └────────────── SERVE ◀──(produk jadi)─┘

  CARA KERJA:
    - StockTracker baca stok bahan dari 2 sumber:
        1. readStock(path)  → di-wire setelah kita tau lokasi
           inventory asli (dari probe/DEX). Isi manual.
        2. SpyLearn          → auto-baca _G.DMHubRemoteData
           (remote yang ke-fire game) buat nebak stok. Mode
           belajar — akurasinya nunggu wiring manual.
    - Tiap tick, engine mutusin phase & kategori hub mana yang
      harus aktif, di-share lewat _G.DMKaitun.

  INTEGRASI HUB:
    Hub/devil_market_hub.lua baca _G.DMKaitun dan nyalain
    fitur sesuai phase. Tanpa hub, engine tetep jalan (log
    + UI progress) biar keliatan keputusannya.
  ============================================================
]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local UIS = game:GetService("UserInputService")

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    TickInterval   = 3,        -- detik tiap keputusan phase
    StockThreshold = 10,       -- stok minimal tiap bahan sebelum COOK
    MinProfit      = 5,        -- minimum produk siap jual sebelum SERVE
    CookTicks      = 4,        -- berapa tick phase COOK bertahan (12 detik)
    ServeTicks     = 4,        -- berapa tick phase SERVE bertahan (12 detik)

    -- Resep yang mau dikejar. ISI nanti setelah probe/DEX
    -- ngasih tau nama bahan & produk asli di game.
    -- Format: { name = "NamaProduk", needs = { Bahan1 = qty, ... } }
    Recipes = {
        -- { name = "Roti", needs = { Gandum = 3, Telur = 2 } },
    },

    -- Kalau Recipes kosong, engine pakai mode belajar:
    -- baca remote yang ke-fire spy dan catat bahannya.
    AutoLearn = true,
}

-- ============================================================
-- STOCK TRACKER
-- ============================================================
local Stock = {
    material = {},   -- material -> qty (stok aktual)
    known    = {},   -- material -> true (pernah ke-detect)
    learned  = {},   -- material -> qty (hasil belajar dari spy)
}

-- Wiring manual: isi path value inventory di sini setelah probe
local function readStock(materialName)
    -- TODO: ganti dengan path asli hasil probe/DEX
    -- contoh: local v = LP:FindFirstChild("Inventory"):FindFirstChild(materialName)
    --         return v and v.Value or 0
    return Stock.learned[materialName] or 0
end

-- Mode belajar: ekstrak angka + kata dari ARGS ASLI yang ke-tangkep spy
-- (field lastArgsStr di tiap kategori _G.DMHubRemoteData).
-- Naive tapi cukup buat nebak bahan yang muncul di remote call.
local function spyLearn()
    pcall(function()
        local shared = _G and _G.DMHubRemoteData
        if type(shared) ~= "table" then return end
        for _, cat in ipairs({ "farm", "cook", "serve", "buy" }) do
            local data = shared[cat]
            if type(data) == "table" then
                for _, e in ipairs(data) do
                    local argsStr = e.lastArgsStr or ""
                    -- cari pola "NamaBahan=123"
                    for mat, qty in string.gmatch(argsStr, "([%a_]+)%s*=%s*(%d+)") do
                        mat = string.lower(mat)
                        if #mat > 2 then
                            Stock.known[mat] = true
                            Stock.learned[mat] = tonumber(qty) or 0
                            print("[KAITUN] belajar bahan: " .. mat .. " = " .. qty)
                        end
                    end
                end
            end
        end
    end)
end

-- Refresh stok aktual (dari wiring + belajar)
local function refreshStock()
    pcall(function()
        for mat in pairs(Stock.known) do
            Stock.material[mat] = readStock(mat)
        end
    end)
    if Config.AutoLearn then spyLearn() end
end

-- ============================================================
-- RECIPE LOGIC
-- ============================================================
local function hasAllMaterials()
    if #Config.Recipes == 0 then
        -- Mode belajar: cukup kalau ada >= 1 bahan ke-detect
        local n = 0
        for _ in pairs(Stock.known) do n = n + 1 end
        return n >= 1
    end
    for _, recipe in ipairs(Config.Recipes) do
        for mat, qty in pairs(recipe.needs) do
            local have = Stock.material[mat] or 0
            if have < qty then return false end
        end
    end
    return true
end

local function missingMaterials()
    local missing = {}
    if #Config.Recipes == 0 then return missing end
    for _, recipe in ipairs(Config.Recipes) do
        for mat, qty in pairs(recipe.needs) do
            local have = Stock.material[mat] or 0
            if have < qty then
                missing[#missing+1] = mat .. " (" .. have .. "/" .. qty .. ")"
            end
        end
    end
    return missing
end

-- ============================================================
-- PHASE ENGINE
-- ============================================================
local Phase = {
    GATHER = "GATHER",
    COOK   = "COOK",
    SERVE  = "SERVE",
}

local engine = {
    phase        = Phase.GATHER,
    reason       = "mulai",
    lastTick     = 0,
    ticksInPhase = 0,
}

-- Share ke hub & UI
local function publish()
    _G.DMKaitun = _G.DMKaitun or {}
    _G.DMKaitun.phase    = engine.phase
    _G.DMKaitun.reason   = engine.reason
    _G.DMKaitun.stock    = Stock.material
    _G.DMKaitun.updated  = os.clock()
end

local function setPhase(p, reason)
    if engine.phase ~= p then
        engine.phase  = p
        engine.reason = reason
        engine.ticksInPhase = 0
        print(string.format("[KAITUN] PHASE %s — %s", p, reason))
        publish()
    end
end

local function tick()
    refreshStock()
    publish()

    engine.ticksInPhase = engine.ticksInPhase + 1

    if engine.phase == Phase.GATHER then
        if hasAllMaterials() then
            setPhase(Phase.COOK, "semua bahan cukup, mulai masak")
        else
            local miss = missingMaterials()
            engine.reason = #miss > 0 and ("kurang: " .. table.concat(miss, ", ")) or "kumpulin bahan..."
            publish()
        end

    elseif engine.phase == Phase.COOK then
        if not hasAllMaterials() then
            setPhase(Phase.GATHER, "bahan abis, balik kumpulin")
        elseif engine.ticksInPhase >= Config.CookTicks then
            setPhase(Phase.SERVE, "produk numpuk, mulai jual")
        else
            engine.reason = ("masak... (%d/%d)"):format(engine.ticksInPhase, Config.CookTicks)
            publish()
        end

    elseif engine.phase == Phase.SERVE then
        if engine.ticksInPhase >= Config.ServeTicks then
            setPhase(Phase.GATHER, "produk abis, mulai dari awal")
        else
            engine.reason = ("jual... (%d/%d)"):format(engine.ticksInPhase, Config.ServeTicks)
            publish()
        end
    end
end

-- ============================================================
-- UI — panel progress kaitun (pojok kiri atas)
-- ============================================================
local UI = {}

local function buildUI()
    local existing = LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("KaitunUI")
    if existing then existing:Destroy() end
    local PlayerGui = LP:WaitForChild("PlayerGui", 10)
    if not PlayerGui then return end

    local screen = Instance.new("ScreenGui")
    screen.Name           = "KaitunUI"
    screen.ResetOnSpawn   = false
    screen.DisplayOrder   = 997
    screen.IgnoreGuiInset = true
    screen.Parent         = PlayerGui

    local frame = Instance.new("Frame")
    frame.Name            = "Main"
    frame.Size            = UDim2.new(0, 220, 0, 150)
    frame.Position        = UDim2.new(0, 10, 0, 45)
    frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    frame.BorderSizePixel = 0
    frame.Active          = true
    frame.Draggable       = true
    frame.Parent          = screen

    local title = Instance.new("TextLabel")
    title.Size            = UDim2.new(1, -8, 0, 20)
    title.Position        = UDim2.new(0, 4, 0, 0)
    title.BackgroundTransparency = 1
    title.Text            = "KAITUN ENGINE"
    title.TextColor3      = Color3.fromRGB(255, 200, 120)
    title.TextSize        = 12
    title.Font            = Enum.Font.GothamBold
    title.TextXAlignment  = Enum.TextXAlignment.Left
    title.Parent          = frame

    local status = Instance.new("TextLabel")
    status.Name           = "Status"
    status.Size           = UDim2.new(1, -8, 0, 60)
    status.Position       = UDim2.new(0, 4, 0, 22)
    status.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    status.BorderSizePixel = 0
    status.Text           = "PHASE: GATHER\n..."
    status.TextColor3     = Color3.fromRGB(200, 220, 200)
    status.TextSize       = 11
    status.Font           = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Parent         = frame

    local btn = Instance.new("TextButton")
    btn.Size              = UDim2.new(1, -8, 0, 30)
    btn.Position          = UDim2.new(0, 4, 0, 110)
    btn.BackgroundColor3  = Color3.fromRGB(60, 60, 60)
    btn.BorderSizePixel   = 0
    btn.Text              = "Mulai Engine"
    btn.TextColor3        = Color3.fromRGB(255, 255, 255)
    btn.TextSize          = 12
    btn.Font              = Enum.Font.GothamBold
    btn.Parent            = frame

    UI.frame = frame
    UI.status = status
    UI.btn = btn

    -- Toggle engine
    local running = false
    btn.MouseButton1Click:Connect(function()
        running = not running
        btn.Text = running and "Stop Engine" or "Mulai Engine"
        btn.BackgroundColor3 = running and Color3.fromRGB(120, 60, 60) or Color3.fromRGB(60, 60, 60)
        _G.DMKaitun = _G.DMKaitun or {}
        _G.DMKaitun.running = running
    end)

    -- Auto-refresh status
    task.spawn(function()
        while true do
            task.wait(1)
            pcall(function()
                if UI.status then
                    local p = _G.DMKaitun and _G.DMKaitun.phase or Phase.GATHER
                    local r = _G.DMKaitun and _G.DMKaitun.reason or "..."
                    UI.status.Text = "PHASE: " .. tostring(p) .. "\n" .. tostring(r)
                end
            end)
        end
    end)

    print("[KAITUN] UI aktif")
end

-- ============================================================
-- LOOP UTAMA
-- ============================================================
task.spawn(function()
    while true do
        task.wait(Config.TickInterval)
        pcall(function()
            local k = _G.DMKaitun
            if k and k.running then
                tick()
            end
        end)
    end
end)

-- ============================================================
-- INIT
-- ============================================================
print("==========================================")
print("  KAITUN ENGINE — Devil's Market")
print("  Phase: GATHER -> COOK -> SERVE -> GATHER")
print("  Tunggu data inventory dari probe/DEX...")
print("  (atau isi Config.Recipes manual)")
print("==========================================")

task.spawn(buildUI)
task.spawn(function()
    task.wait(1)
    pcall(spyLearn)
end)
