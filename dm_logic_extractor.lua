--[[
  ============================================================
  DM LOGIC EXTRACTOR — Devil's Market (Pasar Setan)
  Versi HP: baca logic game LANGSUNG di dalem game.
  Gak butuh PC / Roblox Studio.
  ============================================================

  Fungsi:
    1. Scan ReplicatedStorage + semua service buat modul/script
       yang penting (recipe, remote, data, save, stats, level,
       inventory, config, upgrade)
    2. Baca SOURCE-nya (decompile kalau perlu)
    3. Tampilkan di UI in-game: list modul → tap → baca source
       (scroll, touch-friendly)
    4. Tombol: Copy (setclipboard), Save semua (writefile)

  Cara pakai:
    1. Masuk Devil's Market
    2. Load script ini di Delta
    3. UI kebuka → tap modul → baca kodenya
    4. Screenshot / copy → kirim ke pembuat script

  Catatan: cuma LocalScript + ModuleScript yang kebaca
  (yang dikirim Roblox ke client). Script server gak.
  ============================================================
]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local UIS = game:GetService("UserInputService")

-- ============================================================
-- KEYWORD — modul yang penting buat kaitun
-- ============================================================
local KEYWORDS = {
    "recipe", "craft", "cook", "food", "menu", "product",
    "remote", "network", "api", "event",
    "data", "save", "playerdata", "profile", "stat",
    "level", "xp", "exp", "rank",
    "inventory", "item", "material", "ingredient",
    "upgrade", "shop", "store", "price", "market", "economy",
    "config", "settings", "manager", "service", "handler",
}

local function matchesKeywords(name)
    local n = string.lower(name or "")
    for _, kw in ipairs(KEYWORDS) do
        if n:find(kw, 1, true) then return true end
    end
    return false
end

-- ============================================================
-- SCAN — kumpulin script/module penting
-- ============================================================
local found = {}   -- { name, path, class, source, size }

local function tryGetSource(inst)
    local ok, src = pcall(function()
        local s = inst.Source
        if type(s) == "string" and #s > 0 then return s end
        return nil
    end)
    if not ok or not src then
        -- coba decompile (executor)
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
    return src
end

local function scanTree(root)
    pcall(function()
        for _, inst in ipairs(root:GetDescendants()) do
            if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
                if matchesKeywords(inst.Name) then
                    local src = tryGetSource(inst)
                    local size = src and #src or 0
                    -- skip yang kekecilan (gak penting) & kegedean (bikin lag)
                    if size >= 100 and size <= 200000 then
                        table.insert(found, {
                            name = inst.Name,
                            path = inst:GetFullName(),
                            class = inst.ClassName,
                            source = src,
                            size = size,
                        })
                    end
                end
            end
        end
    end)
end

local function scanAll()
    found = {}
    -- Prioritas: ReplicatedStorage dulu (sumber logic client)
    local RS = game:GetService("ReplicatedStorage")
    scanTree(RS)
    -- Terus service lain yang relevan
    for _, svcName in ipairs({
        "ReplicatedFirst", "Workspace", "Players", "StarterGui",
        "StarterPack", "Lighting", "SoundService",
    }) do
        pcall(function()
            local svc = game:GetService(svcName)
            scanTree(svc)
        end)
    end
    -- Sort: yang paling kecil dulu (biasanya config/recipe yang penting)
    table.sort(found, function(a, b) return a.size < b.size end)
end

-- ============================================================
-- UI — touch friendly
-- ============================================================
local UI = {}
local screen, frame, listFrame, viewFrame, viewBox

local function clearList()
    if listFrame then
        for _, c in ipairs(listFrame:GetChildren()) do c:Destroy() end
    end
end

local function showView(entry)
    -- Sembunyiin list, tampilin source
    listFrame.Visible = false
    viewFrame.Visible = true
    viewBox.Text = ""
    task.defer(function()
        viewBox.Text = entry.source or "(gak bisa baca source)"
    end)
    UI.viewTitle.Text = entry.name .. "  (" .. math.floor(entry.size / 1024 * 10) / 10 .. " KB)"
    UI.viewPath.Text = entry.path
end

local function showList()
    viewFrame.Visible = false
    listFrame.Visible = true
end

local function buildUI()
    local existing = LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("LogicUI")
    if existing then existing:Destroy() end
    local PlayerGui = LP:WaitForChild("PlayerGui", 10)
    if not PlayerGui then return end

    screen = Instance.new("ScreenGui")
    screen.Name           = "LogicUI"
    screen.ResetOnSpawn   = false
    screen.DisplayOrder   = 996
    screen.IgnoreGuiInset = true
    screen.Parent         = PlayerGui

    frame = Instance.new("Frame")
    frame.Name            = "Main"
    frame.Size            = UDim2.new(0.96, 0, 0.8, 0)
    frame.Position        = UDim2.new(0.02, 0, 0.1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    frame.BorderSizePixel = 0
    frame.Parent          = screen

    -- Title
    local title = Instance.new("TextLabel")
    title.Size            = UDim2.new(1, -50, 0, 28)
    title.Position        = UDim2.new(0, 6, 0, 4)
    title.BackgroundTransparency = 1
    title.Text            = "LOGIC EXTRACTOR"
    title.TextColor3      = Color3.fromRGB(255, 200, 120)
    title.TextSize        = 15
    title.Font            = Enum.Font.GothamBold
    title.TextXAlignment  = Enum.TextXAlignment.Left
    title.Parent          = frame

    -- Close
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size         = UDim2.new(0, 40, 0, 28)
    closeBtn.Position     = UDim2.new(1, -44, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text         = "X"
    closeBtn.TextColor3   = Color3.fromRGB(255,255,255)
    closeBtn.TextSize     = 14
    closeBtn.Font         = Enum.Font.GothamBold
    closeBtn.Parent       = frame
    closeBtn.MouseButton1Click:Connect(function()
        screen:Destroy()
    end)

    -- Info
    local info = Instance.new("TextLabel")
    info.Name             = "Info"
    info.Size             = UDim2.new(1, -12, 0, 20)
    info.Position         = UDim2.new(0, 6, 0, 34)
    info.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    info.BorderSizePixel  = 0
    info.Text             = "Scan..."
    info.TextColor3       = Color3.fromRGB(160, 220, 160)
    info.TextSize         = 12
    info.Font             = Enum.Font.Gotham
    info.TextXAlignment   = Enum.TextXAlignment.Left
    info.Parent           = frame
    UI.info = info

    -- LIST VIEW
    listFrame = Instance.new("ScrollingFrame")
    listFrame.Name            = "List"
    listFrame.Size            = UDim2.new(1, -12, 1, -70)
    listFrame.Position        = UDim2.new(0, 6, 0, 58)
    listFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    listFrame.BorderSizePixel = 0
    listFrame.CanvasSize      = UDim2.new(0, 0, 0, 0)
    listFrame.ScrollBarThickness = 6
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listFrame.Parent          = frame

    -- VIEW VIEW (source)
    viewFrame = Instance.new("Frame")
    viewFrame.Name            = "View"
    viewFrame.Size            = UDim2.new(1, -12, 1, -70)
    viewFrame.Position        = UDim2.new(0, 6, 0, 58)
    viewFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    viewFrame.BorderSizePixel = 0
    viewFrame.Visible         = false
    viewFrame.Parent          = frame

    local vTitle = Instance.new("TextLabel")
    vTitle.Name               = "ViewTitle"
    vTitle.Size               = UDim2.new(1, -8, 0, 22)
    vTitle.Position           = UDim2.new(0, 4, 0, 2)
    vTitle.BackgroundTransparency = 1
    vTitle.Text               = ""
    vTitle.TextColor3         = Color3.fromRGB(255, 220, 150)
    vTitle.TextSize           = 13
    vTitle.Font               = Enum.Font.GothamBold
    vTitle.TextXAlignment     = Enum.TextXAlignment.Left
    vTitle.Parent             = viewFrame
    UI.viewTitle = vTitle

    local vPath = Instance.new("TextLabel")
    vPath.Name                = "ViewPath"
    vPath.Size                = UDim2.new(1, -8, 0, 16)
    vPath.Position            = UDim2.new(0, 4, 0, 24)
    vPath.BackgroundTransparency = 1
    vPath.Text                = ""
    vPath.TextColor3         = Color3.fromRGB(150, 150, 170)
    vPath.TextSize           = 10
    vPath.Font               = Enum.Font.Gotham
    vPath.TextXAlignment     = Enum.TextXAlignment.Left
    vPath.Parent             = viewFrame
    UI.viewPath = vPath

    local vScroll = Instance.new("ScrollingFrame")
    vScroll.Name              = "SrcScroll"
    vScroll.Size              = UDim2.new(1, -8, 1, -80)
    vScroll.Position          = UDim2.new(0, 4, 0, 42)
    vScroll.BackgroundColor3  = Color3.fromRGB(12, 12, 16)
    vScroll.BorderSizePixel   = 0
    vScroll.ScrollBarThickness = 8
    vScroll.Parent            = viewFrame

    viewBox = Instance.new("TextLabel")
    viewBox.Name              = "Src"
    viewBox.Size              = UDim2.new(1, -10, 0, 0)
    viewBox.Position          = UDim2.new(0, 5, 0, 0)
    viewBox.BackgroundTransparency = 1
    viewBox.Text              = ""
    viewBox.TextColor3        = Color3.fromRGB(200, 230, 200)
    viewBox.TextSize          = 10
    viewBox.Font              = Enum.Font.Code
    viewBox.TextXAlignment    = Enum.TextXAlignment.Left
    viewBox.TextYAlignment    = Enum.TextYAlignment.Top
    viewBox.AutomaticSize     = Enum.AutomaticSize.Y
    viewBox.TextWrapped       = false
    viewBox.Parent            = vScroll

    -- Button bar bawah (view)
    local bY = 0.5
    local function makeBtn(parent, label, y, fn, color)
        local b = Instance.new("TextButton")
        b.Size                = UDim2.new(0, 100, 0, 32)
        b.Position            = UDim2.new(0, y, 0, 0)
        b.BackgroundColor3    = color or Color3.fromRGB(50, 80, 130)
        b.BorderSizePixel     = 0
        b.Text                = label
        b.TextColor3          = Color3.fromRGB(230, 230, 255)
        b.TextSize            = 13
        b.Font                = Enum.Font.GothamBold
        b.Parent              = parent
        b.MouseButton1Click:Connect(fn)
        return b
    end

    local vBtns = Instance.new("Frame")
    vBtns.Name            = "ViewBtns"
    vBtns.Size            = UDim2.new(1, -12, 0, 36)
    vBtns.Position        = UDim2.new(0, 6, 1, -40)
    vBtns.BackgroundTransparency = 1
    vBtns.Parent          = viewFrame

    local currentEntry = nil
    makeBtn(vBtns, "< Kembali", 0, function()
        currentEntry = nil
        showList()
    end, Color3.fromRGB(80, 60, 60))
    makeBtn(vBtns, "Copy", 110, function()
        if currentEntry and currentEntry.source then
            local ok = pcall(function() setclipboard(currentEntry.source) end)
            UI.info.Text = ok and ("Copied: " .. currentEntry.name) or "setclipboard gak ada"
        end
    end, Color3.fromRGB(40, 130, 70))
    makeBtn(vBtns, "Save", 220, function()
        if currentEntry and currentEntry.source then
            local fname = "dm_logic_" .. currentEntry.name:gsub("[^%w_]", "_") .. ".lua"
            local ok = pcall(function() writefile(fname, currentEntry.source) end)
            UI.info.Text = ok and ("Saved: " .. fname) or "writefile gak ada"
        end
    end, Color3.fromRGB(130, 110, 40))

    -- Bottom bar list
    local lBtns = Instance.new("Frame")
    lBtns.Name            = "ListBtns"
    lBtns.Size            = UDim2.new(1, -12, 0, 36)
    lBtns.Position        = UDim2.new(0, 6, 1, -40)
    lBtns.BackgroundTransparency = 1
    lBtns.Parent          = listFrame.Parent

    makeBtn(lBtns, "Scan Ulang", 0, function()
        scanAll()
        renderList()
    end, Color3.fromRGB(40, 80, 140))
    makeBtn(lBtns, "Save Semua", 110, function()
        local saved = 0
        for _, e in ipairs(found) do
            if e.source then
                local fname = "dm_logic_" .. e.name:gsub("[^%w_]", "_") .. ".lua"
                pcall(function()
                    writefile(fname, e.source)
                    saved = saved + 1
                end)
            end
        end
        UI.info.Text = ("Saved %d file ke folder Delta"):format(saved)
    end, Color3.fromRGB(130, 110, 40))
    makeBtn(lBtns, "Copy Semua", 220, function()
        local out = {}
        for _, e in ipairs(found) do
            if e.source then
                out[#out+1] = ("--===== %s (%s) =====--\n%s"):format(e.path, e.name, e.source)
            end
        end
        local ok = pcall(function() setclipboard(table.concat(out, "\n\n")) end)
        UI.info.Text = ok and ("Copied %d modul"):format(#found) or "setclipboard gak ada"
    end, Color3.fromRGB(40, 130, 70))

    -- Isi list
    renderList()

    -- Auto-refresh info
    task.spawn(function()
        while screen and screen.Parent do
            task.wait(3)
            pcall(function()
                if UI.info then
                    UI.info.Text = ("%d modul ketemu. Tap buat baca. Path: %s"):format(#found, LP:GetFullName())
                end
            end)
        end
    end)

    print("[LogicExtractor] UI aktif. " .. #found .. " modul.")
end

local function renderList()
    clearList()
    if #found == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size            = UDim2.new(1, 0, 0, 60)
        empty.BackgroundTransparency = 1
        empty.Text            = "Gak ada modul yang cocok keyword.\nCoba jalanin lagi abis game selesai load."
        empty.TextColor3      = Color3.fromRGB(200, 120, 120)
        empty.TextSize        = 13
        empty.Font            = Enum.Font.Gotham
        empty.Parent          = listFrame
        return
    end
    local y = 0
    for _, e in ipairs(found) do
        local row = Instance.new("TextButton")
        row.Size              = UDim2.new(1, -10, 0, 44)
        row.Position          = UDim2.new(0, 5, 0, y)
        row.BackgroundColor3  = Color3.fromRGB(35, 35, 45)
        row.BorderSizePixel   = 0
        row.Text              = ""
        row.Parent            = listFrame

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size            = UDim2.new(1, -8, 0, 20)
        nameLabel.Position        = UDim2.new(0, 4, 0, 2)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text            = e.name .. "  [" .. e.class .. "]"
        nameLabel.TextColor3      = Color3.fromRGB(255, 220, 150)
        nameLabel.TextSize        = 13
        nameLabel.Font            = Enum.Font.GothamBold
        nameLabel.TextXAlignment  = Enum.TextXAlignment.Left
        nameLabel.TextTruncate    = Enum.TextTruncate.AtEnd
        nameLabel.Parent          = row

        local pathLabel = Instance.new("TextLabel")
        pathLabel.Size            = UDim2.new(1, -8, 0, 16)
        pathLabel.Position        = UDim2.new(0, 4, 0, 22)
        pathLabel.BackgroundTransparency = 1
        pathLabel.Text            = e.path .. "  (" .. math.floor(e.size / 1024 * 10) / 10 .. " KB)"
        pathLabel.TextColor3      = Color3.fromRGB(150, 150, 180)
        pathLabel.TextSize        = 10
        pathLabel.Font            = Enum.Font.Gotham
        pathLabel.TextXAlignment  = Enum.TextXAlignment.Left
        pathLabel.TextTruncate    = Enum.TextTruncate.AtEnd
        pathLabel.Parent          = row

        row.MouseButton1Click:Connect(function()
            currentEntry = e
            showView(e)
        end)

        y = y + 48
    end
    listFrame.CanvasSize = UDim2.new(0, 0, 0, y + 4)
end

-- ============================================================
-- INIT
-- ============================================================
print("==========================================")
print("  DM LOGIC EXTRACTOR — Devil's Market")
print("==========================================")

-- Scan duluan biar UI langsung isi
task.spawn(function()
    scanAll()
    print("[LogicExtractor] Scan selesai: " .. #found .. " modul")
    task.spawn(buildUI)
end)

-- Rescan tombol F9
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F9 then
        scanAll()
        renderList()
        print("[LogicExtractor] Rescan: " .. #found .. " modul")
    end
end)
