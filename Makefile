# Makefile -- build, play and test the whole rig on this workstation: the
# patched ROM, the track server, fujinet-pc (RS232 build with Bus-over-IP) and
# MAME with the FujiNet NES slot device.
#
#   make play        build what is missing, start what is not running, open MAME
#   make test        server unit tests + every MAME test (starts/stops the server)
#   make status      what is up
#   make stop        stop the track server (and fujinet-pc, if make started it)
#
# Knobs: MAME=~/src/mame  FUJINET_PC=.../fujinet-pc/build/dist  SERVER_PORT=8080
#        DEBUG=1 (MAME logs every mailbox transaction)  PLAY_ARGS="-window -nomax"

SHELL       := /bin/bash
ROOT        := $(CURDIR)
MAME        ?= $(HOME)/Workspace/mame
FUJINET_PC  ?= $(HOME)/Workspace/fujinet-pc-rs232/build/dist
FUJINET_UI  ?= 0.0.0.0:8003
BOIP_PORT   ?= 9995
SERVER_PORT ?= 8080
SERVER_URL  ?= http://localhost:$(SERVER_PORT)
SECS        ?= 300
PLAY_ARGS   ?= -window -nomax

ROM         := build/excitebike-fujinet.nes
SERVER_BIN  := server/excitebike-tracks
SERVER_PID  := build/server.pid
DB          ?= $(ROOT)/server/db/tracks.sqlite3
TEST_DB     := $(ROOT)/build/test.sqlite3
KEYFILE     := $(FUJINET_PC)/SD/FujiNet/00010100.key
SAMPLE      := $(ROOT)/server/testdata/sample320.bin
FUJINET_PID := build/fujinet-pc.pid
SNAPDIR     := build/snap
DEBUG_ENV   := $(if $(DEBUG),FUJINET_DEBUG=1,)

# Is anything listening on local TCP port $(1)? Checked without connecting: a
# probe would take fujinet-pc's single Bus-over-IP connection away from MAME.
listening = ss -ltn 2>/dev/null | grep -q ':$(1) '

.PHONY: all rom server play test status stop help clean \
        server-start server-stop fujinet-start fujinet-stop \
        nocart ebtest errors sfxdiff repro

all: rom server

# ---- build ---------------------------------------------------------------

rom: $(ROM)

$(ROM): build.py tools/bps.py tools/checkrom.py $(wildcard patch/*) rom/excitebike.nes
	python3 build.py --server-url $(SERVER_URL)

server: $(SERVER_BIN)

$(SERVER_BIN): $(wildcard server/*.go) server/go.mod server/index.html server/schema.sql
	cd server && go build -o excitebike-tracks .

# ---- services ------------------------------------------------------------

server-start: $(SERVER_BIN)
	@if $(call listening,$(SERVER_PORT)); then \
	    echo "track server: already listening on :$(SERVER_PORT)"; \
	else \
	    mkdir -p build server/db; \
	    ( cd server && exec nohup ./excitebike-tracks -addr :$(SERVER_PORT) \
	        -db $(DB) -schema $(ROOT)/server/schema.sql \
	        >> $(ROOT)/build/server.log 2>&1 ) & echo $$! > $(SERVER_PID); \
	    sleep 1; \
	    curl -sf -o /dev/null http://localhost:$(SERVER_PORT)/healthz \
	        && echo "track server: started on :$(SERVER_PORT), db $(DB) (pid $$(cat $(SERVER_PID)), log build/server.log)" \
	        || { echo "track server: failed to start, see build/server.log"; exit 1; }; \
	fi

# Stops the server make started, or any excitebike-tracks holding the port.
server-stop:
	@pid=""; \
	if [ -f $(SERVER_PID) ] && kill -0 $$(cat $(SERVER_PID)) 2>/dev/null; then pid=$$(cat $(SERVER_PID)); \
	else pid=$$(ss -ltnp 2>/dev/null | awk '/:$(SERVER_PORT) /' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2); fi; \
	if [ -n "$$pid" ] && [ "$$(ps -o comm= -p $$pid 2>/dev/null)" = excitebike-trac ]; then \
	    kill $$pid && sleep 0.5 && echo "track server: stopped (pid $$pid)"; \
	elif [ -n "$$pid" ]; then \
	    echo "track server: port :$(SERVER_PORT) belongs to pid $$pid ($$(ps -o comm= -p $$pid)), left alone"; \
	else echo "track server: not running"; fi; \
	rm -f $(SERVER_PID)

fujinet-start:
	@if $(call listening,$(BOIP_PORT)); then \
	    echo "fujinet-pc: already listening for Bus-over-IP on :$(BOIP_PORT)"; \
	else \
	    [ -x $(FUJINET_PC)/fujinet ] || { echo "fujinet-pc: no binary at $(FUJINET_PC)/fujinet (set FUJINET_PC)"; exit 1; }; \
	    grep -q '^port=$(BOIP_PORT)' $(FUJINET_PC)/fnconfig.ini \
	        || echo "fujinet-pc: warning: $(FUJINET_PC)/fnconfig.ini has no [BOIP] port=$(BOIP_PORT)"; \
	    mkdir -p build; \
	    ( cd $(FUJINET_PC) && exec nohup ./fujinet -u $(FUJINET_UI) >> $(ROOT)/build/fujinet-pc.log 2>&1 ) & \
	    echo $$! > $(FUJINET_PID); \
	    for i in $$(seq 20); do $(call listening,$(BOIP_PORT)) && break; sleep 1; done; \
	    $(call listening,$(BOIP_PORT)) \
	        && echo "fujinet-pc: started (pid $$(cat $(FUJINET_PID)), web UI $(FUJINET_UI), log build/fujinet-pc.log)" \
	        || { echo "fujinet-pc: did not open :$(BOIP_PORT); see build/fujinet-pc.log"; exit 1; }; \
	fi

# Only a fujinet-pc that make started; a long-running one of yours is left alone.
fujinet-stop:
	@if [ -f $(FUJINET_PID) ] && kill -0 $$(cat $(FUJINET_PID)) 2>/dev/null; then \
	    kill $$(cat $(FUJINET_PID)) && echo "fujinet-pc: stopped (pid $$(cat $(FUJINET_PID)))"; \
	else echo "fujinet-pc: not started by make"; fi; \
	rm -f $(FUJINET_PID)

stop: server-stop fujinet-stop

status:
	@$(call listening,$(SERVER_PORT)) && echo "track server : up, $(SERVER_URL)/" || echo "track server : down"
	@$(call listening,$(BOIP_PORT))   && echo "fujinet-pc   : Bus-over-IP on :$(BOIP_PORT)" || echo "fujinet-pc   : down"
	@[ -x $(MAME)/mame ] && echo "mame         : $(MAME)/mame" || echo "mame         : missing at $(MAME) (set MAME; the tree needs fn-nes/pico/nes/emu/apply.sh)"
	@[ -f $(ROM) ] && echo "rom          : $(ROM) ($(SERVER_URL))" || echo "rom          : not built (make rom)"

# ---- play ----------------------------------------------------------------

play: $(ROM) server-start fujinet-start
	@[ -x $(MAME)/mame ] || { echo "no MAME at $(MAME)/mame (set MAME=...; the tree needs fn-nes/pico/nes/emu/apply.sh)"; exit 1; }
	@mkdir -p $(SNAPDIR)
	@echo
	@echo "Excitebike + FujiNet.  Title: Select, Select, Start -> design menu."
	@echo "Select moves the cursor, Start picks.  SAVE and LOAD ask for a slot:"
	@echo "Up/Down +-1, Left/Right +-10, A confirms, B backs out."
	@echo "Saved tracks: $(SERVER_URL)/        Afterwards: make stop"
	@echo
	cd $(MAME) && $(DEBUG_ENV) ./mame nes -nes_slot fujinet -cart $(ROOT)/$(ROM) $(PLAY_ARGS) \
	    -snapshot_directory $(ROOT)/$(SNAPDIR)

# ---- tests ---------------------------------------------------------------

nocart: $(ROM)
	tests/run-mame.sh nocart

# ebtest wants an empty repository: it runs the server on its own database.
ebtest: $(ROM) $(SERVER_BIN) fujinet-start
	@$(MAKE) --no-print-directory server-stop
	@rm -f $(TEST_DB) $(TEST_DB)-wal $(TEST_DB)-shm
	@$(MAKE) --no-print-directory server-start DB=$(TEST_DB)
	EB_KEYFILE=$(KEYFILE) EB_SAMPLE=$(SAMPLE) SECS=$(SECS) tests/run-mame.sh ebtest; rc=$$?; \
	    $(MAKE) --no-print-directory server-stop; exit $$rc

errors: $(ROM) fujinet-start
	@$(MAKE) --no-print-directory server-stop
	SECS=$(SECS) tests/run-mame.sh errors

# The user's own session, against the real database (reads only): LOAD a slot,
# DESIGN, SAVE through picker, editor and confirmation, back out.
repro: $(ROM) server-start fujinet-start
	SECS=$(SECS) tests/run-mame.sh repro

sfxdiff: $(ROM)
	EB_LOG=$(ROOT)/build/sfx-orig.log    SECS=40 tests/run-mame.sh sfxdiff $(ROOT)/rom/excitebike.nes
	EB_LOG=$(ROOT)/build/sfx-patched.log SECS=40 tests/run-mame.sh sfxdiff $(ROOT)/$(ROM)
	@grep -v '^#' build/sfx-orig.log > build/sfx-orig.cmp; grep -v '^#' build/sfx-patched.log > build/sfx-patched.cmp
	@cmp -s build/sfx-orig.cmp build/sfx-patched.cmp && echo "sfxdiff: APU writes identical" \
	    || { echo "sfxdiff: FAIL: APU writes differ (diff build/sfx-orig.log build/sfx-patched.log)"; exit 1; }
	@grep -q '^# frag reads [1-9]' build/sfx-patched.log && echo "sfxdiff: relocated fragment at \$$BFF0 was read" \
	    || { echo "sfxdiff: FAIL: the patched ROM never read \$$BFF0"; exit 1; }

test: $(ROM)
	cd server && go test ./...
	@$(MAKE) --no-print-directory nocart
	@$(MAKE) --no-print-directory ebtest
	@$(MAKE) --no-print-directory errors
	@$(MAKE) --no-print-directory sfxdiff
	@$(MAKE) --no-print-directory server-start
	@$(MAKE) --no-print-directory repro
	@echo; echo "all rig tests passed; the track server is up for make play"

clean:
	rm -rf build $(SERVER_BIN) server/db

help:
	@sed -n '2,12p' Makefile | cut -c3-
