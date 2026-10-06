-- fceux_nocart.lua -- regression without a FujiNet: the game boots, the design
-- menu's SAVE shows "NO FUJINET" and comes back to the menu instead of writing
-- to a cassette for 20 s (LOAD used to hang forever).
--   fceux --loadlua tests/fceux_nocart.lua build/excitebike-fujinet.nes
local function glyph(v)
  if v <= 9 then return string.char(0x30 + v) end
  if v >= 0x0A and v <= 0x23 then return string.char(0x41 + v - 0x0A) end
  if v == 0xFC then return " " end
  return "."
end
local function row(r)
  local t = {}
  for c = 0, 31 do t[#t + 1] = glyph(ppu.readbyte(0x2000 + r * 32 + c)) end
  return table.concat(t)
end
local function find(text)
  for r = 0, 29 do if row(r):find(text, 1, true) then return r end end
  return nil
end

local queue, hold = {}, 0
local function press(name, n) for _ = 1, (n or 1) do queue[#queue + 1] = name end end
local function pump()
  if hold > 0 then
    hold = hold - 1
    if hold >= 6 then joypad.set(1, { [queue[1]] = true }) end
    if hold == 0 then table.remove(queue, 1) end
    return true
  end
  if #queue > 0 then hold = 12; return true end
  return false
end

local step, frame, shown = 1, 0, nil
local function finish(ok, msg)
  print((ok and "PASS: " or "FAIL: ") .. msg)
  emu.exit()
end

while true do
  frame = frame + 1
  if frame > 2400 then finish(false, "timeout at step " .. step) end
  if not pump() then
    if step == 1 and find("SELECTION A") then
      press("select", 2); press("start"); step = 2
    elseif step == 2 and memory.readbyte(0x41) == 8 and find("SAVE") then
      if memory.readbyte(0x42) ~= 3 then press("select") else press("start"); step = 3 end
    elseif step == 3 and find("NO FUJINET") then
      shown = frame; step = 4
    elseif step == 4 and memory.readbyte(0x41) == 8 and not find("NO FUJINET") then
      -- and LOAD must not hang either
      if memory.readbyte(0x42) ~= 4 then press("select") else press("start"); step = 5 end
    elseif step == 5 and find("NO FUJINET") then
      step = 6
    elseif step == 6 and memory.readbyte(0x41) == 8 and not find("NO FUJINET") then
      finish(true, string.format("SAVE and LOAD report NO FUJINET and return to the menu (frame %d)", frame))
    end
  end
  emu.frameadvance()
end
