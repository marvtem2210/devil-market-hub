# Devil's Market Auto Hub

Auto hub untuk game **Devil's Market (Pasar Setan)** — Roblox.

Script bersih: **tanpa key system, tanpa webhook, tanpa obfuscation**. Kode 100% bisa diaudit.

## Fitur

| Tab | Fitur |
|---|---|
| Farming | Auto-Farm (tanam & panen otomatis) |
| Cooking | Auto-Cook (masak otomatis) |
| Serving | Auto-Serve (layani pelanggan otomatis) |
| Shopping | Auto-Buy / Upgrade |
| Movement | Speed Boost (WalkSpeed & JumpPower), Anti-AFK, Infinite Jump |
| Teleport | Dropdown lokasi + input nama part custom |
| Visual | ESP (highlight pemain & objek), SCAN dump nama objek |
| Settings | Theme manager (6 tema) + Save/Load config |

## Cara Pakai

1. Buka game **Devil's Market** (Pasar Setan)
2. Jalankan script di executor Anda (load file `devil_market_hub.lua`)
3. Aktifkan fitur via toggle per tab
4. Kalau auto-farm/cook/serve kurang akurat: klik **SCAN** di tab Visual → hasil dump nama objek muncul di konsol (F9) → sesuaikan keyword di bagian `Config` di atas script → load ulang

## Teknis

- UI: [FluentUI](https://github.com/dawid-scripts/Fluent) (dawid-scripts)
- Interaksi: `fireproximityprompt` kalau executor mendukung; fallback simulasi gerak + tekan E
- Config terpusat di bagian atas (keyword, radius, delay, warna ESP)
- SaveManager: config tersimpan otomatis (folder `DevilMarketHub`)
- Anti-crash: semua load library & fungsi executor dibungkus pcall

## Disclaimer

Script ini melanggar ToS Roblox. Gunakan dengan risiko sendiri — risiko ban akun. Jangan pakai di akun utama kalau tidak mau kehilangan progress.
