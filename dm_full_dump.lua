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

-- State yang di-share ke UI
local DumpState = {
    phase     = "idle",      -- idle / tree / remotes / stats / logic / hook / done
    files     = {},          -- { name, size }
    remotes   = 0,
    scripts   = 0,
    logsCount = 0,
    startedAt = os.clock(),
}

local function saveFile(name, content)
    local ok, err = pcall(function()
        writefile(name, content)
    end)
    if ok then
        print("[FULLDUMP] OK  " .. name .. "  (" .. math.floor(#content / 1024) .. " KB)")
        DumpState.files[#DumpState.files+1] = {
            name = name,
            size = math.floor(#content / 1024),
        }
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
    DumpState.remotes = #all

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
    DumpState.scripts = total
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
    DumpState.logsCount = DumpState.logsCount + #lines
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
    local wrap = newcclosure or function(f) return f end
    local old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        local args = {...}
        pcall(function()
            local method = getnamecallmethod()
            if (method == "FireServer" or method == "InvokeServer")
            and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
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
-- UI — panel status (HP friendly)
-- ============================================================
local UI = {}

local function buildUI()
    local existing = LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("DumpUI")
    if existing then existing:Destroy() end
    local PlayerGui = LP:WaitForChild("PlayerGui", 10)
    if not PlayerGui then return end

    local screen = Instance.new("ScreenGui")
    screen.Name           = "DumpUI"
    screen.ResetOnSpawn   = false
    screen.DisplayOrder   = 995
    screen.IgnoreGuiInset = true
    screen.Parent         = PlayerGui

    local frame = Instance.new("Frame")
    frame.Name            = "Main"
    frame.Size            = UDim2.new(0, 260, 0, 240)
    frame.Position        = UDim2.new(1, -270, 0, 45)
    frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    frame.BorderSizePixel = 0
    frame.Active          = true
    frame.Draggable       = true
    frame.Parent          = screen

    local title = Instance.new("TextLabel")
    title.Size            = UDim2.new(1, -28, 0, 24)
    title.Position        = UDim2.new(0, 4, 0, 0)
    title.BackgroundTransparency = 1
    title.Text            = "FULL DUMP"
    title.TextColor3      = Color3.fromRGB(255, 200, 120)
    title.TextSize        = 13
    title.Font            = Enum.Font.GothamBold
    title.TextXAlignment  = Enum.TextXAlignment.Left
    title.Parent          = frame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size         = UDim2.new(0, 24, 0, 24)
    closeBtn.Position     = UDim2.new(1, -26, 0, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text         = "X"
    closeBtn.TextColor3   = Color3.fromRGB(255,255,255)
    closeBtn.TextSize     = 11
    closeBtn.Font         = Enum.Font.GothamBold
    closeBtn.Parent       = frame
    closeBtn.MouseButton1Click:Connect(function() screen:Destroy() end)

    local status = Instance.new("TextLabel")
    status.Name           = "Status"
    status.Size           = UDim2.new(1, -8, 0, 80)
    status.Position       = UDim2.new(0, 4, 0, 26)
    status.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    status.BorderSizePixel = 0
    status.Text           = "phase: idle"
    status.TextColor3     = Color3.fromRGB(200, 220, 200)
    status.TextSize       = 11
    status.Font           = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.TextWrapped    = true
    status.Parent         = frame

    local files = Instance.new("TextLabel")
    files.Name            = "Files"
    files.Size            = UDim2.new(1, -8, 0, 70)
    files.Position        = UDim2.new(0, 4, 0, 108)
    files.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    files.BorderSizePixel = 0
    files.Text            = "belum ada file"
    files.TextColor3      = Color3.fromRGB(160, 200, 255)
    files.TextSize        = 10
    files.Font            = Enum.Font.Gotham
    files.TextXAlignment  = Enum.TextXAlignment.Left
    files.TextYAlignment  = Enum.TextYAlignment.Top
    files.TextWrapped     = true
    files.Parent          = frame

    local reBtn = Instance.new("TextButton")
    reBtn.Size            = UDim2.new(0, 120, 0, 30)
    reBtn.Position        = UDim2.new(0, 4, 0, 182)
    reBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 140)
    reBtn.BorderSizePixel = 0
    reBtn.Text            = "Re-Dump"
    reBtn.TextColor3      = Color3.fromRGB(220, 220, 255)
    reBtn.TextSize        = 12
    reBtn.Font            = Enum.Font.GothamBold
    reBtn.Parent          = frame
    reBtn.MouseButton1Click:Connect(function()
        DumpState.phase = "tree";    pcall(dumpTree)
        DumpState.phase = "remotes"; pcall(dumpRemotes)
        DumpState.phase = "stats";   pcall(dumpStats)
        DumpState.phase = "logic";   pcall(dumpLogic)
        DumpState.phase = "done"
        UI.status.Text = "Re-dump selesai!"
    end)

    local closeAll = Instance.new("TextButton")
    closeAll.Size        = UDim2.new(0, 120, 0, 30)
    closeAll.Position    = UDim2.new(0, 130, 0, 182)
    closeAll.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
    closeAll.BorderSizePixel = 0
    closeAll.Text        = "Tutup"
    closeAll.TextColor3  = Color3.fromRGB(255,255,255)
    closeAll.TextSize    = 12
    closeAll.Font        = Enum.Font.GothamBold
    closeAll.Parent      = frame
    closeAll.MouseButton1Click:Connect(function() screen:Destroy() end)

    UI.frame = frame
    UI.status = status
    UI.files = files

    -- Auto-refresh tiap 2 detik
    task.spawn(function()
        while screen and screen.Parent do
            task.wait(2)
            pcall(function()
                local elapsed = math.floor(os.clock() - DumpState.startedAt)
                UI.status.Text = string.format(
                    "phase: %s\nremote: %d | script: %d\nhook log: %d\nwaktu: %ds",
                    DumpState.phase, DumpState.remotes, DumpState.scripts,
                    DumpState.logsCount, elapsed)
                local fLines = {}
                for i, f in ipairs(DumpState.files) do
                    fLines[#fLines+1] = ("%s (%d KB)"):format(f.name, f.size)
                end
                UI.files.Text = #fLines == 0 and "belum ada file" or table.concat(fLines, "\n")
            end)
        end
    end)
    print("[FULLDUMP] UI aktif")
end

task.spawn(buildUI)

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
    DumpState.phase = "tree";    pcall(dumpTree)
    DumpState.phase = "remotes"; pcall(dumpRemotes)
    DumpState.phase = "stats";   pcall(dumpStats)
    DumpState.phase = "logic";   pcall(dumpLogic)
    DumpState.phase = "hook";    pcall(initHook)
    DumpState.phase = "done"
    print("==========================================")
    print("  DUMP SELESAI. File di folder Delta:")
    print("  dm_instances.txt  dm_remotes.txt")
    print("  dm_stats.txt      dm_logic_all.txt")
    print("  dm_logic_everything.txt  dm_logic_*.lua")
    print("  dm_remote_logs.txt (nambah terus)")
    print("==========================================")
    notify("Dump selesai! Buka folder Delta & kirim file-nya", 8)
end)
