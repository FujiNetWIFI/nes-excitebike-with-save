-- ebtext.lua -- read Excitebike's screen as text from inside MAME.
--
-- The game's font: tiles $00-$09 are the digits, $0A-$23 the letters A-Z,
-- $FC a space. Everything else (track graphics, borders) reads as ".".
-- readv_u8 has no side effects: a plain read through the CPU space would fire
-- the FujiNet mailbox hotspots.
local M = {}

function M.ppu_space() return manager.machine.devices[":ppu"].spaces["videoram"] end
function M.cpu_space() return manager.machine.devices[":maincpu"].spaces["program"] end

local function glyph(v)
  if v <= 9 then return string.char(0x30 + v) end
  if v >= 0x0A and v <= 0x23 then return string.char(0x41 + v - 0x0A) end
  if v == 0xFC then return " " end
  if v == 0xF9 then return "'" end
  if v == 0xFA then return "!" end
  if v == 0xFB then return ":" end
  if v == 0xF1 then return "/" end
  if v == 0x26 then return "*" end
  return "."
end

-- nametable 0, row r (0-29), trailing spaces trimmed
function M.row(r)
  local s, t = M.ppu_space(), {}
  for c = 0, 31 do t[#t + 1] = glyph(s:readv_u8(0x2000 + r * 32 + c)) end
  return (table.concat(t):gsub("%s+$", ""))
end

function M.screen()
  local t = {}
  for r = 0, 29 do t[#t + 1] = string.format("%2d %s", r, M.row(r)) end
  return table.concat(t, "\n")
end

function M.find(text)
  for r = 0, 29 do
    if M.row(r):find(text, 1, true) then return r end
  end
  return nil
end

function M.rd(a) return M.cpu_space():readv_u8(a) end
function M.wr(a, v) M.cpu_space():write_u8(a, v) end

-- n bytes from a as lowercase hex
function M.hex(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02x", M.rd(a + i)) end
  return table.concat(t)
end

function M.now() return manager.machine.time:as_double() end

-- The notifier token must stay referenced or the subscription dies at GC.
function M.every_frame(fn) _G.__ebtext_sub = emu.add_machine_frame_notifier(fn) end

function M.verdict(ok, msg)
  emu.print_info((ok and "PASS: " or "FAIL: ") .. msg)
  print((ok and "PASS: " or "FAIL: ") .. msg)
  manager.machine:exit()
end

-- Joypad 1 press queue: each press is held 6 frames and released 6, one
-- event for the game's edge detection (and for the patch's own prompt).
local pad = manager.machine.ioport.ports[":ctrl1:joypad:JOYPAD"]
local function btn(name) return pad.fields["P1 " .. name] end
local presses, hold = {}, 0
function M.press(name, n) for _ = 1, (n or 1) do presses[#presses + 1] = name end end
function M.pump()
  if hold > 0 then
    hold = hold - 1
    if hold == 6 then btn(presses[1]):set_value(0); table.remove(presses, 1) end
    return true
  end
  if #presses > 0 then btn(presses[1]):set_value(1); hold = 12; return true end
  return false
end


-- CPU stack pointer (low byte) and the attribute bytes our screens use.
function M.sp() return manager.machine.devices[":maincpu"].state["SP"].value & 0xFF end
function M.attrs()
  local s, t = M.ppu_space(), {}
  for i = 0, 47 do t[#t + 1] = string.format("%02x", s:readv_u8(0x23C8 + i)) end
  return table.concat(t)
end

function M.shot()                                  -- build/snap/nes/NNNN.png
  local scr = manager.machine.screens[":screen"]
  if scr then scr:snapshot() end
end

function M.sh(cmd)
  local p = io.popen(cmd)
  local out = p:read("a")
  p:close()
  return out
end

function M.readfile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("a")
  f:close()
  return d
end

-- Type str into the patch's name editor from the current (blank) cell:
-- Up cycles space, A-Z, 0-9, so a letter is 1-26 presses and a digit 27-36;
-- Right moves to the next cell.
function M.type(str)
  for i = 1, #str do
    local c = str:sub(i, i)
    local n = 0
    if c:match("%a") then n = c:upper():byte() - 64
    elseif c:match("%d") then n = 27 + c:byte() - 48 end
    if n > 0 then M.press("Up", n) end
    if i < #str then M.press("Right") end
  end
end

return M
