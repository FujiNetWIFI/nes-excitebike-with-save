-- nocart.lua -- MAME, plain NES slot (no FujiNet): SAVE and LOAD must show
-- "NO FUJINET" and return to the design menu; LOAD must leave the track alone.
--   tests/run-mame.sh nocart   (run-mame.sh drops -nes_slot fujinet for this one)
local T = dofile(os.getenv("EB_TEST_DIR") .. "/ebtext.lua")
local timeout = tonumber(os.getenv("EB_TIMEOUT") or "90")
local STATE, CURSOR, MASTER = 0x41, 0x42, 0x06E0
local step, done = 1, false
local before
local function fail(msg) done = true; print(T.screen()); T.verdict(false, msg) end

T.every_frame(function()
  if done then return end
  if T.now() > timeout then return fail("timeout at step " .. step) end
  if T.pump() then return end
  if step == 1 then
    if T.find("SELECTION A") and T.find("DESIGN") then T.press("Select", 2); T.press("Start"); step = 2 end
  elseif step == 2 then
    if T.rd(STATE) == 8 and T.find("SAVE") then before = T.hex(MASTER, 256); step = 3 end
  elseif step == 3 then
    if T.rd(CURSOR) ~= 3 then T.press("Select") else T.press("Start"); step = 4 end
  elseif step == 4 then
    if T.find("NO FUJINET") then print(string.format("%.2fs SAVE: NO FUJINET", T.now())); step = 5
    elseif T.find("SAVE SLOT") then fail("prompt appeared without a cartridge") end
  elseif step == 5 then
    if T.rd(STATE) == 8 and not T.find("NO FUJINET") then step = 6 end
  elseif step == 6 then
    if T.rd(CURSOR) ~= 4 then T.press("Select") else T.press("Start"); step = 7 end
  elseif step == 7 then
    if T.find("NO FUJINET") then print(string.format("%.2fs LOAD: NO FUJINET", T.now())); step = 8 end
  elseif step == 8 then
    if T.rd(STATE) == 8 and not T.find("NO FUJINET") then
      if T.hex(MASTER, 256) ~= before then return fail("LOAD without a cart changed the track") end
      done = true
      T.verdict(true, string.format("no-cart SAVE/LOAD both return to the menu by %.1fs", T.now()))
    end
  end
end)
