-- ebtest.lua -- end-to-end against a FRESH server database (make ebtest):
-- LOAD shows NO TRACKS -> a track seeded by curl as another user -> SAVE: the
-- slot picker shows EMPTY, the editor is titled with the slot and B returns
-- to the picker, a typed name -> the server has name, user and bytes -> wipe
-- RAM -> LOAD picks it from the list and restores it -> SAVE onto the other
-- user's slot: the picker shows the owner, the confirmation asks (B backs out
-- to the picker, A replaces). The username comes from the
-- FujiNet's shared app key; the test never edits it, and checks the key file
-- is unchanged at the end.
--   EB_TEST_DIR  this directory             EB_SERVER   default http://localhost:8080
--   EB_KEYFILE   fujinet-pc's 00010100.key  EB_SAMPLE   a 320-byte track to seed with
--   EB_TIMEOUT   seconds (default 200)
local T = dofile(os.getenv("EB_TEST_DIR") .. "/ebtext.lua")
local timeout = tonumber(os.getenv("EB_TIMEOUT") or "200")
local server = os.getenv("EB_SERVER") or "http://localhost:8080"
local keyfile = os.getenv("EB_KEYFILE")
local sampl = os.getenv("EB_SAMPLE")

local STATE, CURSOR = 0x41, 0x42         -- design menu = state 8; SAVE = 3, LOAD = 4
local HDR, TRK, MASTER = 0x0060, 0x05E0, 0x06E0
local BEST_A, BEST_B = 0x05A0, 0x05C3

local step, done = 1, false
local me, saved_hdr, saved_trk, attrs0, key0, settle
local function fail(msg) done = true; print(T.screen()); T.verdict(false, msg) end
local function log(msg) print(string.format("%6.2fs %s", T.now(), msg)) end
local function failed_text()
  return T.find("NET ERROR") or T.find("NO FUJINET") or T.find("BAD DATA")
end
local function in_menu() return T.rd(STATE) == 8 and T.find("SAVE") and T.find("LOAD") end
local function cursor_to(n, nextstep)
  if T.rd(CURSOR) ~= n then T.press("Select") else T.press("Start"); step = nextstep end
end
-- The editor's labels land one vblank before its fields; the cursor star on
-- row 9 is drawn with the fields, so only then is the USER field readable.
local function editor_ready()
  return T.row(4):find("SAVE SLOT", 1, true) and T.find("NAME") and T.find("USER") and T.row(9):sub(13, 13) == "*"
end
local function curl(path) return T.sh("curl -s '" .. server .. path .. "'") end
local function versions(slot)
  local _, n = curl("/api/track/" .. slot .. "/versions"):gsub('"version":', "")
  return n
end

-- the track we plant before saving: 3 laps, a few pieces, finish, end
local plant = { 0x03, 0x40, 0x12, 0x08, 0x07, 0x40, 0x05, 0x0E, 0x05, 0x40, 0x20, 0x09, 0x00 }
local plant_hex = (function()
  local t = {} for _, v in ipairs(plant) do t[#t + 1] = string.format("%02x", v) end return table.concat(t)
end)()

T.every_frame(function()
  if done then return end
  if T.now() > timeout then return fail("timeout at step " .. step) end
  -- our screens must never let the stack reach the bottom of page 1
  if T.rd(STATE) == 8 and T.sp() < 0xA0 then return fail(string.format("SP %02X", T.sp())) end
  if T.pump() then return end

  if step == 1 then                                  -- title screen
    if T.find("SELECTION A") and T.find("DESIGN") then
      log("title up"); T.press("Select", 2); T.press("Start"); step = 2
    end
  elseif step == 2 then                              -- design menu: plant a track
    if in_menu() then
      for i, v in ipairs(plant) do T.wr(MASTER + i - 1, v) end
      T.wr(BEST_A, 0x12); T.wr(BEST_A + 1, 0x34); T.wr(BEST_A + 2, 0x56)
      T.wr(BEST_B, 0x21); T.wr(BEST_B + 1, 0x43); T.wr(BEST_B + 2, 0x65)
      attrs0 = T.attrs()
      key0 = keyfile and T.readfile(keyfile)
      log("design menu up, track planted"); step = 3
    end
  elseif step == 3 then cursor_to(4, 4)              -- LOAD on an empty server
  elseif step == 4 then
    if T.find("NO TRACKS") then log("empty repository reported"); step = 5
    elseif T.find("LOAD TRACK") then
      if T.now() > 8 then fail("list shown on a supposedly empty server (run via make ebtest)") end
    elseif failed_text() then fail("load: " .. T.row(16)) end
  elseif step == 5 then
    if in_menu() and not T.find("NO TRACKS") then
      if T.hex(MASTER, 256):sub(1, #plant_hex) ~= plant_hex then return fail("NO TRACKS changed the track") end
      local r = T.sh("curl -s -X POST --data-binary @" .. sampl .. " '" .. server .. "/api/track/05?name=SEEDED&user=OTHER'")
      if r ~= "OK" then return fail("seeding slot 05 failed: " .. r) end
      log("slot 05 seeded as OTHER"); step = 6
    end
  elseif step == 6 then cursor_to(3, 7)              -- SAVE: the slot picker first
  elseif step == 7 then
    if T.find("SAVE SLOT 00") then
      if T.row(18):find("%d") then return fail("name row shows cold-boot garbage: " .. T.row(18)) end
      settle = T.now() + 0.8; step = 71
    elseif failed_text() then fail("save: " .. T.row(16)) end
  elseif step == 71 then                             -- info for slot 00 settles in
    if T.row(20):find("EMPTY", 1, true) then log("picker up, slot 00 EMPTY"); T.press("Up", 7); step = 72
    elseif T.now() > settle then fail("no slot info for 00: " .. T.row(20)) end
  elseif step == 72 then
    if T.find("SAVE SLOT 07") then settle = T.now() + 0.8; step = 73 end
  elseif step == 73 then
    if T.row(20):find("EMPTY", 1, true) then T.shot(); T.press("A"); step = 8
    elseif T.now() > settle then fail("no slot info for 07: " .. T.row(20)) end
  elseif step == 8 then                              -- the editor, titled with the slot
    if editor_ready() then
      if not T.row(4):find("SAVE SLOT 07", 1, true) then return fail("editor title: " .. T.row(4)) end
      me = T.row(12):match("USER%s+(%w+)")
      if not me then return fail("the USER field is blank: fujinet-pc has no 00010100.key username") end
      log("editor up for slot 07, user " .. me .. "; B must go back to the picker")
      T.press("B"); step = 81
    elseif failed_text() then fail("save: " .. T.row(16)) end
  elseif step == 81 then
    if T.find("SAVE SLOT 07") and not T.find("NAME") then log("back on the picker"); T.press("A"); step = 82 end
  elseif step == 82 then
    if editor_ready() then T.type("LUA"); step = 9 end
  elseif step == 9 then
    if T.row(8):find("NAME  LUA", 1, true) then T.shot(); T.press("A"); step = 11 end
  elseif step == 11 then                             -- the POST happened
    if T.find("SAVED SLOT 07") then
      saved_hdr, saved_trk = T.hex(HDR, 64), T.hex(TRK, 256)
      if saved_hdr:sub(3, 10) ~= "17010001" then return fail("header lacks the signature") end
      if saved_hdr:sub(11, 22) ~= "123456214365" then return fail("header lacks the best times") end
      if saved_trk:sub(1, #plant_hex) ~= plant_hex then return fail("saved track is not the planted one") end
      if not T.row(18):find("LUA", 1, true) then return fail("name missing under SAVED") end
      log("saved"); step = 12
    elseif T.find("SLOT 07 HAS") then fail("unexpected overwrite prompt on an empty slot")
    elseif failed_text() then fail("save: " .. T.row(16)) end
  elseif step == 12 then                             -- back in the menu: ask the server
    if in_menu() and not T.find("SAVED") then
      if T.attrs() ~= attrs0 then return fail("menu attributes differ after our screens") end
      local j = curl("/api/tracks")
      for _, want in ipairs({ '"slot":"07"', '"name":"LUA"', '"user":"' .. me .. '"', '"name":"SEEDED"' }) do
        if not j:find(want, 1, true) then return fail("server JSON lacks " .. want .. ": " .. j) end
      end
      local got = T.sh("curl -s " .. server .. "/api/track/07 | xxd -p | tr -d '\\n'")
      if got ~= saved_hdr .. saved_trk then return fail("server bytes differ: " .. got:sub(1, 40)) end
      log("server holds name, user and the 320 bytes")
      for i = 0, 255 do T.wr(TRK + i, 0xEE); T.wr(MASTER + i, 0xEE) end
      for i = 0, 2 do T.wr(BEST_A + i, 0); T.wr(BEST_B + i, 0) end
      for i = 1, 10 do T.wr(HDR + i, 0) end
      step = 13
    end
  elseif step == 13 then cursor_to(4, 14)            -- LOAD: the list
  elseif step == 14 then
    if T.find("LOAD TRACK") and T.find("05 SEEDED   OTHER") and T.find("07 LUA      " .. me) then
      if T.row(6):sub(5, 5) ~= "*" then return fail("cursor not on the first line: " .. T.row(6)) end
      if not T.find("PAGE  1 OF  1") then return fail("page numbers: " .. T.row(4)) end
      log("list up"); settle = T.now() + 0.3; step = 145
    elseif failed_text() or T.find("NO TRACKS") then fail("load list: " .. T.row(16)) end
  elseif step == 145 then                            -- the page takes five vblanks to draw;
    if T.now() > settle then T.press("Down"); step = 15 end   -- a press during that is ignored
  elseif step == 15 then
    if T.row(8):sub(5, 5) == "*" and T.row(6):sub(5, 5) ~= "*" then
      T.shot(); T.press("A"); step = 16
    end
  elseif step == 16 then
    if T.find("LOADED SLOT 07") and T.row(18):find("LUA", 1, true) then log("loaded"); step = 17
    elseif failed_text() or T.find("EMPTY SLOT") then fail("load: " .. T.row(16)) end
  elseif step == 17 then                             -- the game committed it
    if in_menu() and not T.find("LOADED") then
      if T.hex(HDR + 1, 10) ~= saved_hdr:sub(3, 22) then return fail("header not restored: " .. T.hex(HDR + 1, 10)) end
      if T.hex(TRK, 256) ~= saved_trk then return fail("working track not restored") end
      if T.hex(MASTER, 256) ~= saved_trk then return fail("master track not committed") end
      if T.hex(BEST_A, 3) .. T.hex(BEST_B, 3) ~= "123456214365" then return fail("best times not restored") end
      log("RAM restored and committed; now saving onto OTHER's slot")
      step = 18
    end
  elseif step == 18 then cursor_to(3, 19)            -- SAVE onto slot 05
  elseif step == 19 then
    if T.find("SAVE SLOT 07") then T.press("Down", 2); step = 20 end
  elseif step == 20 then
    if T.find("SAVE SLOT 05") then settle = T.now() + 0.8; step = 201 end
  elseif step == 201 then
    if T.row(20):find("SEEDED   BY OTHER", 1, true) then
      log("picker shows the owner of 05"); T.shot(); T.press("A"); step = 21
    elseif T.now() > settle then fail("slot 05 info: " .. T.row(20)) end
  elseif step == 21 then
    if editor_ready() and T.row(8):find("NAME  LUA", 1, true) then T.press("A"); step = 22 end  -- name pre-filled
  elseif step == 22 then                             -- confirmation: back out
    if T.find("SLOT 05 HAS") and T.find("SEEDED") and T.find("BY") and T.find("OTHER") and T.find("A REPLACE") then
      T.shot(); log("overwrite prompt up"); T.press("B"); step = 23
    elseif T.find("SAVED") then fail("saved over another user's slot without asking")
    elseif failed_text() then fail("owner check: " .. T.row(16)) end
  elseif step == 23 then                             -- B goes back to the picker, not the menu
    if T.find("SAVE SLOT 05") and not T.find("HAS") then
      if versions("05") ~= 1 then return fail("B at the prompt still saved") end
      log("back on the picker after B"); T.press("B"); step = 231
    end
  elseif step == 231 then
    if in_menu() and not T.find("SLOT") then step = 24 end
  elseif step == 24 then cursor_to(3, 25)            -- and again, replacing
  elseif step == 25 then
    if T.find("SAVE SLOT 05") then T.press("A"); step = 26 end
  elseif step == 26 then
    if editor_ready() and T.row(8):find("NAME  LUA", 1, true) then T.press("A"); step = 27 end
  elseif step == 27 then
    if T.find("A REPLACE") then T.press("A"); step = 28 end
  elseif step == 28 then
    if T.find("SAVED SLOT 05") then log("replaced"); step = 29
    elseif failed_text() then fail("replace: " .. T.row(16)) end
  elseif step == 29 then
    if in_menu() and not T.find("SAVED") then
      if versions("05") ~= 2 then return fail("replace did not add a version") end
      local j = curl("/api/tracks?bin=1&slot=05")
      if j:sub(1, 1) ~= "\1" or j:sub(6, 13) ~= "LUA     " or j:sub(14, 21) ~= (me .. string.rep(" ", 8 - #me)) then
        return fail("slot 05 record is not LUA/" .. me)
      end
      if keyfile and T.readfile(keyfile) ~= key0 then return fail("the username app key changed") end
      done = true
      T.verdict(true, string.format("names, list, confirm and app key all good in %.1fs", T.now()))
    end
  end
end)
