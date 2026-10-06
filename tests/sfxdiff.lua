-- sfxdiff.lua -- log every APU register write for a while after forcing the
-- sound whose data lived at $FFF0 (sound id $80: lowest set bit 7 -> table byte $FDDA = entry $23 at $FDF6). Run on the original and on
-- the patched ROM; the two logs must be identical. On the patched ROM also
-- counts reads of the relocated copy at $BFF0 so the test proves the fragment
-- was actually consumed.
--   EB_LOG  output file          EB_TEST_DIR  this directory
local T = dofile(os.getenv("EB_TEST_DIR") .. "/ebtext.lua")
local out = assert(io.open(os.getenv("EB_LOG"), "w"))
local cpu = T.cpu_space()
local frame, reads = 0, 0
local wtap, rtap

T.every_frame(function()
  frame = frame + 1
  if frame == 150 then
    wtap = cpu:install_write_tap(0x4000, 0x4017, "apu", function(offset, data, mask)
      out:write(string.format("%d %04X %02X\n", frame, offset, data & 0xFF))
    end)
    rtap = cpu:install_read_tap(0xBFF0, 0xBFFF, "frag", function(offset, data, mask)
      reads = reads + 1
    end)
    cpu:write_u8(0xFB, 0x80)                       -- request sound $80 (song table entry $FDF6)
  elseif frame == 150 + 240 then
    out:write(string.format("# frag reads %d\n", reads))
    out:close()
    print(string.format("sfxdiff: %d reads of $BFF0-$BFFF", reads))
    manager.machine:exit()
  end
end)
