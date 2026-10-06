BIN  = excitebike-tracks
ADDR ?= :8080
DB   ?= db/tracks.sqlite3

all: build

build:
	go build -o $(BIN) .

run: build
	./$(BIN) -addr $(ADDR) -db $(DB)

test:
	go test ./...

# The server creates the database itself; this target exists for parity with
# the other FujiNet servers and for rebuilding from scratch.
install-db: $(DB)

$(DB): schema.sql
	@mkdir -p db
	@rm -f $(DB) $(DB)-wal $(DB)-shm
	sqlite3 -bail $(DB) < schema.sql

# Upload the sample track to slot 07 of a server on localhost, with a name.
post-sample:
	curl -s -X POST --data-binary @testdata/sample320.bin "http://localhost:8080/api/track/07?name=SAMPLE&user=MAKE"; echo
	curl -s http://localhost:8080/api/track/07 | cmp - testdata/sample320.bin && echo "round trip ok"
	curl -s "http://localhost:8080/api/tracks?bin=1&slot=07" | xxd | head -3

dblist:
	@sqlite3 -column -header $(DB) "select t.slot, t.name, t.username, c.versions, c.updated from track t join (select slot, count(*) versions, max(version) maxv, max(created_at) updated from track group by slot) c on c.slot=t.slot and c.maxv=t.version order by t.slot"

dbbackup:
	@sqlite3 $(DB) ".backup 'db/`date "+%Y-%m-%d"`-tracks.sqlite3'"

clean:
	rm -f $(BIN)

.PHONY: all build run test install-db post-sample dblist dbbackup clean
