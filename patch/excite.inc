; excite.inc -- Excitebike addresses the patch relies on (all in the original
; $C000-$FFFF bank, unchanged) and the RAM the patch owns.

; Routines in the game we call.
EB_DRAWLIST = $C289             ; $00 = list lo, A = list hi: draw a $D3C1 list
                                ;   now, clear $0300/$0301/$45, reset PPU addr
EB_PADS     = $D347             ; read both pads: $14 = pad 1 held bits
EB_COPYTRK  = $C621             ; copy master track $06E0-$07DF -> $05E0-$06DF
EB_SIG      = $C17F             ; +1..+4 = header signature 17 01 00 01 (the game indexes it 1-4 too)

; Game variables.
EB_PAD1     = $14               ; A=$80 B=$40 Sel=$20 Start=$10 U=$08 D=$04 L=$02 R=$01
EB_REQ      = $48               ; 1 save, 2 load, $FF done (owned by the caller)
EB_HDR      = $0060             ; 64-byte cassette header block ($61-$64 sig, $65-$6A times)
EB_TRK      = $05E0             ; 256-byte track block (working copy)
EB_BEST_A   = $05A0             ; 3 bytes, best time A (header $65-$67)
EB_BEST_B   = $05C3             ; 3 bytes, best time B (header $68-$6A)

; Our persistent state: console RAM nothing else touches. Survives Reset,
; zero after a cold boot.
EB_SLOT     = $05C6             ; chosen slot 0-99
EB_LASTERR  = $05C7             ; last error code shown
EB_FLAGS    = $05C8             ; FL_* below
EB_PAGE     = $05C9             ; last list page shown
EB_USER     = $05D0             ; username, 8 font tiles
EB_NAME     = $05D8             ; track name, 8 font tiles

FL_KEYREAD  = 1                 ; the username app key has been read
FL_NAMEOK   = 2                 ; EB_NAME holds tiles (not cold-boot zeros)
FL_USEREDIT = 4                 ; the username was edited: app key write pending

; Our zero-page scratch (the tape routines' old area; NMI is off while we run).
UI_PTR      = $00               ; list pointer for EB_DRAWLIST, record source
EB_T0       = $0B
EB_T1       = $0C
EB_PREV     = $0D               ; previous pad state (edge detection)
EB_NEW      = $0E               ; newly pressed bits this frame
EB_HOLD     = $0F               ; frame counter: autorepeat / result hold

; Scratch in the bottom of the stack page. The game's stack never gets below
; $01E0 and nothing else references page 1; valid only while NMI is off.
UI_FRAME    = $0100
UI_FIELD    = $0101             ; editor: 0 = NAME, 1 = USER
UI_POS      = $0102             ; editor: cell 0-7
UI_CUR      = $0103             ; list: cursor line
UI_COUNT    = $0104             ; list: records on this page
UI_PAGE     = $0105             ; list: page index
UI_PAGES    = $0106             ; list: page count
UI_LINE     = $0107             ; list: line being drawn
UI_RESULT   = $0108             ; message to show after a screen fails (0 = none)
UI_PREVCUR  = $0109             ; list: line the marker is drawn on
UI_TMP      = $010A
UI_HINT     = $010B             ; editor: a hint is on row 16
UI_INFOSLOT = $0109             ; picker: slot the cached owner info is for ($FF none)
UI_INFOCNT  = $0107             ; picker: 0 empty, 1 held, $FF unknown (fetch failed)
UI_SETTLE   = $010B             ; picker: frames since the slot number last changed
UI_RI       = $010C             ; record builder: write index into UI_REC
UI_LEN      = $010D
UI_COL      = $010E
UI_CNT      = $010F
UI_REC      = $0110             ; 64-byte draw-list buffer built outside vblank
UI_ONAME    = $0150             ; owner of the slot being overwritten: name tiles
UI_OUSER    = $0158             ; ... and user tiles

; Hardware.
PPU_STATUS  = $2002
APU_STATUS  = $4015

; Font tiles.
T_SPACE     = $FC
T_APOS      = $F9
T_BANG      = $FA
T_COLON     = $FB
T_SLASH     = $F1
T_CURSOR    = $26               ; a star
