# Devil's Market Auto Hub

Auto hub untuk game **Devil's Market (Pasar Setan)** — Roblox.

Script bersih: **tanpa key system, tanpa webhook, tanpa obfuscation**. Kode 100% bisa diaudit.

## Isi Repo

| File | Fungsi |
|---|---|
| `devil_market_hub.lua` | **Auto Hub murni** (v7) — auto-farm/cook/serve/buy via ProximityPrompt, speed, anti-AFK, ESP, teleport, scanner. Jalan mandiri, tanpa remote hook. |
| `remote_spy.lua` | **Remote Spy** (standalone) — scan semua RemoteEvent/RemoteFunction, kategorisasi farm/cook/serve/buy, hook `__namecall` buat intercept FireServer/InvokeServer live, dump + save ke file. |

## Fitur

### devil_market_hub.lua (Auto Hub v7)

| Fitur | Keterangan |
|---|---|
| Auto-Farm | Tanam & panen otomatis via ProximityPrompt |
| Auto-Cook | Masak otomatis |
| Auto-Serve | Layani pelanggan otomatis |
| Auto-Buy | Beli/upgrade otomatis |
| Speed Boost | WalkSpeed 32 (default 16) |
| Anti-AFK | Anti kick idle |
| ESP | Highlight pemain & objek interaktif |
| Teleport | Lompat ke lokasi terdekat (keyword-based) |
| Scan (F9) | Dump prompt + tool ke konsol |
| UI | Custom Instance.new (PlayerGui), tanpa library eksternal |

**Keybind:** F1 Farm · F2 Cook · F3 Serve · F4 Buy · F5 Speed · F6 Anti-AFK · F7 ESP · F8 Teleport · F9 Scan · F10 Matikan Semua

### remote_spy.lua (Remote Spy)

| Fitur | Keterangan |
|---|---|
| Scan statis | Semua remote di game, dikategorikan otomatis |
| Hook namecall | Intercept FireServer/InvokeServer live + log args (butuh executor yang support `hookmetamethod`) |
| Dump (F9) | Remote map ke konsol |
| Save (F11) | Remote map + log ke file `DevilMarket_Remotes.txt` |
| Rescan (F12) | Reset + scan ulang |

## Cara Pakai

1. Buka game **Devil's Market** (Pasar Setan)
2. **Auto hub doang:** jalankan `devil_market_hub.lua`
3. **Mau mapping remote:** jalankan `remote_spy.lua` (bisa barengan, keybind gak bentrok)
4. Kalau auto-farm/cook/serve kurang akurat: klik **Scan (F9)** di hub → hasil dump nama objek muncul di konsol → sesuaikan keyword di bagian `Config` di atas script → load ulang

## Teknis

- UI hub: **Instance.new murni** (PlayerGui) — tanpa library eksternal (FluentUI/Rayfield fork gak jalan di semua executor)
- Interaksi: `fireproximityprompt` kalau executor mendukung; fallback simulasi gerak + tekan E
- Remote spy: `hookmetamethod` + `getnamecallmethod` (API executor), fallback scan statis
- Config terpusat di bagian atas tiap file (keyword, radius, delay, warna ESP)
- Anti-crash: semua operasi dibungkus pcall

## Disclaimer

Script ini melanggar ToS Roblox. Gunakan dengan risiko sendiri — risiko ban akun. Jangan pakai di akun utama kalau tidak mau kehilangan progress.
