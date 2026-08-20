--[[
  ============================================================
  HOOK TEMPLATE — Delta Executor (Android)
  Pola dasar hook yang aman & anti-crash.
  ============================================================

  Yang dipelajari dari file ini:
    1. Cek environment DULU (fungsi executor ada gak)
    2. Simpan old function SEBELUM hook (nyawa hook)
    3. pcall di dalem hook → error isi hook gak nge-crash game
    4. SELALU return old(...) — kecuali sengaja block
    5. newcclosure → hook lebih susah ke-detect anti-cheat

  Toggle:
    LOG   = true  → log semua FireServer/InvokeServer
    BLOCK = false → true = cegah remote tertentu jalan.
                    HATI-HATI: block remote bisa bikin fitur
                    game error / anti-cheat curiga.
  ============================================================
]]

-- 1) ENVIRONMENT CHECK
print("===== DELTA ENV CHECK =====")
print("executor:", getexecutorname and getexecutorname() or "?")
print("hookmetamethod:", hookmetamethod and "YES" or "NO")
print("newcclosure:", newcclosure and "YES" or "NO")
print("getnamecallmethod:", getnamecallmethod and "YES" or "NO")
print("============================")

-- Kalau hook gak ada, stop — gak usah lanjut
if not hookmetamethod or not getnamecallmethod then
    print("[HookTemplate] executor ini gak support hookmetamethod — STOP")
    return
end

-- 2) SETUP
local LOG   = true   -- log remote yang di-fire
local BLOCK = false  -- cegah remote (bahaya, default false)

-- Remote yang mau di-block kalau BLOCK = true
local BLOCKED_NAMES = {
    -- ["NamaRemote"] = true,
}

-- 3) SIMPAN OLD — WAJIB. Kalau gak, gak ada jalan balik.
local oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local blocked = false

    -- pcall: kalau isi hook error, game gak ikut crash
    pcall(function()
        local method = getnamecallmethod()

        -- Cuma peduli FireServer/InvokeServer
        if (method == "FireServer" or method == "InvokeServer")
        and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then

            if LOG then
                print(string.format("[HOOK] %s : %s", self:GetFullName(), method))
            end

            if BLOCK and BLOCKED_NAMES[self.Name] then
                print("[HOOK] BLOCKED: " .. self.Name)
                blocked = true
            end
        end
    end)

    -- 4) SELALU return old — kecuali di atas udah mutusin buat block
    if blocked then return end
    return oldNamecall(self, ...)
end))

print("[HookTemplate] hook aktif. LOG=" .. tostring(LOG) .. " BLOCK=" .. tostring(BLOCK))
