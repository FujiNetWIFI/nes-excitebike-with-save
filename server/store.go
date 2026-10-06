package main

import (
	"database/sql"
	"errors"
	"log"
	"os"
	"time"

	"github.com/jmoiron/sqlx"
	_ "github.com/mattn/go-sqlite3"
)

// Store is the SQLite behind the repository: every upload is a new version of
// its slot, nothing is ever overwritten.
type Store struct {
	db *sqlx.DB
}

type TrackRow struct {
	Slot      int       `db:"slot" json:"-"`
	Version   int       `db:"version" json:"version"`
	Data      []byte    `db:"data" json:"-"`
	Remote    string    `db:"remote" json:"-"`
	Name      string    `db:"name" json:"name"`
	User      string    `db:"username" json:"user"`
	CreatedAt time.Time `db:"created_at" json:"created_at"`
}

// SlotRow is one line of the slot summary: the latest version's name, user
// and data, with the version count. updated_at comes out of MAX() as text,
// not as a declared DATETIME, so it is parsed by hand (see Updated).
type SlotRow struct {
	Slot      int    `db:"slot"`
	Versions  int    `db:"versions"`
	UpdatedAt string `db:"updated_at"`
	Name      string `db:"name"`
	User      string `db:"username"`
	Data      []byte `db:"data"`
}

// Updated parses the SQLite timestamp text; zero time if it does not parse.
func (r SlotRow) Updated() time.Time {
	for _, layout := range []string{"2006-01-02 15:04:05", time.RFC3339, "2006-01-02T15:04:05Z07:00"} {
		if t, err := time.Parse(layout, r.UpdatedAt); err == nil {
			return t
		}
	}
	return time.Time{}
}

var ErrNotFound = errors.New("not found")

const trackColumns = `slot, version, data, remote, name, username, created_at`

// OpenStore connects (WAL, busy timeout), creates the schema if the file is
// new, and adds any column an older database lacks.
func OpenStore(path, schemaFile string) (*Store, error) {
	fresh := false
	if _, err := os.Stat(path); err != nil {
		fresh = true
	}
	db, err := sqlx.Connect("sqlite3", path+"?_journal=WAL&_timeout=300&_foreign_keys=on")
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(`PRAGMA busy_timeout=300; PRAGMA journal_mode=WAL;`); err != nil {
		return nil, err
	}
	if fresh || !tableExists(db, "track") {
		schema, err := os.ReadFile(schemaFile)
		if err != nil {
			return nil, err
		}
		if _, err := db.Exec(string(schema)); err != nil {
			return nil, err
		}
	}
	if err := migrate(db); err != nil {
		return nil, err
	}
	return &Store{db: db}, nil
}

func tableExists(db *sqlx.DB, name string) bool {
	var n int
	err := db.Get(&n, `SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?`, name)
	return err == nil && n > 0
}

// migrate brings a database created by an earlier schema up to date. There
// is no migration framework: additive changes are applied here, idempotently,
// at every startup (the lobby's migrate_db pattern).
func migrate(db *sqlx.DB) error {
	var cols []string
	if err := db.Select(&cols, `SELECT name FROM pragma_table_info('track')`); err != nil {
		return err
	}
	have := map[string]bool{}
	for _, c := range cols {
		have[c] = true
	}
	for _, col := range []string{"name", "username"} {
		if have[col] {
			continue
		}
		if _, err := db.Exec(`ALTER TABLE track ADD COLUMN ` + col + ` TEXT NOT NULL DEFAULT ''`); err != nil {
			return err
		}
		log.Printf("database: added column track.%s", col)
	}
	return nil
}

// Insert stores data as the next version of slot and returns that version.
func (s *Store) Insert(slot int, data []byte, remote, name, user string) (int, error) {
	tx, err := s.db.Beginx()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var version int
	if err := tx.Get(&version, `SELECT COALESCE(MAX(version), 0) + 1 FROM track WHERE slot = ?`, slot); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(`INSERT INTO track (slot, version, data, remote, name, username) VALUES (?, ?, ?, ?, ?, ?)`,
		slot, version, data, remote, name, user); err != nil {
		return 0, err
	}
	return version, tx.Commit()
}

// Latest returns the newest version of a slot.
func (s *Store) Latest(slot int) (*TrackRow, error) {
	var row TrackRow
	err := s.db.Get(&row, `SELECT `+trackColumns+` FROM track WHERE slot = ? ORDER BY version DESC LIMIT 1`, slot)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &row, err
}

func (s *Store) Version(slot, version int) (*TrackRow, error) {
	var row TrackRow
	err := s.db.Get(&row, `SELECT `+trackColumns+` FROM track WHERE slot = ? AND version = ?`, slot, version)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &row, err
}

// Versions lists a slot's versions, newest first.
func (s *Store) Versions(slot int) ([]TrackRow, error) {
	rows := []TrackRow{}
	err := s.db.Select(&rows, `SELECT `+trackColumns+` FROM track WHERE slot = ? ORDER BY version DESC`, slot)
	return rows, err
}

// Slots lists every slot in use with its latest version's name, user and
// data, the version count and the last upload time.
func (s *Store) Slots() ([]SlotRow, error) {
	rows := []SlotRow{}
	err := s.db.Select(&rows, `
		SELECT t.slot, c.versions, c.updated_at, t.name, t.username, t.data
		FROM track t
		JOIN (SELECT slot, COUNT(*) AS versions, MAX(version) AS maxv, MAX(created_at) AS updated_at
		      FROM track GROUP BY slot) c
		  ON c.slot = t.slot AND c.maxv = t.version
		ORDER BY t.slot`)
	return rows, err
}
