// excitebike-tracks -- a public repository for Excitebike design-mode tracks,
// saved and loaded by the game itself through a FujiNet NES cartridge.
//
// The game POSTs the 320 bytes it would have written to cassette (64-byte
// header block + 256-byte track block) to /api/track/NN and GETs them back.
// Every upload is kept as a new version of its slot. See README.md.
package main

import (
	"flag"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

type arrayFlag []string

func (a *arrayFlag) String() string     { return strings.Join(*a, ",") }
func (a *arrayFlag) Set(v string) error { *a = append(*a, v); return nil }

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	var addr, dbPath, schema string
	var proxies arrayFlag
	flag.StringVar(&addr, "addr", env("TRACKS_ADDR", ":8080"), "<address:port> to listen on (or TRACKS_ADDR)")
	flag.StringVar(&dbPath, "db", env("TRACKS_DB", "db/tracks.sqlite3"), "sqlite database file (or TRACKS_DB)")
	flag.StringVar(&schema, "schema", "schema.sql", "schema applied to a new database")
	flag.Var(&proxies, "trustedproxy", "<ip|cidr> of a reverse proxy allowed to set X-Forwarded-For (repeatable)")
	prod := flag.Bool("prod", false, "release mode: no per-request debug output")
	flag.Parse()

	if *prod {
		gin.SetMode(gin.ReleaseMode)
	}
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o755); err != nil {
		log.Fatal(err)
	}
	store, err := OpenStore(dbPath, schema)
	if err != nil {
		log.Fatal(err)
	}
	r := NewRouter(store)
	if len(proxies) > 0 {
		if err := r.SetTrustedProxies(proxies); err != nil {
			log.Fatal(err)
		}
	} else {
		_ = r.SetTrustedProxies(nil)
	}
	log.Printf("excitebike track repository listening on %s, database %s", addr, dbPath)
	log.Fatal(r.Run(addr))
}
