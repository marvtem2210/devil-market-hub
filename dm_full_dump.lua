--[[
  ============================================================
  DM FULL DUMP — Devil's Market (Pasar Setan)
  Semua ke-dump OTOMATIS ke file txt, tanpa kerja manual.
  Buat HP (Delta): load → tunggu → buka folder Delta → kirim file.
  ============================================================

  FILE YANG DIHASILKAN (folder workspace Delta):
    dm_instances.txt      — struktur instance lengkap (tree)
    dm_remotes.txt        — semua RemoteEvent/RemoteFunction
                            + kategori (farm/cook/serve/buy)
    dm_stats.txt          — leaderstats + value player
    dm_logic_all.txt      — SEMUA source script/module digabung
                            (recipe, remote, data, level, dll)
    dm_logic_<nama>.lua   — tiap script/module file terpisah
    dm_remote_logs.txt    — hook live: FireServer/InvokeServer
                            + args (auto-save tiap 30 detik)

  Catatan: semua pcall → kalau satu gagal, sisanya tetap jalan.
  ============================================================
]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local function saveFile(name, content)
    local ok, err = pcall(function()
        writefile(name, content)
    end)
    if ok then
        print("[FULLDUMP] OK  " .. name .. "  (" .. math.floor(#content / 1024) .. " KB)")
    else
        print("[FULLDUMP] GAGAL " .. name .. "  " .. tostring(err))
    end
    return ok
end

local function notify(text, dur)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Full Dump",
            Text  = text,
            Duration = dur or 5,
        })
    end)
end

-- ============================================================
-- 1) TREE INSTANCE — struktur lengkap
-- ============================================================
local function dumpTree()
    local lines = {}
    local function walk(inst, depth)
        if depth > 12 then return end
        local pad = string.rep("  ", depth)
        local val = ""
        if inst:IsA("IntValue") or inst:IsA("NumberValue") or inst:IsA("DoubleValue") then
            val = " = " .. tostring(inst.Value)
        elseif inst:IsA("StringValue") then
            val = ' = "' .. tostring(inst.Value) .. '"'
        elseif inst:IsA("BoolValue") then
            val = " = " .. tostring(inst.Value)
        end
        lines[#lines+1] = ("%s%s [%s]%s"):format(pad, inst.Name, inst.ClassName, val)
        if inst.ClassName ~= "Script" and inst.ClassName ~= "LocalScript"
        and inst.ClassName ~= "ModuleScript" then
            for _, c in ipairs(inst:GetChildren()) do
                walk(c, depth + 1)
            end
        end
    end
    local roots = {
        game:GetService("ReplicatedStorage"),
        game:GetService("ReplicatedFirst"),
        game:GetService("Workspace"),
        game:GetService("Players"),
        LP,
    }
    for _, r in ipairs(roots) do
        pcall(function()
            lines[#lines+1] = ""
            lines[#lines+1] = "----- " .. r:GetFullName() .. " -----"
            for _, c in ipairs(r:GetChildren()) do
                walk(c, 1)
            end
        end)
    end
    saveFile("dm_instances.txt", table.concat(lines, "\n"))
end

-- ============================================================
-- 2) REMOTES — semua + kategori
-- ============================================================
local REMOTE_KW = {
    farm  = { "farm", "plant", "harvest", "seed", "tanam", "panen", "water", "grow", "crop" },
    cook  = { "cook", "recipe", "craft", "make", "masak", "process", "brew", "bake" },
    serve = { "serve", "deliver", "order", "complete", "customer", "layani", "antar", "give" },
    buy   = { "buy", "purchase", "upgrade", "unlock", "beli", "shop", "store", "acquire" },
}

local function remoteCat(name)
    local n = string.lower(name or "")
    for cat, kws in pairs(REMOTE_KW) do
        for _, kw in ipairs(kws) do
            if n:find(kw, 1, true) then return cat end
        end
    end
    return "?"
end

local function dumpRemotes()
    local all = {}
    local byCat = { farm = {}, cook = {}, serve = {}, buy = {}, ["?"] = {} }
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local cat = remoteCat(obj.Name)
            table.insert(byCat[cat], ("[%s] %s"):format(obj.ClassName, obj:GetFullName()))
            table.insert(all, ("[%s][%s] %s"):format(string.upper(cat), obj.ClassName, obj:GetFullName()))
        end
    end
    local lines = {
        "======================================================",
        "  DEVIL'S MARKET — REMOTE DUMP",
        "  Di-generate: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "======================================================",
        "",
        ("TOTAL: %d remote"):format(#all),
        "",
    }
    for cat, list in pairs(byCat) do
        table.sort(list)
        lines[#lines+1] = ("-- %s (%d) --"):format(string.upper(cat), #list)
        for _, l in ipairs(list) do lines[#lines+1] = "  " .. l end
        lines[#lines+1] = ""
    end
    lines[#lines+1] = "-- SEMUA (urut) --"
    for _, l in ipairs(all) do lines[#lines+1] = "  " .. l end
    saveFile("dm_remotes.txt", table.concat(lines, "\n"))

    -- Share ke _G buat hub/spy kalau ada
    pcall(function()
        _G.DMHubRemoteData = _G.DMHubRemoteData or {
            farm = {}, cook = {}, serve = {}, buy = {}, updated = 0,
        }
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local cat = remoteCat(obj.Name)
                if cat ~= "?" then
                    local path = obj:GetFullName()
                    local data = _G.DMHubRemoteData[cat]
                    local dup
                    for _, e in ipairs(data) do
                        if e.path == path then dup = true break end
                    end
                    if not dup then
                        table.insert(data, {
                            path = path, className = obj.ClassName, name = obj.Name,
                            fireCount = 0, lastArgsRaw = nil, lastArgsStr = "", lastTime = "",
                        })
                    end
                end
            end
        end
        _G.DMHubRemoteData.updated = os.clock()
    end)
end

-- ============================================================
-- 3) STATS — leaderstats + value player
-- ============================================================
local function dumpStats()
    local lines = {}
    local function walk(inst, depth)
        local pad = string.rep("  ", depth)
        local val = ""
        if inst:IsA("IntValue") or inst:IsA("NumberValue") or inst:IsA("DoubleValue") then
            val = " = " .. tostring(inst.Value)
        elseif inst:IsA("StringValue") then
            val = ' = "' .. tostring(inst.Value) .. '"'
        elseif inst:IsA("BoolValue") then
            val = " = " .. tostring(inst.Value)
        end
        lines[#lines+1] = ("%s%s [%s]%s"):format(pad, inst.Name, inst.ClassName, val)
        for _, c in ipairs(inst:GetChildren()) do
            walk(c, depth + 1)
        end
    end
    lines[#lines+1] = "===== STATS PLAYER: " .. LP.Name .. " ====="
    local ls = LP:FindFirstChild("leaderstats")
    if ls then
        lines[#lines+1] = "-- leaderstats --"
        walk(ls, 1)
    else
        lines[#lines+1] = "(leaderstats TIDAK ADA)"
    end
    lines[#lines+1] = ""
    lines[#lines+1] = "-- Value di LocalPlayer --"
    for _, c in ipairs(LP:GetChildren()) do
        if c:IsA("ValueBase") then
            lines[#lines+1] = "  " .. c:GetFullName() .. " = " .. tostring(c.Value)
        end
    end
    -- Attributes
    pcall(function()
        local attrs = LP:GetAttributes()
        local n = 0
        for k, v in pairs(attrs) do
            if n == 0 then lines[#lines+1] = ""; lines[#lines+1] = "-- Attributes --" end
            lines[#lines+1] = "  " .. k .. " = " .. tostring(v)
            n = n + 1
        end
    end)
    saveFile("dm_stats.txt", table.concat(lines, "\n"))
end

-- ============================================================
-- 4) LOGIC — semua source script/module
-- ============================================================
local LOGIC_KEYWORDS = {
    "recipe", "craft", "cook", "food", "menu", "product",
    "remote", "network", "api", "event",
    "data", "save", "playerdata", "profile", "stat",
    "level", "xp", "exp", "rank",
    "inventory", "item", "material", "ingredient",
    "upgrade", "shop", "store", "price", "market", "economy",
    "config", "settings", "manager", "service", "handler",
    "main", "init", "client", "server", "loader", "game",
}

local function matchesKw(name)
    local n = string.lower(name or "")
    for _, kw in ipairs(LOGIC_KEYWORDS) do
        if n:find(kw, 1, true) then return true end
    end
    return false
end

local function getSource(inst)
    local ok, src = pcall(function() return inst.Source end)
    if ok and type(src) == "string" and #src > 0 then return src end
    local ok2, s2 = pcall(function()
        if decompile then return decompile(inst) end
        if getscriptbytecode then return getscriptbytecode(inst) end
        return nil
    end)
    if ok2 and type(s2) == "string" and #s2 > 0 then
        return s2 .. "\n-- [decompiled]"
    end
    return nil
end

local function dumpLogic()
    local combined = {}
    local combinedSize = 0
    local savedSeparate = 0
    local total = 0

    for _, root in ipairs({
        game:GetService("ReplicatedStorage"),
        game:GetService("ReplicatedFirst"),
        game:GetService("Workspace"),
        game:GetService("StarterGui"),
        game:GetService("StarterPack"),
        LP,
    }) do
        pcall(function()
            for _, inst in ipairs(root:GetDescendants()) do
                if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
                    total = total + 1
                    if matchesKw(inst.Name) then
                        local src = getSource(inst)
                        if src and #src >= 50 and #src <= 300000 then
                            local header = ("--===== %s [%s] (%d chars) =====--\n"):format(
                                inst:GetFullName(), inst.ClassName, #src)
                            combined[#combined+1] = header .. src .. "\n\n"
                            combinedSize = combinedSize + #header + #src
                            -- File terpisah
                            local fname = ("dm_logic_%s.lua"):format(
                                inst.Name:gsub("[^%w_]", "_"):sub(1, 40))
                            pcall(function() writefile(fname, header .. src) end)
                            savedSeparate = savedSeparate + 1
                        end
                    end
                end
            end
        end)
    end

    -- Semua script (termasuk yang gak match keyword) → 1 file raksasa
    local everything = {}
    local everythingSize = 0
    pcall(function()
        for _, root in ipairs({
            game:GetService("ReplicatedStorage"),
            game:GetService("ReplicatedFirst"),
            game:GetService("Workspace"),
            game:GetService("StarterGui"),
            game:GetService("StarterPack"),
            LP,
        }) do
            for _, inst in ipairs(root:GetDescendants()) do
                if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
                    local src = getSource(inst)
                    if src and #src >= 50 and #src <= 300000 then
                        everything[#everything+1] = ("--===== %s [%s] =====--\n%s\n\n"):format(
                            inst:GetFullName(), inst.ClassName, src)
                        everythingSize = everythingSize + #src
                    end
                end
            end
        end
    end)

    saveFile("dm_logic_all.txt", table.concat(combined, "\n"))
    saveFile("dm_logic_everything.txt", table.concat(everything, "\n"))
    print(string.format("[FULLDUMP] total script: %d | match: %d file terpisah | gabungan: %.1f MB",
        total, savedSeparate, everythingSize / 1048576))
end

-- ============================================================
-- 5) HOOK LIVE — FireServer/InvokeServer + args → file
-- ============================================================
local logs = {}
local LOG_MAX = 2000

local FormatArg
local function SerializeTable(tbl, depth, visited)
    depth, visited = depth or 0, visited or {}
    if depth >= 4 then return "{...}" end
    if visited[tbl] then return "{CIRCULAR}" end
    visited[tbl] = true
    local parts = {}
    for k, v in pairs(tbl) do
        local ks = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
        parts[#parts+1] = ks .. "=" .. FormatArg(v, depth + 1, visited)
    end
    return #parts == 0 and "{}" or ("{" .. table.concat(parts, ", ") .. "}")
end
FormatArg = function(arg, depth, visited)
    depth, visited = depth or 0, visited or {}
    if arg == nil then return "nil" end
    local t = typeof(arg)
    if t == "Instance" then
        return "Inst(" .. (pcall(function() return arg:GetFullName() end) and arg:GetFullName() or "?") .. ")"
    elseif t == "table" then return SerializeTable(arg, depth, visited)
    elseif t == "string" then return '"' .. arg:sub(1, 100) .. '"'
    elseif t == "Vector3" then return ("V3(%.1f,%.1f,%.1f)"):format(arg.X, arg.Y, arg.Z)
    elseif t == "CFrame" then local p = arg.Position; return ("CF(%.1f,%.1f,%.1f)"):format(p.X, p.Y, p.Z)
    elseif t == "EnumItem" then return "Enum." .. tostring(arg)
    end
    return tostring(arg)
end

local function flushLogs()
    if #logs == 0 then return end
    local lines = {}
    for _, e in ipairs(logs) do
        lines[#lines+1] = ("[%s] %s:%s(%s)"):format(e.time, e.path, e.method, e.args)
    end
    logs = {}
    local ok = pcall(function()
        local prev = readfile and readfile("dm_remote_logs.txt") or ""
        writefile("dm_remote_logs.txt", prev .. table.concat(lines, "\n") .. "\n")
    end)
    if not ok then
        pcall(function() writefile("dm_remote_logs.txt", table.concat(lines, "\n") .. "\n") end)
    end
end

local function initHook()
    if not hookmetamethod or not getnamecallmethod then
        print("[FULLDUMP] hookmetamethod gak ada — log live skip, dump statis tetap jalan")
        return
    end
    local old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        pcall(function()
            local method = getnamecallmethod()
            if (method == "FireServer" or method == "InvokeServer")
            and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
                local args = {...}
                local strs = {}
                for i = 1, math.min(#args, 12) do
                    strs[i] = FormatArg(args[i])
                end
                if #logs >= LOG_MAX then table.remove(logs, 1) end
                table.insert(logs, {
                    time = os.date("%H:%M:%S"),
                    path = self:GetFullName(),
                    method = method,
                    args = table.concat(strs, ", "),
                })
            end
        end)
        return old(self, ...)
    end))
    print("[FULLDUMP] Hook live AKTIF")
end

-- Flush tiap 30 detik
task.spawn(function()
    while true do
        task.wait(30)
        pcall(flushLogs)
    end
end)

-- ============================================================
-- INIT
-- ============================================================
print("==========================================")
print("  DM FULL DUMP — Devil's Market")
print("  Semua di-dump otomatis ke file txt")
print("==========================================")

-- Header file log
pcall(function() writefile("dm_remote_logs.txt",
    "-- DM REMOTE LOGS — " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n") end)

-- Urutan: instans → remote → stats → logic → hook
task.spawn(function()
    notify("Mulai dump...", 3)
    task.wait(1)
    pcall(dumpTree)
    pcall(dumpRemotes)
    pcall(dumpStats)
    pcall(dumpLogic)
    pcall(initHook)
    print("==========================================")
    print("  DUMP SELESAI. File di folder Delta:")
    print("  dm_instances.txt  dm_remotes.txt")
    print("  dm_stats.txt      dm_logic_all.txt")
    print("  dm_logic_everything.txt  dm_logic_*.lua")
    print("  dm_remote_logs.txt (nambah terus)")
    print("==========================================")
    notify("Dump selesai! Buka folder Delta & kirim file-nya", 8)
end)
