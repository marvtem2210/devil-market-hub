--[[
  ============================================================
  DM STATS PROBE — Devil's Market (Pasar Setan)
  Langkah 1 dari pembuatan script KAITUN (auto level 1-max)

  Fungsi:
    1. Dump struktur stats player (leaderstats / custom)
       → tau di mana LEVEL, XP, dan UANG disimpan
    2. Monitor perubahan nilai (poll tiap 2 detik)
       → nilai yang naik pas kita main = XP/uang/level
    3. Output: konsol + file DMStatsProbe.txt + notif

  Cara pakai di Delta:
    1. Masuk game Devil's Market
    2. Load script ini
    3. Main normal 1-2 menit (tanam, panen, jual)
    4. Tekan F9 → dump status lengkap ke konsol + file
    5. Kasih tau hasilnya ke pembuat script (gue)
  ============================================================
]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local UIS = game:GetService("UserInputService")

local lines = {}
local function add(fmt, ...)
    lines[#lines+1] = fmt:format(...)
end

-- ============================================================
-- 1) DUMP STATIS — struktur stats player
-- ============================================================
local function dumpValue(inst, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local info = inst.ClassName
    if inst:IsA("IntValue") or inst:IsA("NumberValue") or inst:IsA("DoubleValue") then
        info = info .. " = " .. tostring(inst.Value)
    elseif inst:IsA("StringValue") then
        info = info .. ' = "' .. tostring(inst.Value) .. '"'
    elseif inst:IsA("BoolValue") then
        info = info .. " = " .. tostring(inst.Value)
    end
    add("%s%s [%s] %s", pad, inst.Name, inst.ClassName, info)
    for _, child in ipairs(inst:GetChildren()) do
        dumpValue(child, indent + 1)
    end
end

local function dumpStats()
    lines = {}
    add("===== DM STATS PROBE =====")
    add("game: %s", game:GetService("MarketplaceService") and game:GetService("GameInfo") and "?" or "?")
    pcall(function()
        add("PlaceId: %d", game.PlaceId)
        add("Player: %s (UserId %d)", LP.Name, LP.UserId)
    end)

    -- Leaderstats standar
    local ls = LP:FindFirstChild("leaderstats")
    if ls then
        add("")
        add("-- leaderstats --")
        dumpValue(ls, 1)
    else
        add("")
        add("-- leaderstats TIDAK ADA — cek value di LocalPlayer --")
    end

    -- Value langsung di LocalPlayer (custom storage)
    local foundCustom = false
    for _, child in ipairs(LP:GetChildren()) do
        if child:IsA("ValueBase") then
            if not foundCustom then
                add("")
                add("-- value di LocalPlayer (custom) --")
                foundCustom = true
            end
            dumpValue(child, 1)
        end
    end
    if not foundCustom and not ls then
        add("  (gak ada value ketemu di LP — cek PlayerData di ReplicatedStorage)")
    end

    -- Data di ReplicatedStorage (seringnya tempat nyimpen stats)
    pcall(function()
        local RS = game:GetService("ReplicatedStorage")
        for _, child in ipairs(RS:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Configuration") or child:IsA("Model") then
                if child.Name:lower():find("data") or child.Name:lower():find("save")
                or child.Name:lower():find("player") or child.Name:lower():find("stat") then
                    add("")
                    add("-- ReplicatedStorage/%s --", child.Name)
                    dumpValue(child, 1)
                end
            end
        end
    end)

    -- Atribut player (GetAttributes)
    pcall(function()
        local attrs = LP:GetAttributes()
        local n = 0
        for k, v in pairs(attrs) do
            if n == 0 then add(""); add("-- attributes LocalPlayer --") end
            add("  attr %s = %s", k, tostring(v))
            n = n + 1
        end
        if n > 0 then add("  (total %d attributes)", n) end
    end)

    add("")
    add("============================")
end

-- ============================================================
-- 2) MONITOR — nilai yang berubah = stats penting
-- ============================================================
local watched = {}  -- { obj, name, lastValue }

local function collectValues()
    local list = {}
    local function walk(inst)
        if inst:IsA("IntValue") or inst:IsA("NumberValue") or inst:IsA("DoubleValue") then
            list[#list+1] = inst
        end
        for _, c in ipairs(inst:GetChildren()) do
            walk(c)
        end
    end
    local ls = LP:FindFirstChild("leaderstats")
    if ls then walk(ls) end
    for _, c in ipairs(LP:GetChildren()) do
        if c:IsA("ValueBase") then list[#list+1] = c end
    end
    pcall(function()
        local RS = game:GetService("ReplicatedStorage")
        for _, c in ipairs(RS:GetChildren()) do
            if c.Name:lower():find("data") or c.Name:lower():find("player") then
                walk(c)
            end
        end
    end)
    return list
end

local function refreshWatched()
    watched = {}
    for _, v in ipairs(collectValues()) do
        watched[#watched+1] = { obj = v, last = v.Value }
    end
    add("Monitor: %d nilai di-track", #watched)
end

-- Poll tiap 2 detik, tampilkan perubahan
task.spawn(function()
    task.wait(1)
    pcall(refreshWatched)
    while true do
        task.wait(2)
        pcall(function()
            for _, w in ipairs(watched) do
                if w.obj and w.obj.Parent then
                    local now = w.obj.Value
                    if now ~= w.last then
                        local delta = now - w.last
                        local arah = delta > 0 and "NAIK" or "TURUN"
                        print(string.format("[MONITOR] %s %s: %s -> %s (%s%d)",
                            arah, w.obj:GetFullName(), tostring(w.last), tostring(now),
                            delta > 0 and "+" or "", delta))
                        -- Notif tipis buat yang penting (biar kelihatan di HP)
                        pcall(function()
                            game:GetService("StarterGui"):SetCore("SendNotification", {
                                Title = "Probe",
                                Text = ("%s %s %s%d"):format(arah, w.obj.Name, delta > 0 and "+" or "", delta),
                                Duration = 3,
                            })
                        end)
                        w.last = now
                    end
                end
            end
        end)
    end
end)

-- ============================================================
-- 3) OUTPUT
-- ============================================================
local function outputAll()
    dumpStats()
    local out = table.concat(lines, "\n")
    print(out)
    pcall(function() writefile("DMStatsProbe.txt", out) end)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Stats Probe",
            Text = "Dump selesai → DMStatsProbe.txt",
            Duration = 6,
        })
    end)
end

-- F9 = dump ulang
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F9 then
        outputAll()
    end
end)

print("==========================================")
print("  DM STATS PROBE — load selesai")
print("  Monitor jalan tiap 2 detik...")
print("  Tekan F9 buat dump lengkap")
print("==========================================")

-- Dump pertama otomatis (biar langsung keliatan strukturnya)
task.wait(2)
outputAll()
