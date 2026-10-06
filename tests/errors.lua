-- errors.lua -- the unhappy paths, run with the track server STOPPED and
-- fujinet-pc up: the picker shows NO INFO and B backs out; LOAD reports
-- NET ERROR with the track intact; B in the editor returns to the picker; the
-- owner check reports NET ERROR and returns to the menu.   tests/run-mame.sh errors
local T = dofile(os.getenv("EB_TEST_DIR") .. "/ebtext.lua")
local timeout = tonumber(os.getenv("EB_TIMEOUT") or "150")
local STATE, CURSOR, MASTER = 0x41, 0x42, 0x06E0
local step, done = 1, false
local before, settle
local function fail(msg) done = true; print(T.screen()); T.verdict(false, msg) end
local function log(msg) print(string.format("%6.2fs %s", T.now(), msg)) end
local function in_menu() return T.rd(STATE) == 8 and T.find("SAVE") and T.find("LOAD") end
local function cursor_to(n, nextstep)
  if T.rd(CURSOR) ~= n then T.press("Select") else T.press("Start"); step = nextstep end
end
-- fields are drawn one vblank after the labels: wait for the cursor star
local function editor()
  return T.row(4):find("SAVE SLOT", 1, true) and T.find("NAME") and T.find("USER") and T.row(9):sub(13, 13) == "*"
end

T.every_frame(function()
  if done then return end
  if T.now() > timeout then return fail("timeout at step " .. step) end
  if T.pump() then return end
  if step == 1 then
    if T.find("SELECTION A") and T.find("DESIGN") then T.press("Select", 2); T.press("Start"); step = 2 end
  elseif step == 2 then
    if in_menu() then before = T.hex(MASTER, 256); step = 3 end
  elseif step == 3 then cursor_to(3, 4)
  elseif step == 4 then                                   -- picker: no server -> NO INFO
    if T.find("SAVE SLOT") then settle = T.now() + 1.5; step = 41 end
  elseif step == 41 then
    if T.row(20):find("NO INFO", 1, true) then log("picker: " .. T.row(20)); T.press("B"); step = 5
    elseif T.now() > settle then fail("picker info with no server: " .. T.row(20)) end
  elseif step == 5 then
    if in_menu() and not T.find("SLOT") then log("picker cancelled with B"); step = 6 end
  elseif step == 6 then cursor_to(4, 7)
  elseif step == 7 then
    if T.find("NET ERROR") then log("load list: " .. T.row(16)); step = 8
    elseif T.find("LOAD TRACK") and T.find("05") then fail("a list appeared with no server") end
  elseif step == 8 then
    if in_menu() and not T.find("ERROR") then
      if T.hex(MASTER, 256) ~= before then return fail("failed load changed the track") end
      step = 9
    end
  elseif step == 9 then cursor_to(3, 10)
  elseif step == 10 then
    if T.find("SAVE SLOT") then T.press("A"); step = 11 end          -- straight to the editor
  elseif step == 11 then
    if editor() then
      if not T.row(12):match("USER%s+(%w+)") then T.press("Right", 8); T.type("NES") end
      T.press("B"); step = 12                                          -- B: back to the picker
    end
  elseif step == 12 then
    if T.find("SAVE SLOT") and not T.find("NAME") then log("editor B returned to the picker"); T.press("A"); step = 13 end
  elseif step == 13 then
    if editor() then T.press("A"); step = 14 end
  elseif step == 14 then
    if T.find("NET ERROR") then log("owner check with no server: " .. T.row(16)); step = 15
    elseif T.find("ENTER A NAME") then T.type("X"); T.press("A")
    elseif T.find("USER 2 TO 8") then fail("username rejected: " .. T.row(12))
    elseif T.find("SAVED") then fail("save succeeded with no server") end
  elseif step == 15 then
    if in_menu() and not T.find("ERROR") then
      done = true
      T.verdict(true, string.format("cancel paths and NET ERROR all return to the menu by %.1fs", T.now()))
    end
  end
end)
