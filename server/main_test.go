package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jmoiron/sqlx"
)

func newTestRouter(t *testing.T) *gin.Engine {
	gin.SetMode(gin.TestMode)
	store, err := OpenStore(filepath.Join(t.TempDir(), "t.sqlite3"), "schema.sql")
	if err != nil {
		t.Fatal(err)
	}
	return NewRouter(store)
}

func sample(t *testing.T) []byte {
	b, err := os.ReadFile("testdata/sample320.bin")
	if err != nil {
		t.Fatal(err)
	}
	if len(b) != TrackSize {
		t.Fatalf("sample is %d bytes", len(b))
	}
	return b
}

func do(r *gin.Engine, method, path string, body []byte) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, bytes.NewReader(body))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestRoundTrip(t *testing.T) {
	r := newTestRouter(t)
	s := sample(t)
	w := do(r, "POST", "/api/track/07", s)
	if w.Code != 200 || w.Body.String() != "OK" {
		t.Fatalf("POST: %d %q", w.Code, w.Body.String())
	}
	w = do(r, "GET", "/api/track/07", nil)
	if w.Code != 200 || !bytes.Equal(w.Body.Bytes(), s) {
		t.Fatalf("GET: %d, %d bytes", w.Code, w.Body.Len())
	}
	if ct := w.Header().Get("Content-Type"); ct != "application/octet-stream" {
		t.Errorf("content type %q", ct)
	}
	if cl := w.Header().Get("Content-Length"); cl != "320" {
		t.Errorf("content length %q", cl)
	}
}

func TestEmptySlot(t *testing.T) {
	r := newTestRouter(t)
	if w := do(r, "GET", "/api/track/99", nil); w.Code != 404 {
		t.Fatalf("empty slot: %d", w.Code)
	}
}

func TestBadUploads(t *testing.T) {
	r := newTestRouter(t)
	s := sample(t)
	cases := map[string][]byte{
		"short":     s[:319],
		"long":      append(append([]byte{}, s...), 0),
		"signature": append([]byte{0, 0x17, 0x01, 0x00, 0x02}, s[5:]...),
		"byte0":     append([]byte{1}, s[1:]...),
		"junkhdr":   append(append(append([]byte{}, s[:20]...), 0x55), s[21:]...),
	}
	for name, body := range cases {
		if w := do(r, "POST", "/api/track/01", body); w.Code != 400 {
			t.Errorf("%s: %d %q", name, w.Code, w.Body.String())
		}
	}
	if w := do(r, "GET", "/api/track/01", nil); w.Code != 404 {
		t.Errorf("rejected uploads were stored: %d", w.Code)
	}
}

func TestVersions(t *testing.T) {
	r := newTestRouter(t)
	s := sample(t)
	first := append([]byte{}, s...)
	first[70] = 0x03 // a different piece
	second := s
	do(r, "POST", "/api/track/7?name=first&user=ann", first)
	do(r, "PUT", "/api/track/07?name=second&user=bob", second)

	w := do(r, "GET", "/api/track/07", nil)
	if !bytes.Equal(w.Body.Bytes(), second) {
		t.Fatal("latest is not the second upload")
	}
	if w.Header().Get("X-Track-Name") != "SECOND" || w.Header().Get("X-Track-User") != "BOB" {
		t.Errorf("headers: %v", w.Header())
	}
	w = do(r, "GET", "/api/track/07/v/1", nil)
	if w.Code != 200 || !bytes.Equal(w.Body.Bytes(), first) {
		t.Fatalf("version 1: %d", w.Code)
	}
	if w := do(r, "GET", "/api/track/07/v/3", nil); w.Code != 404 {
		t.Errorf("version 3: %d", w.Code)
	}
	w = do(r, "GET", "/api/track/07/versions", nil)
	var got struct {
		Slot     string        `json:"slot"`
		Versions []versionInfo `json:"versions"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Slot != "07" || len(got.Versions) != 2 || got.Versions[0].Version != 2 ||
		got.Versions[0].Laps != 2 || got.Versions[0].Name != "SECOND" || got.Versions[1].User != "ANN" {
		t.Fatalf("versions: %+v", got)
	}
	w = do(r, "GET", "/api/tracks", nil)
	var slots []slotInfo
	if err := json.Unmarshal(w.Body.Bytes(), &slots); err != nil {
		t.Fatal(err)
	}
	if len(slots) != 1 || slots[0].SlotName != "07" || slots[0].Versions != 2 ||
		slots[0].Name != "SECOND" || slots[0].User != "BOB" {
		t.Fatalf("tracks: %+v", slots)
	}
}

func TestSlotNames(t *testing.T) {
	r := newTestRouter(t)
	for _, bad := range []string{"abc", "100", "-1", "007", "+7"} {
		if w := do(r, "GET", "/api/track/"+bad, nil); w.Code != 404 {
			t.Errorf("%q: %d", bad, w.Code)
		}
	}
}

func TestIndex(t *testing.T) {
	r := newTestRouter(t)
	do(r, "POST", "/api/track/42?name=hill+run&user=thom", sample(t))
	w := do(r, "GET", "/", nil)
	if w.Code != 200 || !bytes.Contains(w.Body.Bytes(), []byte("<code>42</code>")) {
		t.Fatalf("index: %d", w.Code)
	}
	for _, want := range []string{"HILL RUN", "THOM", "________________________________A"} {
		if !bytes.Contains(w.Body.Bytes(), []byte(want)) {
			t.Errorf("index lacks %q: %s", want, w.Body.String())
		}
	}
	if w := do(r, "GET", "/healthz", nil); w.Code != 200 {
		t.Errorf("healthz: %d", w.Code)
	}
}

func TestSummarize(t *testing.T) {
	s := Summarize(sample(t))
	if s.Laps != 2 || s.Warn != "" || s.Columns != 32+1+8+2+16+1+48+1 {
		t.Fatalf("%+v", s)
	}
}

func TestNameUser(t *testing.T) {
	r := newTestRouter(t)
	s := sample(t)
	do(r, "POST", "/api/track/03?name=my+track&user=thom", s)
	do(r, "POST", "/api/track/04", s)
	do(r, "POST", "/api/track/05?name=a%20very%20long%20name%21&user=t%20h-om", s)
	do(r, "POST", "/api/track/06?name=%20%20&user=T", s)
	w := do(r, "GET", "/api/tracks", nil)
	var slots []slotInfo
	if err := json.Unmarshal(w.Body.Bytes(), &slots); err != nil {
		t.Fatal(err)
	}
	want := map[string][2]string{"03": {"MY TRACK", "THOM"}, "04": {"", ""}, "05": {"A VERY L", "THOM"}, "06": {"", ""}}
	if len(slots) != len(want) {
		t.Fatalf("%d slots", len(slots))
	}
	for _, sl := range slots {
		if sl.Name != want[sl.SlotName][0] || sl.User != want[sl.SlotName][1] {
			t.Errorf("slot %s: %q %q", sl.SlotName, sl.Name, sl.User)
		}
	}
}

func TestBinList(t *testing.T) {
	r := newTestRouter(t)
	s := sample(t)
	w := do(r, "GET", "/api/tracks?bin=1", nil)
	if w.Code != 200 || w.Body.Len() != BinSize || !bytes.Equal(w.Body.Bytes()[:4], []byte{0, 0, 1, 0}) {
		t.Fatalf("empty list: %d %d %v", w.Code, w.Body.Len(), w.Body.Bytes()[:4])
	}
	for i := 1; i <= 12; i++ {
		do(r, "POST", fmt.Sprintf("/api/track/%02d?name=T%d&user=U%d", i*3, i, i), s)
	}
	do(r, "POST", "/api/track/03?name=T1B&user=U1", s) // a second version of the first slot

	w = do(r, "GET", "/api/tracks?bin=1&page=0", nil)
	b := w.Body.Bytes()
	if len(b) != BinSize || w.Header().Get("Content-Length") != "204" || w.Header().Get("Content-Type") != "application/octet-stream" {
		t.Fatalf("page 0: %d bytes, %v", len(b), w.Header())
	}
	if !bytes.Equal(b[:4], []byte{10, 0, 2, 12}) {
		t.Errorf("page 0 header %v", b[:4])
	}
	rec := b[4:24]
	wantRec := append(append([]byte{3}, []byte("T1B     U1      ")...), 2, 2, 0)
	if !bytes.Equal(rec, wantRec) {
		t.Errorf("record 0 %q, want %q", rec, wantRec)
	}
	w = do(r, "GET", "/api/tracks?bin=1&page=1", nil)
	b = w.Body.Bytes()
	if !bytes.Equal(b[:4], []byte{2, 1, 2, 12}) || b[4] != 33 || b[24] != 36 {
		t.Errorf("page 1 header %v slots %d %d", b[:4], b[4], b[24])
	}
	if !bytes.Equal(b[44:], make([]byte, BinSize-44)) {
		t.Errorf("page 1 tail not zero")
	}
	w = do(r, "GET", "/api/tracks?bin=1&page=9", nil)
	if b = w.Body.Bytes(); b[1] != 1 {
		t.Errorf("page 9 not clamped: %v", b[:4])
	}
	w = do(r, "GET", "/api/tracks?bin=1&slot=06", nil)
	if b = w.Body.Bytes(); !bytes.Equal(b[:4], []byte{1, 0, 1, 1}) || b[4] != 6 || string(b[5:13]) != "T2      " {
		t.Errorf("slot 06: %v %q", b[:5], b[5:13])
	}
	w = do(r, "GET", "/api/tracks?bin=1&slot=50", nil)
	if b = w.Body.Bytes(); !bytes.Equal(b[:4], []byte{0, 0, 1, 0}) {
		t.Errorf("slot 50: %v", b[:4])
	}
	do(r, "POST", "/api/track/50", s) // no name, no user: the game sees placeholders
	w = do(r, "GET", "/api/tracks?bin=1&slot=50", nil)
	if b = w.Body.Bytes(); string(b[5:13]) != "UNNAMED " || string(b[13:21]) != "UNKNOWN " {
		t.Errorf("placeholders: %q %q", b[5:13], b[13:21])
	}
	if w := do(r, "GET", "/api/tracks?bin=1&slot=abc", nil); w.Code != 404 {
		t.Errorf("slot abc: %d", w.Code)
	}
}

// TestMigrate opens a database created by the phase-1 schema (no name
// columns) and expects the columns to be added and old rows to list.
func TestMigrate(t *testing.T) {
	path := filepath.Join(t.TempDir(), "old.sqlite3")
	db, err := sqlx.Connect("sqlite3", path)
	if err != nil {
		t.Fatal(err)
	}
	old := `CREATE TABLE track (id INTEGER PRIMARY KEY AUTOINCREMENT, slot INTEGER NOT NULL DEFAULT 0,
	        version INTEGER NOT NULL DEFAULT 1, data BLOB NOT NULL DEFAULT X'', remote TEXT NOT NULL DEFAULT '',
	        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP);
	        CREATE UNIQUE INDEX IDX_track_slot_version ON track (slot, version);`
	if _, err := db.Exec(old); err != nil {
		t.Fatal(err)
	}
	s := sample(t)
	if _, err := db.Exec(`INSERT INTO track (slot, version, data) VALUES (9, 1, ?)`, s); err != nil {
		t.Fatal(err)
	}
	db.Close()

	for i := 0; i < 2; i++ { // the second open must be a no-op
		store, err := OpenStore(path, "schema.sql")
		if err != nil {
			t.Fatalf("open %d: %s", i, err)
		}
		gin.SetMode(gin.TestMode)
		r := NewRouter(store)
		w := do(r, "GET", "/api/tracks", nil)
		var slots []slotInfo
		if err := json.Unmarshal(w.Body.Bytes(), &slots); err != nil {
			t.Fatal(err)
		}
		wantName, wantUser := "", ""
		if i == 1 { // the first pass already posted a named version
			wantName, wantUser = "NEW", "ME"
		}
		if len(slots) != 1 || slots[0].SlotName != "09" || slots[0].Name != wantName || slots[0].User != wantUser {
			t.Fatalf("after migrate (pass %d): %+v", i, slots)
		}
		if w := do(r, "POST", "/api/track/09?name=new&user=me", s); w.Code != 200 {
			t.Fatalf("post after migrate: %d %s", w.Code, w.Body.String())
		}
		row, err := store.Latest(9)
		if err != nil || row.Name != "NEW" || row.User != "ME" || row.Version != 2+i {
			t.Fatalf("latest after migrate: %+v %v", row, err)
		}
		store.db.Close()
	}
}
