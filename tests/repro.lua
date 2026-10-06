-- repro.lua -- the user's session against the REAL database: LOAD 05 from
-- the list, DESIGN (place a piece and the finish line, leave with B), SAVE:
-- the picker opens on 05 and shows who holds it, the editor is titled with
-- the slot, a typed name and a touched USER field, A -> the confirmation
-- asks, B, B -> menu. Never confirms a save, so nothing is written (the app
-- key is rewritten with the same value). FUJINET_DEBUG=1 logs every
-- mailbox transaction.   make repro
local T = dofile(os.getenv("EB_TEST_DIR") .. "/ebtext.lua")
local timeout = tonumber(os.getenv("EB_TIMEOUT") or "120")
local STATE, CURSOR = 0x41, 0x42
local step, done = 1, false
local t0, tries, last_state, last_rows, settle = 0, 0, -1, "", 0
local function fail(msg) done = true; print(T.screen()); T.verdict(false, msg) end
local function log(msg) print(string.format("%6.2fs %s", T.now(), msg)) end
local function in_menu() return T.rd(STATE) == 8 and T.find("SAVE") and T.find("LOAD") end
local function cursor_to(n, nextstep)
  if T.rd(CURSOR) ~= n then T.press("Select") else T.press("Start"); step = nextstep end
end
local function editor()
  return T.row(4):find("SAVE SLOT", 1, true) and T.find("NAME") and T.find("USER") and T.row(9):sub(13, 13) == "*"
end

T.every_frame(function()
  if done then return end
  if T.now() > timeout then return fail("timeout at step " .. step) end
  local st = T.rd(STATE)
  if st ~= last_state then log("state " .. st); last_state = st end
  if T.pump() then return end
  if step == 1 then
    if T.find("SELECTION A") and T.find("DESIGN") then T.press("Select", 2); T.press("Start"); step = 2 end
  elseif step == 2 then
    if in_menu() then step = 3 end
  elseif step == 3 then cursor_to(4, 4)                        -- LOAD
  elseif step == 4 then
    if T.find("LOAD TRACK") and T.find("05") then t0 = T.now() + 0.3; step = 5
    elseif T.find("NO TRACKS") or T.find("NET ERROR") then fail("no slot 05 on the server: " .. T.row(16)) end
  elseif step == 5 then
    if T.now() > t0 then                                       -- the star is on the first line (05)
      if T.row(6):sub(5, 5) ~= "*" or not T.row(6):find("05", 1, true) then return fail("slot 05 is not the first line: " .. T.row(6)) end
      T.press("A"); step = 6
    end
  elseif step == 6 then
    if T.find("LOADED SLOT 05") then log("loaded 05"); step = 7 end
  elseif step == 7 then
    if in_menu() and not T.find("LOADED") then
      if os.getenv("EB_SKIP_DESIGN") then log("skipping DESIGN"); step = 13 else step = 8 end
    end
  elseif step == 8 then cursor_to(2, 9)                        -- DESIGN
  elseif step == 9 then
    if T.rd(STATE) == 9 then log("in the design editor"); t0 = T.now() + 1.0; step = 10 end
  elseif step == 10 then
    -- Left/Right move the piece selector ($C2, 21 entries, starts at 1; the
    -- editor polls the pad every 8 frames so presses are checked, not counted),
    -- B places the piece; placing the finish line (entry 20) sets $BF and
    -- then B (with nothing else held) commits and leaves. Place one ordinary piece first.
    if T.now() > t0 then
      if T.rd(0xC2) ~= 3 then T.press("Right") else T.press("B"); t0 = T.now() + 1.5; step = 11 end
    end
  elseif step == 11 then
    if T.now() > t0 then
      if T.rd(0xC2) ~= 20 then T.press("Left") else T.press("B"); t0 = T.now() + 2.0; step = 115 end
    end
  elseif step == 115 then
    if T.now() > t0 then
      if T.rd(0xBF) == 0 then return fail(string.format("finish line not placed ($C2=%d $49=%02X $BE=%02X)", T.rd(0xC2), T.rd(0x49), T.rd(0xBE))) end
      log("finish line placed; leaving with B"); T.press("B"); t0 = T.now() + 2.0; step = 12
    end
  elseif step == 12 then
    if in_menu() then log("left the design editor after placing pieces"); step = 13
    elseif T.now() > t0 then fail(string.format("still in state %d after B ($BF=%02X $49=%02X)", T.rd(STATE), T.rd(0xBF), T.rd(0x49))) end
  elseif step == 13 then cursor_to(3, 14)                      -- SAVE
  elseif step == 14 then                                  -- the picker, on the loaded slot
    if T.find("SAVE SLOT 05") then log("picker up on 05"); settle = T.now() + 1.0; step = 141 end
  elseif step == 141 then
    if T.row(20) ~= "" and T.now() > settle then log("slot info: " .. T.row(20)); T.press("A"); step = 142
    elseif T.now() > settle + 2 then fail("no slot info: " .. T.row(20)) end
  elseif step == 142 then
    if editor() then
      log("editor up: " .. T.row(4) .. " / " .. T.row(12))
      if not T.row(4):find("SAVE SLOT 05", 1, true) then return fail("editor title: " .. T.row(4)) end
      T.type("ZZ")                      -- name
      T.press("Right", 7)               -- into the USER field, cell 0
      T.press("Up"); T.press("Down")    -- touch it and put it back
      T.press("A")
      t0 = T.now(); step = 15
    end
  elseif step == 15 then                                  -- 05 is held by someone: confirm asks
    local rows = T.row(4) .. "|" .. T.row(8) .. "|" .. T.row(16) .. "|" .. T.row(20)
    if rows ~= last_rows then log("screen: " .. rows); last_rows = rows end
    if T.find("A REPLACE") then log("confirmation up; backing out"); T.press("B"); step = 16
    elseif T.find("SAVED") then fail("saved without asking")
    elseif T.find("NET ERROR") or T.find("BAD DATA") then fail("owner check: " .. T.row(16))
    elseif in_menu() and T.now() > t0 + 1 then fail("back in the menu with no confirmation")
    elseif T.now() > t0 + 10 then fail("nothing happened after A") end
  elseif step == 16 then
    if T.find("SAVE SLOT 05") and not T.find("HAS") then T.press("B"); step = 17 end
  elseif step == 17 then
    if in_menu() and not T.find("SLOT") then
      done = true
      T.verdict(true, string.format("DESIGN -> SAVE: picker, editor, confirmation and back, nothing written (%.1fs)", T.now()))
    end
  end
end)
