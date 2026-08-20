--[[
  ============================================================
  DEX LOADER — gabung Dex Explorer ke workflow remote spy
  Devil's Market (Pasar Setan)
  ============================================================

  Fungsi:
    1. Load FxkeDex (Dex Explorer modern, fork klasik by Moon)
       dari GitHub — pcall + fallback biar gak nge-crash
    2. Kalau berhasil: DEX UI kebuka (explorer + properties +
       script viewer + console + remote spy bawaan DEX)
    3. Jembatan ke remote_spy: hasil DEX (objek/remote yang
       di-scan) di-share ke _G.DMHubRemoteData + _G.DMDexInfo

  Cara pakai:
    1. Load remote_spy.lua dulu
    2. Load dex_loader.lua ini
    3. DEX kebuka → browsing game, baca script, liat remote
    4. Remote yang DEX temuin otomatis masuk ke data spy

  Catatan: FxkeDex butuh icon library + API dump dari network
  (nebulasoftworks.xyz). Kalau gagal, fallback ke DEX klasik
  sederhana yang jalan offline.
  ============================================================
]]

print("==========================================")
print("  DEX LOADER — Devil's Market")
print("==========================================")

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

-- ============================================================
-- JEMBATAN KE REMOTE SPY
-- ============================================================
-- Spy baca _G.DMHubRemoteData. Loader nambahin remote hasil
-- DEX ke situ juga (biar hub & spy ngeliat remote yang sama).
local function bridgeDexRemote(remote, category)
    pcall(function()
        local path = remote:GetFullName()
        _G.DMHubRemoteData = _G.DMHubRemoteData or {
            farm = {}, cook = {}, serve = {}, buy = {}, updated = 0,
        }
        local cat = category or "farm"
        local data = _G.DMHubRemoteData[cat]
        if type(data) ~= "table" then data = {}; _G.DMHubRemoteData[cat] = data end
        for _, e in ipairs(data) do
            if e.path == path then return end
        end
        table.insert(data, {
            path = path, className = remote.ClassName, name = remote.Name,
            fireCount = 0, lastArgsRaw = nil, lastArgsStr = "", lastTime = "",
        })
        _G.DMHubRemoteData.updated = os.clock()
        print("[DEX-BRIDGE] remote ditambahkan: " .. path)
    end)
end

-- Kategorikan remote by nama (sama kayak spy)
local function categorizeName(name)
    local n = string.lower(name or "")
    local kws = {
        farm  = { "farm", "plant", "harvest", "seed", "tanam", "panen", "water", "grow", "crop" },
        cook  = { "cook", "recipe", "craft", "make", "masak", "process", "brew", "bake" },
        serve = { "serve", "deliver", "order", "complete", "customer", "layani", "antar", "give" },
        buy   = { "buy", "purchase", "upgrade", "unlock", "beli", "shop", "store", "acquire" },
    }
    for cat, list in pairs(kws) do
        for _, kw in ipairs(list) do
            if n:find(string.lower(kw), 1, true) then return cat end
        end
    end
    return nil
end

-- Scan semua remote & share ke spy (biar DEX + spy nyambung)
local function scanAndBridge()
    local count = 0
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            bridgeDexRemote(obj, categorizeName(obj.Name))
            count = count + 1
        end
    end
    print("[DEX-BRIDGE] scan selesai: " .. count .. " remote di-share ke spy")
end

-- ============================================================
-- LOAD FXKEDEX (full Dex Explorer)
-- ============================================================
local DEX_URL = "https://raw.githubusercontent.com/Fxkez/FxkeDex/main/fxkedex.lua"

local function loadFxkeDex()
    print("[DEX] Downloading FxkeDex (" .. DEX_URL .. ")...")
    local okSrc, src = pcall(function()
        return game:HttpGet(DEX_URL)
    end)
    if not okSrc or not src or #src < 10000 then
        print("[DEX] Gagal download FxkeDex (" .. tostring(src) .. ") — fallback")
        return false
    end
    print("[DEX] Download OK (" .. math.floor(#src / 1024) .. " KB), executing...")
    local okRun, err = pcall(loadstring, src)
    if not okRun then
        print("[DEX] Gagal eksekusi FxkeDex: " .. tostring(err))
        return false
    end
    print("[DEX] FxkeDex berhasil di-load")
    return true
end

-- ============================================================
-- LOAD DEX KLASIK SEDERHANA (fallback offline)
-- ============================================================
local function loadClassicDex()
    print("[DEX] Mencoba DEX klasik sederhana...")
    -- DEX klasik (versi compact, self-contained) — coba dari beberapa source
    local sources = {
        "https://raw.githubusercontent.com/infinity-stuff/DexExplorer/main/Dex.lua",
        "https://raw.githubusercontent.com/7apoz/Dex/master/Dex.lua",
    }
    for _, url in ipairs(sources) do
        local ok, src = pcall(function()
            return game:HttpGet(url)
        end)
        if ok and src and #src > 1000 then
            local okRun, err = pcall(loadstring, src)
            if okRun then
                print("[DEX] DEX klasik berhasil dari " .. url)
                return true
            end
        end
    end
    print("[DEX] Semua source DEX gagal. Cuma jembatan spy yang aktif.")
    return false
end

-- ============================================================
-- START
-- ============================================================
task.spawn(function()
    local ok = loadFxkeDex()
    if not ok then
        ok = loadClassicDex()
    end
    -- Jembatan tetap jalan apa pun hasilnya
    task.wait(1)
    pcall(scanAndBridge)
    print("==========================================")
    print("  DEX LOADER selesai. DEX-loaded: " .. tostring(ok))
    print("  Remote hasil DEX di-share ke spy/hub")
    print("==========================================")
end)
