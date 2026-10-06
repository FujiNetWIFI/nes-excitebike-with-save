package main

import (
	_ "embed"
	"errors"
	"html/template"
	"io"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

//go:embed index.html
var indexHTML string

var indexTmpl = template.Must(template.New("index").Parse(indexHTML))

type server struct {
	store *Store
}

// NewRouter wires the API and the index page.
//
//	GET  /api/track/NN                 latest 320 bytes (octet-stream) or 404
//	POST /api/track/NN?name=&user=     store 320 bytes as a new version -> 200 "OK"
//	PUT  /api/track/NN                 same as POST
//	GET  /api/track/NN/versions        JSON list of versions, newest first
//	GET  /api/track/NN/v/V             that version's 320 bytes or 404
//	GET  /api/tracks                   JSON summary of slots in use
//	GET  /api/tracks?bin=1&page=P      204-byte page of the summary for the game
//	GET  /api/tracks?bin=1&slot=NN     204-byte single-slot record (count 0/1)
//	GET  /                             HTML index
//	GET  /healthz                      "ok"
func NewRouter(store *Store) *gin.Engine {
	r := gin.Default()
	s := &server{store: store}
	r.GET("/", s.index)
	r.GET("/healthz", func(c *gin.Context) { c.String(http.StatusOK, "ok") })
	api := r.Group("/api")
	api.GET("/tracks", s.listSlots)
	api.GET("/track/:slot", s.getLatest)
	api.POST("/track/:slot", s.put)
	api.PUT("/track/:slot", s.put)
	api.GET("/track/:slot/versions", s.versions)
	api.GET("/track/:slot/v/:version", s.getVersion)
	return r
}

func slotParam(c *gin.Context) (int, bool) {
	n, err := ParseSlot(c.Param("slot"))
	if err != nil {
		c.String(http.StatusNotFound, "no such slot: %s\n", err)
		return 0, false
	}
	return n, true
}

// sendTrack writes the blob the way an 8-bit client wants it: raw bytes and
// an explicit Content-Length.
func sendTrack(c *gin.Context, row *TrackRow) {
	c.Header("Content-Length", strconv.Itoa(len(row.Data)))
	c.Header("X-Track-Version", strconv.Itoa(row.Version))
	c.Header("X-Track-Name", row.Name)
	c.Header("X-Track-User", row.User)
	c.Header("Last-Modified", row.CreatedAt.UTC().Format(http.TimeFormat))
	c.Data(http.StatusOK, "application/octet-stream", row.Data)
}

func (s *server) getLatest(c *gin.Context) {
	slot, ok := slotParam(c)
	if !ok {
		return
	}
	row, err := s.store.Latest(slot)
	if errors.Is(err, ErrNotFound) {
		c.String(http.StatusNotFound, "slot %s is empty\n", SlotName(slot))
		return
	}
	if err != nil {
		c.String(http.StatusInternalServerError, "%s\n", err)
		return
	}
	sendTrack(c, row)
}

func (s *server) getVersion(c *gin.Context) {
	slot, ok := slotParam(c)
	if !ok {
		return
	}
	v, err := strconv.Atoi(c.Param("version"))
	if err != nil || v < 1 {
		c.String(http.StatusNotFound, "no such version\n")
		return
	}
	row, err := s.store.Version(slot, v)
	if errors.Is(err, ErrNotFound) {
		c.String(http.StatusNotFound, "slot %s has no version %d\n", SlotName(slot), v)
		return
	}
	if err != nil {
		c.String(http.StatusInternalServerError, "%s\n", err)
		return
	}
	sendTrack(c, row)
}

func (s *server) put(c *gin.Context) {
	slot, ok := slotParam(c)
	if !ok {
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, TrackSize+1)
	b, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.String(http.StatusBadRequest, "need exactly %d bytes\n", TrackSize)
		return
	}
	if err := Validate(b); err != nil {
		c.String(http.StatusBadRequest, "%s\n", err)
		return
	}
	name := CleanName(c.Query("name"))
	user := CleanUser(c.Query("user"))
	version, err := s.store.Insert(slot, b, c.ClientIP(), name, user)
	if err != nil {
		c.String(http.StatusInternalServerError, "%s\n", err)
		return
	}
	sum := Summarize(b)
	if sum.Warn != "" {
		log.Printf("slot %s v%d from %s: %s", SlotName(slot), version, c.ClientIP(), sum.Warn)
	}
	c.Header("X-Track-Version", strconv.Itoa(version))
	// A short body (not 204) so the FujiNet's STATUS reports success with
	// bytes available instead of an ambiguous end-of-file.
	c.String(http.StatusOK, "OK")
}

type versionInfo struct {
	Version   int       `json:"version"`
	CreatedAt time.Time `json:"created_at"`
	Name      string    `json:"name"`
	User      string    `json:"user"`
	Laps      int       `json:"laps"`
	Columns   int       `json:"columns"`
}

func (s *server) versions(c *gin.Context) {
	slot, ok := slotParam(c)
	if !ok {
		return
	}
	rows, err := s.store.Versions(slot)
	if err != nil {
		c.String(http.StatusInternalServerError, "%s\n", err)
		return
	}
	out := make([]versionInfo, 0, len(rows))
	for _, r := range rows {
		sum := Summarize(r.Data)
		out = append(out, versionInfo{r.Version, r.CreatedAt, r.Name, r.User, sum.Laps, sum.Columns})
	}
	c.JSON(http.StatusOK, gin.H{"slot": SlotName(slot), "versions": out})
}

type slotInfo struct {
	SlotNum   int       `json:"-"`
	Name      string    `json:"name"`
	User      string    `json:"user"`
	SlotName  string    `json:"slot"`
	Versions  int       `json:"versions"`
	UpdatedAt time.Time `json:"updated_at"`
	Laps      int       `json:"laps"`
	Columns   int       `json:"columns"`
	Strip     string    `json:"strip"`
	Updated   string    `json:"-"`
}

func (s *server) slotInfos() ([]slotInfo, error) {
	slots, err := s.store.Slots()
	if err != nil {
		return nil, err
	}
	out := make([]slotInfo, 0, len(slots))
	for _, sl := range slots {
		sum := Summarize(sl.Data)
		up := sl.Updated()
		out = append(out, slotInfo{
			SlotNum: sl.Slot, SlotName: SlotName(sl.Slot), Name: sl.Name, User: sl.User,
			Versions: sl.Versions, UpdatedAt: up,
			Laps: sum.Laps, Columns: sum.Columns, Strip: sum.Strip,
			Updated: up.UTC().Format("2006-01-02 15:04 UTC"),
		})
	}
	return out, nil
}

func (s *server) listSlots(c *gin.Context) {
	infos, err := s.slotInfos()
	if err != nil {
		c.String(http.StatusInternalServerError, "%s\n", err)
		return
	}
	if c.Query("bin") == "" {
		c.JSON(http.StatusOK, infos)
		return
	}
	var out []byte
	if sq := c.Query("slot"); sq != "" {
		n, err := ParseSlot(sq)
		if err != nil {
			c.String(http.StatusNotFound, "no such slot: %s\n", err)
			return
		}
		out = BinSlot(infos, n)
	} else {
		page, _ := strconv.Atoi(c.DefaultQuery("page", "0"))
		out = BinPage(infos, page)
	}
	c.Header("Content-Length", strconv.Itoa(len(out)))
	c.Data(http.StatusOK, "application/octet-stream", out)
}

func (s *server) index(c *gin.Context) {
	infos, err := s.slotInfos()
	if err != nil {
		c.String(http.StatusInternalServerError, "%s\n", err)
		return
	}
	c.Status(http.StatusOK)
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := indexTmpl.Execute(c.Writer, gin.H{"Slots": infos}); err != nil {
		log.Printf("index: %s", err)
	}
}
