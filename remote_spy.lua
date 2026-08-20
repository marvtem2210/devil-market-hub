--[[
  ============================================================
  REMOTE SPY — Devil's Market (Pasar Setan)
  Standalone — terpisah dari auto-hub
  ============================================================

  Fungsi:
    1. Scan SEMUA RemoteEvent/RemoteFunction di game
    2. Kategorikan otomatis (farm/cook/serve/buy)
    3. Hook __namecall buat intercept FireServer/InvokeServer
       live (butuh hookmetamethod dari executor)
    4. Log args tiap remote call (serialize, anti-circular)
    5. Dump ke konsol + save ke file (writefile)

  KONTROL:
    F9   = SCAN ulang + dump objek/prompt ke konsol
    F11  = Dump RemoteMap ke konsol + save ke file
    F12  = Reset RemoteMap + scan ulang

  Catatan: ini murni untuk INSPEKSI — gak ada auto-farm di sini.

  INTEGRASI HUB: hasil map di-share lewat _G.DMHubRemoteData.
  Kalau devil_market_hub.lua jalan barengan, hub otomatis
  replay remote + args asli yang ke-tangkep (sebelum fallback
  ke ProximityPrompt). Urutan: load spy → gerak normal biar
  args ke-log → baru nyalain auto di hub.
  ============================================================
]]

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    -- Remote keyword kategori (untuk auto-kategorisasi)
    RemoteFarmKw  = { "farm", "plant", "harvest", "seed", "tanam", "panen", "water", "grow", "crop" },
    RemoteCookKw  = { "cook", "recipe", "craft", "make", "masak", "process", "brew", "bake" },
    RemoteServeKw = { "serve", "deliver", "order", "complete", "customer", "layani", "antar", "give" },
    RemoteBuyKw   = { "buy", "purchase", "upgrade", "unlock", "beli", "shop", "store", "acquire" },

    MaxRemoteLogs     = 300,  -- batas log remote biar nggak bocor memori
    RemoteFireDelay   = 0.2,  -- jeda antar fire remote

    -- Save ke file (executor workspace folder)
    SaveFileName      = "DevilMarket_Remotes.txt",  -- ganti nama sesuka lo
    AutoSaveInterval  = 0,   -- >0 = auto-save tiap N detik, 0 = manual (tekan F11)
}

-- ============================================================
-- SERVICES
-- ============================================================
local Players    = game:GetService("Players")
local LP         = Players.LocalPlayer
local UIS        = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")

-- ============================================================
-- REMOTE MAP — hasil deteksi
-- ============================================================
local RemoteMap = {
    farm  = {},  -- list RemoteEvent/Function untuk farming
    cook  = {},  -- masak
    serve = {},  -- layani pelanggan
    buy   = {},  -- beli/upgrade
    all   = {},  -- semua remote yang pernah ketangkep
    logs  = {},  -- log call: {time, path, method, args}
}

-- ============================================================
-- HELPERS UMUM
-- ============================================================
local function char() return LP.Character end
local function hrp()
    local c = char(); return c and c:FindFirstChild("HumanoidRootPart")
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
    print("[RemoteSpy] " .. msg)
end

-- Notifikasi native Roblox (pojok kanan atas) — aman dari blokir GUI executor
local function notify(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title or "RemoteSpy",
            Text  = text or "",
            Duration = duration or 5,
        })
    end)
end

-- ============================================================
-- SHARED DATA — dibaca devil_market_hub.lua
-- ============================================================
-- _G.DMHubRemoteData:
--   farm/cook/serve/buy = { { path, className, name, fireCount,
--                             lastArgsRaw, lastArgsStr, lastTime } }
--   updated = os.clock() terakhir spy update (freshness check hub)
_G.DMHubRemoteData = _G.DMHubRemoteData or {
    farm = {}, cook = {}, serve = {}, buy = {},
    updated = 0,
}

local RAW_ARGS_CAP = 8  -- maksimal argumen asli yang disimpan per remote

local function syncSpyData()
    _G.DMHubRemoteData.updated = os.clock()
end

-- Kategori remote (satu sumber kebenaran: categorize + sync)
local function remoteCategoryOf(remote)
    local name = lower(remote.Name)
    if matchesKeywords(name, Config.RemoteFarmKw) then return "farm" end
    if matchesKeywords(name, Config.RemoteCookKw) then return "cook" end
    if matchesKeywords(name, Config.RemoteServeKw) then return "serve" end
    if matchesKeywords(name, Config.RemoteBuyKw) then return "buy" end
    return nil
end

-- ============================================================
-- SERIALIZE ARG (buat logging)
-- ============================================================
local FormatArg
local function SerializeTable(tbl, depth, visited)
    depth   = depth   or 0
    visited = visited or {}
    if depth >= 4 then return "{...}" end
    if visited[tbl] then return "{CIRCULAR}" end
    visited[tbl] = true
    local parts = {}
    local empty = true
    for k, v in pairs(tbl) do
        empty = false
        local ks = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
        parts[#parts+1] = ks .. "=" .. FormatArg(v, depth+1, visited)
    end
    return empty and "{}" or ("{" .. table.concat(parts, ", ") .. "}")
end

FormatArg = function(arg, depth, visited)
    depth   = depth   or 0
    visited = visited or {}
    if arg == nil then return "nil" end
    local t = typeof(arg)
    if t == "Instance"       then return "Inst(" .. (pcall(function() return arg:GetFullName() end) and arg:GetFullName() or "?") .. ")" end
    if t == "table"          then return SerializeTable(arg, depth, visited) end
    if t == "string"         then return '"' .. arg:sub(1, 80) .. '"' end
    if t == "Vector3"        then return ("V3(%.1f,%.1f,%.1f)"):format(arg.X, arg.Y, arg.Z) end
    if t == "CFrame"         then local p = arg.Position; return ("CF(%.1f,%.1f,%.1f)"):format(p.X, p.Y, p.Z) end
    if t == "EnumItem"       then return "Enum." .. tostring(arg) end
    return tostring(arg)
end

-- ============================================================
-- REMOTE SCANNER — deteksi & kategorisasi
-- ============================================================

-- Kategorikan satu remote ke RemoteMap
local function categorizeRemote(remote)
    local path = remote:GetFullName()

    -- Cek duplikat di all
    for _, r in ipairs(RemoteMap.all) do
        if r == remote then return end  -- udah ada
    end
    table.insert(RemoteMap.all, remote)

    -- Kategorikan (satu sumber kebenaran)
    local cat = remoteCategoryOf(remote)
    if cat then
        table.insert(RemoteMap[cat], remote)
        log(("REMOTE [%s] "):format(string.upper(cat)) .. path)
    else
        log("REMOTE [?] " .. path)
    end

    -- Sync ke shared data (dibaca hub)
    if cat then
        local data = _G.DMHubRemoteData[cat]
        local exists
        for _, e in ipairs(data) do
            if e.path == path then exists = true break end
        end
        if not exists then
            table.insert(data, {
                path        = path,
                className   = remote.ClassName,
                name        = remote.Name,
                fireCount   = 0,
                lastArgsRaw = nil,
                lastArgsStr = "",
                lastTime    = "",
            })
            syncSpyData()
        end
    end
end

-- Scan semua remote di game (full scan)
local function scanAllRemotes()
    log("Scanning semua remote di game...")
    local count = 0
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            pcall(categorizeRemote, obj)
            count = count + 1
        end
    end
    local msg = ("%d remote ditemukan | Farm:%d Cook:%d Serve:%d Buy:%d Unknown:%d"):format(
        count,
        #RemoteMap.farm, #RemoteMap.cook,
        #RemoteMap.serve, #RemoteMap.buy,
        #RemoteMap.all - #RemoteMap.farm - #RemoteMap.cook - #RemoteMap.serve - #RemoteMap.buy
    )
    log("Scan selesai: " .. msg)
    -- Kasih tau player buat tekan F11
    notify("Scan Selesai!", msg .. "\n\nTekan F11 untuk save ke file.", 8)
    print("[RemoteSpy] Tekan F11 untuk save remote map ke: " .. Config.SaveFileName)
end

-- Reset dan scan ulang
local function resetRemoteMap()
    RemoteMap.farm  = {}
    RemoteMap.cook  = {}
    RemoteMap.serve = {}
    RemoteMap.buy   = {}
    RemoteMap.all   = {}
    RemoteMap.logs  = {}
    scanAllRemotes()
end

-- ============================================================
-- NAMECALL HOOK — intercept FireServer/InvokeServer live
-- ============================================================
local oldNamecall = nil
local hookActive  = false

local function initHook()
    if hookActive then return end
    -- hookmetamethod hanya ada di executor (Synapse, Wave, dll)
    -- Kalau nggak ada, skip — fallback ke scan statis aja
    if not hookmetamethod then
        log("hookmetamethod tidak tersedia di executor ini — pakai scan statis")
        return
    end

    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args   = {...}

        if (method == "FireServer" or method == "InvokeServer")
        and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            -- Tambahkan ke RemoteMap kalau belum ada
            pcall(categorizeRemote, self)

            -- Simpan log (FIFO)
            if #RemoteMap.logs >= Config.MaxRemoteLogs then
                table.remove(RemoteMap.logs, 1)
            end
            local argStrs = {}
            for i, a in ipairs(args) do
                argStrs[i] = FormatArg(a)
            end
            table.insert(RemoteMap.logs, {
                time   = os.date("%H:%M:%S"),
                path   = self:GetFullName(),
                method = method,
                args   = table.concat(argStrs, ", "),
            })

            -- Update shared data (raw args biar hub bisa replay)
            local path = self:GetFullName()
            for catName, catData in pairs(_G.DMHubRemoteData) do
                if catName ~= "updated" and type(catData) == "table" then
                    for _, e in ipairs(catData) do
                        if e.path == path then
                            e.fireCount = e.fireCount + 1
                            e.lastArgsStr = table.concat(argStrs, ", ")
                            e.lastTime = os.date("%H:%M:%S")
                            local raw = {}
                            for i = 1, math.min(#args, RAW_ARGS_CAP) do
                                raw[i] = args[i]
                            end
                            e.lastArgsRaw = raw
                            syncSpyData()
                            break
                        end
                    end
                end
            end
        end

        -- Selalu panggil original — jangan pernah block
        return oldNamecall(self, ...)
    end)

    hookActive = true
    log("Namecall hook aktif — semua FireServer/InvokeServer akan dicatat")
end

-- ============================================================
-- DUMP REMOTE MAP (F11)
-- ============================================================
local function dumpRemoteMap()
    local lines = { "===== REMOTE MAP =====" }
    local cats = { {name="FARM", t=RemoteMap.farm}, {name="COOK", t=RemoteMap.cook},
                   {name="SERVE", t=RemoteMap.serve}, {name="BUY", t=RemoteMap.buy} }
    for _, cat in ipairs(cats) do
        lines[#lines+1] = "-- " .. cat.name .. " (" .. #cat.t .. ") --"
        for _, r in ipairs(cat.t) do
            pcall(function() lines[#lines+1] = "  " .. r:GetFullName() .. " [" .. r.ClassName .. "]" end)
        end
    end
    -- Unknown
    local known = {}
    for _, cat in ipairs(cats) do
        for _, r in ipairs(cat.t) do known[r] = true end
    end
    lines[#lines+1] = "-- UNKNOWN --"
    for _, r in ipairs(RemoteMap.all) do
        if not known[r] then
            pcall(function() lines[#lines+1] = "  " .. r:GetFullName() .. " [" .. r.ClassName .. "]" end)
        end
    end
    -- Log 10 terakhir
    lines[#lines+1] = "-- LOG TERAKHIR (10) --"
    local start = math.max(1, #RemoteMap.logs - 9)
    for i = start, #RemoteMap.logs do
        local e = RemoteMap.logs[i]
        if e then
            lines[#lines+1] = ("[%s] %s:%s(%s)"):format(e.time, e.path, e.method, e.args)
        end
    end
    print(table.concat(lines, "\n"))
    log("Remote map di-dump ke konsol.")
end

-- ============================================================
-- SAVE TO FILE
-- ============================================================
local function buildSaveContent()
    local lines = {}
    lines[#lines+1] = "======================================================"
    lines[#lines+1] = "  DEVIL'S MARKET — REMOTE MAP SAVE"
    lines[#lines+1] = "  Disimpan: " .. os.date("%Y-%m-%d %H:%M:%S")
    lines[#lines+1] = "======================================================"
    lines[#lines+1] = ""

    local cats = {
        { name = "FARM",  t = RemoteMap.farm  },
        { name = "COOK",  t = RemoteMap.cook  },
        { name = "SERVE", t = RemoteMap.serve },
        { name = "BUY",   t = RemoteMap.buy   },
    }

    for _, cat in ipairs(cats) do
        lines[#lines+1] = "-- " .. cat.name .. " (" .. #cat.t .. ") --"
        for _, r in ipairs(cat.t) do
            pcall(function()
                lines[#lines+1] = "  [" .. r.ClassName .. "] " .. r:GetFullName()
            end)
        end
        lines[#lines+1] = ""
    end

    -- Unknown
    local known = {}
    for _, cat in ipairs(cats) do
        for _, r in ipairs(cat.t) do known[r] = true end
    end
    lines[#lines+1] = "-- UNKNOWN (" .. (#RemoteMap.all - #RemoteMap.farm - #RemoteMap.cook - #RemoteMap.serve - #RemoteMap.buy) .. ") --"
    for _, r in ipairs(RemoteMap.all) do
        if not known[r] then
            pcall(function()
                lines[#lines+1] = "  [" .. r.ClassName .. "] " .. r:GetFullName()
            end)
        end
    end
    lines[#lines+1] = ""

    -- Log call terakhir (50 entry)
    lines[#lines+1] = "-- LOG CALL TERAKHIR (50) --"
    local start = math.max(1, #RemoteMap.logs - 49)
    for i = start, #RemoteMap.logs do
        local e = RemoteMap.logs[i]
        if e then
            lines[#lines+1] = ("[%s] %s:%s(%s)"):format(e.time, e.path, e.method, e.args)
        end
    end

    return table.concat(lines, "\n")
end

local function saveToFile()
    -- writefile() adalah API executor (Synapse/Wave/dll) — tidak ada di Roblox biasa
    if not writefile then
        log("writefile tidak tersedia di executor ini — skip save")
        return false
    end
    local ok, err = pcall(function()
        writefile(Config.SaveFileName, buildSaveContent())
    end)
    if ok then
        log("Disimpan ke: " .. Config.SaveFileName)
    else
        log("Gagal save: " .. tostring(err))
    end
    return ok
end

-- Auto-save loop (jalan di background)
local function startAutoSave()
    if Config.AutoSaveInterval <= 0 then return end
    task.spawn(function()
        while true do
            task.wait(Config.AutoSaveInterval)
            pcall(saveToFile)
        end
    end)
    log("Auto-save aktif setiap " .. Config.AutoSaveInterval .. "s → " .. Config.SaveFileName)
end

-- ============================================================
-- KEYBINDS
-- ============================================================
UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local k = input.KeyCode
    if     k == Enum.KeyCode.F9  then dumpRemoteMap()
    elseif k == Enum.KeyCode.F11 then dumpRemoteMap(); saveToFile()
    elseif k == Enum.KeyCode.F12 then resetRemoteMap()
    end
end)

-- ============================================================
-- INIT
-- ============================================================
print("==========================================")
print("  REMOTE SPY — Devil's Market — LOADING")
print("==========================================")

-- 1. Scan remote statis dulu
task.spawn(scanAllRemotes)

-- 2. Aktifkan hook namecall (kalau executor support)
task.spawn(initHook)

-- 3. Listen kalau ada remote baru masuk (DescendantAdded)
game.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        pcall(categorizeRemote, obj)
    end
end)

-- 4. Auto-save
task.spawn(startAutoSave)

print("  F9  Dump Remote Map")
print("  F11 Dump + Save ke file")
print("  F12 Rescan Remote")
print("------------------------------------------")
print("  Data di-share ke hub via _G.DMHubRemoteData")
print("  (jalanin devil_market_hub.lua buat auto pakai remote)")
print("==========================================")
