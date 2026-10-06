# Excitebike with FujiNet save/load

An experiment: Excitebike's design mode has SAVE and LOAD, which on the Famicom
wrote the designed track to a cassette through the Family Computer Data
Recorder. On an NES nothing is connected: SAVE toggles `$4016` into the void for
twenty seconds and LOAD waits forever. This patch points both at a FujiNet NES
cartridge instead, so a track is POSTed to, and fetched from, a public track
repository on the internet.

- `patch/`, `build.py` -- the ROM patch (6502, cc65) and the script that builds
  `build/excitebike-fujinet.nes` and a BPS patch from `rom/excitebike.nes`.
- `server/` -- the track repository: Go + Gin + SQLite, every save kept as a
  new version of its slot, with a small HTML index.
- `tests/` -- MAME Lua tests (end-to-end save/load, no-cartridge path, sound
  regression) and an FCEUX script.

## What the player sees

In the design menu choose SAVE or LOAD as before.

**SAVE** opens on the slot picker, `SAVE SLOT 05` (the slot you last loaded
or saved): Up/Down change it by one, Left/Right by ten. Half a second after
the number stops, the row below shows what that slot holds (`EMPTY`, or
`MYTRACK  BY THOM`). A goes on to the name editor, titled `SAVE SLOT 05`: a
NAME field and a USER field of eight cells each (A-Z, 0-9, space).
Left/Right move the cursor, Up/Down change the glyph, A or Start accepts, B
goes back to the picker. The USER field is pre-filled from the FujiNet's
shared player-name app key (the one the lobby and its games use, creator
`0001` app `01` key `00`); editing it writes the key back, so the name sticks
across power cycles and is the same in every FujiNet game. If the slot holds
another player's track the game shows its name and owner and asks
`A REPLACE  B BACK` (B returns to the picker). Then `SAVING 05` and
`SAVED SLOT 05` with the track name underneath. Tracks saved before names
existed show as `UNNAMED` by `UNKNOWN`.

**LOAD** fetches the repository and lists it ten slots a page:
`* 07 MYTRACK  THOM`. Up/Down move the star, Left/Right page, A loads the
track under the star, B goes back. `LOADED SLOT 07` restores the track and the
two best times saved with it, and the loaded name becomes the next SAVE's
default. The slot, page and names are remembered until the console is powered
off (they survive Reset).

| Text | Meaning |
|---|---|
| `NO TRACKS` | the repository is empty |
| `NO FUJINET` | no FujiNet cartridge is answering (plain NES, other flash cart, FCEUX) |
| `NET ERROR xx` | the FujiNet or the server said no; xx is the error code in hex |
| `BAD DATA` | the server's answer was not what the game expects |
| `ENTER A NAME`, `USER 2 TO 8 CHARS` | the editor will not accept an empty name or a bad user name |
| `NO INFO` | the picker could not ask the server about that slot (you can still try to save) |

A failed or cancelled LOAD leaves the current track and best times untouched.

## Quick start on a workstation

```sh
make play      # builds ROM + server, starts the server and fujinet-pc if they
               # are not already listening, opens MAME with the FujiNet slot
make test      # go test + every MAME test (nocart, ebtest, errors, sfxdiff)
make status    # what is up;  make stop  stops what make started
```

`make play` expects MAME at `~/Workspace/mame` with the FujiNet NES slot grafted
in (`fujinet-firmware/pico/nes/emu/apply.sh`) and a fujinet-pc RS232 build at
`~/Workspace/fujinet-pc-rs232/build/dist` whose `fnconfig.ini` has `[BOIP]
enabled=1` on port 9995; override with `MAME=...` and `FUJINET_PC=...`. A
fujinet-pc that is already listening is used as is. `DEBUG=1 make play` logs
every mailbox transaction.

## Building the ROM

Needs cc65 (`ca65`, `ld65`) and Python 3. Put the original ROM at
`rom/excitebike.nes` (Excitebike (JU), 16 K PRG + 8 K CHR; `build.py` checks
the md5 and refuses anything else).

```sh
python3 build.py                                  # talks to http://localhost:8080
python3 build.py --server-url https://tracks.example.org
```

Outputs in `build/`: `excitebike-fujinet.nes` (NROM-256, 40 976 bytes),
`excitebike-fujinet.bps` (apply to the original with any BPS tool; it contains
none of the game's bytes), `patchlist.txt` (every changed byte of the original
bank), `newbank.map` / `newbank.lbl`.

### How the patch works

The 16 K PRG is full, so the image grows to NROM-256 and the new code lives in
the lower bank, `$8000-$BFFF`. The original bank changes in eleven bytes:

| Address | Change |
|---|---|
| `$C1EB-$C1EC` | the main loop's `JSR $C6C8` (cassette save) now calls `eb_save` |
| `$C1F8-$C1F9` | its `JSR $C739` (cassette load) now calls `eb_load` |
| `$FDF8` | a song-table pointer: the 16 bytes at `$FFF0` moved to `$BFF0` |
| `$FFF0-$FFF3` | `FUJI`, the claim that keeps the cartridge's mailbox alive |
| `$FFFE-$FFFF` | the (never used) IRQ vector now points at an `RTI` |

Both hooks run exactly where the cassette routines ran: with NMI off and
"SAVING"/"LOADING" already on screen. They draw with the game's own list
drawer (`$C289`), read the pad with the game's routine (`$D347`), and use the
cassette code's zero-page scratch (`$00-$0F`). The slot number and a 16-byte
text record live in `$05C6-$05DF`, console RAM nothing else touches.

What travels is exactly what the cassette carried: the 64-byte header block
from `$0060` (zero, the signature `17 01 00 01`, six bytes of best times,
zeros) followed by the 256-byte track block from `$05E0`, 320 bytes in all.
The track name and user name ride on the URL
(`/api/track/07?name=MY+TRACK&user=THOM`). SAVE: `OPEN` (POST) ->
`SET_HTTP_MODE 4` -> `WRITE` 64 -> `WRITE` 256 -> `SET_HTTP_MODE 0` -> `STATUS`
(performs the request) -> `CLOSE`, preceded by a `GET /api/tracks?bin=1&slot=NN`
(the picker's slot info, reused for the owner check). LOAD: `GET /api/tracks?bin=1&page=P` (a fixed
204-byte page of ten records, rendered straight out of the mailbox's reply
window), then `OPEN` (GET) -> `STATUS` -> `READ` 320 -> check the signature ->
copy -> `CLOSE`. On a failed load the code re-primes `$65-$6A` and `$05E0`
from the game's own copies, because the LOAD state commits them
unconditionally when we return. The user name is read and written with the
FUJI device's app-key commands (`$DC`/`$DD`/`$DE`/`$DB`).

Names are kept in RAM as font tiles (`$05D0-$05DF`), draw lists are built in
the unused bottom of the stack page (`$0100-$015F`), and every screen writes
its own attribute bytes because the game clears them before SAVE/LOAD.

The mailbox is documented in fujinet-firmware `pico/nes/README.md` and
`firmware/include/fuji_mailbox.h`; `tools/checkrom.py` (copied from there)
runs at the end of every build and rejects the one instruction class the
mailbox cannot tolerate (read-modify-write on `$5500-$57FF`).

## The track server

```sh
cd server
make test             # go test
make run              # :8080, db/tracks.sqlite3 (created on first start)
make post-sample      # upload testdata/sample320.bin to slot 07 and read it back
```

| Method | Path | |
|---|---|---|
| GET | `/api/track/NN` | latest 320 bytes of slot `NN` (00-99), `application/octet-stream`; 404 when empty |
| POST, PUT | `/api/track/NN?name=&user=` | store exactly 320 bytes as a new version with a name and owner; answers `OK` |
| GET | `/api/track/NN/versions` | JSON list of versions with names |
| GET | `/api/track/NN/v/V` | one version's bytes |
| GET | `/api/tracks` | JSON summary of slots in use (name, user, laps, strip) |
| GET | `/api/tracks?bin=1&page=P` | 204 bytes for the game: `count page pages total` then ten records of `slot name[8] user[8] laps versions 0`; `&slot=NN` filters to one slot |
| GET | `/` | HTML index with a one-line strip of each track |

Uploads must be the canonical blob the game produces (320 bytes, signature at
bytes 1-4, zeros where the game leaves zeros), so everything stored loads back.
Names are folded to the game's font (uppercase A-Z, 0-9, space; eight
characters; no spaces in a user name). A database from the first version is
upgraded in place at startup (the two name columns are added).
Flags: `-addr`, `-db`, `-trustedproxy` (repeatable), `-prod`; or `TRACKS_ADDR`
and `TRACKS_DB`. Run it behind a TLS-terminating reverse proxy as the other
FujiNet servers are; the FujiNet speaks HTTPS to a public URL just as well.

## Testing

Everything was verified in MAME with the FujiNet NES slot device from
fujinet-firmware's `pico/nes` bring-up (grafted into `~/Workspace/mame`) talking
to fujinet-pc (RS232 build, Bus-over-IP on 127.0.0.1:9995). No cartridge
hardware exists yet.

```sh
tests/run-mame.sh nocart     # plain NROM slot: SAVE and LOAD show NO FUJINET and return
make ebtest                  # fresh server db + fujinet-pc: NO TRACKS, a curl-seeded slot,
                             #   SAVE with a typed name, server JSON/bytes check, wipe RAM,
                             #   LOAD from the list, overwrite prompt (B, then A), app key
                             #   untouched (screenshots land in build/snap/nes/)
make errors                  # server STOPPED: picker says NO INFO, B backs out, LOAD and
                             #   the owner check report NET ERROR, track intact
make repro                   # against the real db, reads only: LOAD a slot, DESIGN (place
                             #   pieces, finish line, B), SAVE through picker, editor and
                             #   confirmation, back out
EB_LOG=build/a.log tests/run-mame.sh sfxdiff rom/excitebike.nes
EB_LOG=build/b.log tests/run-mame.sh sfxdiff build/excitebike-fujinet.nes
diff build/a.log build/b.log      # APU writes identical; b.log counts reads of $BFF0
fceux --loadlua tests/fceux_nocart.lua build/excitebike-fujinet.nes
```

`FUJINET_DEBUG=1 tests/run-mame.sh ebtest` logs every mailbox transaction.
For a look rather than a test: `cd ~/Workspace/mame && ./mame nes -nes_slot
fujinet -cart .../build/excitebike-fujinet.nes -window`.

## Credits and references

- Excitebike disassembly and RAM map: cyneprepou4uk/NES-Games-Disassembly.
- Data Recorder format notes: nesdev wiki, okuyam2y/NES_MiSTer-family-basic
  (`ebtape.py` confirms the two-block, 320-byte layout).
- FujiNet NES cartridge: fujinet-firmware `pico/nes` (branch `nes-bringup`).
