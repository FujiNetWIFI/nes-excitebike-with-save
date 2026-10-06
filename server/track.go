package main

import (
	"bytes"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

// TrackSize is what Excitebike writes to tape: the 64-byte header block from
// zero page $60 followed by the 256-byte track block from $05E0.
const TrackSize = 320

// NameLen bounds track names and usernames: eight cells of the game's font
// (A-Z, 0-9, space), which is what fits on one line of the LOAD list.
const NameLen = 8

// The binary slot list the game reads: a 4-byte header and ten fixed
// records, always 204 bytes so the NES can read it in one fixed-size READ.
const (
	PageSize = 10
	RecSize  = 20
	BinSize  = 4 + PageSize*RecSize
)

const (
	hdrSize   = 64
	trackOff  = 64 // laps byte, then the piece codes
	pieceEnd  = 0x00
	pieceFlat = 0x40 // followed by a run length
	pieceFin  = 0x09 // finish line, ends a lap
)

// signature is what the game stores at header bytes 1-4 and checks on load.
var signature = []byte{0x17, 0x01, 0x00, 0x01}

// pieceLetter maps a piece code to the letter the editor's selector shows
// for it (A-S); the two remaining selector slots are END (00) and finish (09).
var pieceLetter = map[byte]byte{
	0x08: 'A', 0x07: 'B', 0x05: 'C', 0x01: 'D', 0x0B: 'E', 0x06: 'F', 0x0A: 'G',
	0x0E: 'H', 0x03: 'I', 0x04: 'J', 0x0C: 'K', 0x0D: 'L', 0x0F: 'M', 0x10: 'N',
	0x12: 'O', 0x13: 'P', 0x11: 'Q', 0x15: 'R', 0x14: 'S',
}

// Validate accepts exactly what the patched game uploads: 320 bytes whose
// header is the canonical one the game builds (zeroed zero page, signature,
// six bytes of best times, zeros). Anything else is refused so every blob
// in the repository loads back into the game.
func Validate(b []byte) error {
	if len(b) != TrackSize {
		return fmt.Errorf("need exactly %d bytes, got %d", TrackSize, len(b))
	}
	if !bytes.Equal(b[1:5], signature) {
		return errors.New("header bytes 1-4 are not the Excitebike signature")
	}
	if b[0] != 0 {
		return errors.New("header byte 0 must be 0")
	}
	for i := 11; i < hdrSize; i++ {
		if b[i] != 0 {
			return fmt.Errorf("header byte %d must be 0", i)
		}
	}
	return nil
}

// cleanField folds a name to what the game's font and editor can show:
// uppercase letters, digits and (for track names) spaces, at most NameLen.
func cleanField(s string, allowSpace bool) string {
	var b strings.Builder
	for _, r := range strings.ToUpper(s) {
		switch {
		case r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == ' ' && allowSpace:
			b.WriteRune(r)
		}
	}
	out := strings.TrimSpace(b.String())
	if len(out) > NameLen {
		out = strings.TrimSpace(out[:NameLen])
	}
	return out
}

// CleanName normalises a track name; empty is allowed (older ROMs send none).
func CleanName(s string) string { return cleanField(s, true) }

// CleanUser normalises a player name the way the lobby does: 2-8 letters or
// digits, no spaces; anything shorter is treated as no name.
func CleanUser(s string) string {
	u := cleanField(s, false)
	if len(u) < 2 {
		return ""
	}
	return u
}

// Summary describes a track for humans: lap count, column count and a
// one-line strip of the pieces ('_' flat, '|' finish, letters as the editor
// labels them; lowercase for pieces flagged to appear only in play mode B).
type Summary struct {
	Laps    int
	Columns int
	Strip   string
	Warn    string
}

func Summarize(b []byte) Summary {
	s := Summary{}
	if len(b) != TrackSize {
		return s
	}
	s.Laps = int(b[trackOff])
	var sb strings.Builder
	finish := false
	for i := trackOff + 1; i < TrackSize; i++ {
		c := b[i]
		if c == pieceEnd {
			break
		}
		if c == pieceFlat && i+1 < TrackSize {
			n := int(b[i+1])
			i++
			s.Columns += n
			if n > 40 {
				sb.WriteString(fmt.Sprintf("_x%d", n))
			} else {
				sb.WriteString(strings.Repeat("_", n))
			}
			continue
		}
		if c == pieceFin {
			finish = true
			sb.WriteByte('|')
			s.Columns++
			continue
		}
		l, ok := pieceLetter[c&0x7F]
		if !ok {
			l = '?'
		} else if c&0x80 != 0 {
			l += 'a' - 'A'
		}
		sb.WriteByte(l)
		s.Columns++
	}
	s.Strip = sb.String()
	if s.Laps < 1 || s.Laps > 9 {
		s.Warn = "laps not 1-9"
	} else if !finish {
		s.Warn = "no finish line"
	}
	return s
}

// ParseSlot accepts "7" or "07" (0-99) and returns the slot number.
func ParseSlot(s string) (int, error) {
	if len(s) == 0 || len(s) > 2 {
		return 0, errors.New("slot is 1-2 digits")
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 0 || n > 99 || strings.ContainsAny(s, "+-") {
		return 0, errors.New("slot is 00-99")
	}
	return n, nil
}

func SlotName(n int) string { return fmt.Sprintf("%02d", n) }

// BinPage encodes page `page` of the slot summary for the game.
func BinPage(infos []slotInfo, page int) []byte {
	total := len(infos)
	pages := (total + PageSize - 1) / PageSize
	if pages < 1 {
		pages = 1
	}
	if page >= pages {
		page = pages - 1
	}
	if page < 0 {
		page = 0
	}
	out := make([]byte, BinSize)
	out[1] = byte(page)
	out[2] = byte(pages)
	out[3] = byte(total)
	n := 0
	for i := page * PageSize; i < total && n < PageSize; i++ {
		putRec(out[4+n*RecSize:], infos[i])
		n++
	}
	out[0] = byte(n)
	return out
}

// BinSlot encodes the one-record page for a single slot (count 0 if empty).
func BinSlot(infos []slotInfo, slot int) []byte {
	one := []slotInfo{}
	for _, s := range infos {
		if s.SlotNum == slot {
			one = append(one, s)
		}
	}
	return BinPage(one, 0)
}

// Placeholders the game shows for tracks saved without a name or an owner
// (first-version saves, plain curl uploads).
const (
	UnnamedTrack = "UNNAMED"
	UnknownUser  = "UNKNOWN"
)

func putRec(b []byte, s slotInfo) {
	b[0] = byte(s.SlotNum)
	name, user := s.Name, s.User
	if name == "" {
		name = UnnamedTrack
	}
	if user == "" {
		user = UnknownUser
	}
	padField(b[1:9], name)
	padField(b[9:17], user)
	b[17] = byte(s.Laps)
	v := s.Versions
	if v > 255 {
		v = 255
	}
	b[18] = byte(v)
	b[19] = 0
}

func padField(b []byte, s string) {
	for i := range b {
		if i < len(s) {
			b[i] = s[i]
		} else {
			b[i] = ' '
		}
	}
}
