--[[
  ============================================================
  DELTA ENVIRONMENT CHECK
  Jalankan pertama kali di Delta sebelum pake script apa pun.
  Hasil: konsol + file DeltaEnvCheck.txt + notifikasi in-game.
  ============================================================
]]

local lines = {}
local function add(fmt, ...) lines[#lines+1] = fmt:format(...) end

add("===== DELTA ENV CHECK =====")
add("executor: %s", getexecutorname and getexecutorname() or "?")

-- Daftar API executor yang umum di Delta
local checks = {
    { "loadstring",          loadstring          },
    { "hookmetamethod",      hookmetamethod      },
    { "hookfunction",        hookfunction        },
    { "newcclosure",         newcclosure         },
    { "getnamecallmethod",   getnamecallmethod   },
    { "getgc",               getgc               },
    { "getreg",              getreg              },
    { "getrawmetatable",     getrawmetatable     },
    { "getgenv",             getgenv             },
    { "fireproximityprompt", fireproximityprompt },
    { "writefile",           writefile           },
    { "readfile",            readfile            },
    { "listfiles",           listfiles           },
    { "setclipboard",        setclipboard        },
    { "request",             request or http_request },
    { "getcustomasset",      getcustomasset      },
    { "getconnections",      getconnections      },
    { "getinfo",             getinfo             },
    { "getsenv",             getsenv             },
    { "getscriptbytecode",   getscriptbytecode   },
}

for _, c in ipairs(checks) do
    add("%s  %s", c[2] and "YES" or "NO ", c[1])
end

add("============================")

local out = table.concat(lines, "\n")
print(out)

-- Save ke file (folder Delta)
pcall(function() writefile("DeltaEnvCheck.txt", out) end)

-- Notif in-game biar keliatan di HP (konsol mobile susah dibuka)
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Env Check",
        Text  = out,
        Duration = 15,
    })
end)

-- Kalau mau liat hasilnya lagi nanti:
--   print(readfile("DeltaEnvCheck.txt"))
