; strings.s -- on-screen text, as $D3C1 draw lists the game itself understands:
; records of [ppu_hi, ppu_lo, len, tiles...] ending in a 0 byte; len bit 6 =
; one tile repeated (fill). The SAVE/LOAD screen is blank when we get it, and
; the design menu redraws itself from scratch when we return, so our screens
; own rows 4-27 (cols 4-27, clear of overscan).

        .include "excite.inc"
        .include "msgs.inc"
        .include "macros.inc"

        .export msg_lo, msg_hi, msg_diglo, msg_digkind
        .export s_by, s_empty, s_noinfo

        .segment "RODATA"

; ---- row 16 / row 20 messages (the game's own SAVING / ERROR rows) ----
m_save_slot:    ROW16 "SAVE SLOT"      ; the picker draws rows 18-20 itself
                REC 22, 10, "A OK  B BACK"
                .byte 0
m_load_slot:    ROW16 "LOAD SLOT"
                ROW20 "A OK  B BACK"
                .byte 0
m_saving:       ROW16 "SAVING"
                BLANK20
                .byte 0
m_loading:      ROW16 "LOADING"
                BLANK20
                .byte 0
m_saved:        ROW16 "SAVED SLOT"
                BLANK20
                .byte 0
m_loaded:       ROW16 "LOADED SLOT"
                BLANK20
                .byte 0
m_nofuji:       ROW16 "NO FUJINET"
                BLANK20
                .byte 0
m_empty:        ROW16 "EMPTY SLOT"
                BLANK20
                .byte 0
m_neterr:       ROW16 "NET ERROR"
                BLANK20
                .byte 0
m_baddata:      ROW16 "BAD DATA"
                BLANK20
                .byte 0
m_blank:        BLANK16
                BLANK20
                .byte 0
m_notracks:     ROW16 "NO TRACKS"
                BLANK20
                .byte 0

; ---- the name editor ----
m_ed_a:         REC 4, 9, "SAVE SLOT"  ; the editor adds the slot digits at col 19
                REC 8, 6, "NAME"
                REC 12, 6, "USER"
                .byte 0
m_ed_b:         REC 20, 6, "UP DOWN  LETTER"
                REC 22, 6, "LEFT RIGHT  MOVE"
                REC 24, 6, "A OK  B BACK"
                .byte 0
m_hint_name:    FILL 16, 6, 20, T_SPACE
                REC 16, 6, "ENTER A NAME"
                .byte 0
m_hint_user:    FILL 16, 6, 20, T_SPACE
                REC 16, 6, "USER 2 TO 8 CHARS"
                .byte 0
m_hintclr:      FILL 16, 6, 20, T_SPACE
                .byte 0

; ---- tile strings the picker copies into its own records ----
s_by:           TXT " BY "
s_empty:        TXT "EMPTY"
s_noinfo:       TXT "NO INFO"

; ---- overwrite confirmation (digits at row 8 col 11, owner on rows 10/12 col 12) ----
m_cf_a:         REC 4, 11, "SAVE TRACK"
                REC 8, 6, "SLOT"
                REC 8, 14, "HAS"
                REC 12, 6, "BY"
                REC 16, 6, "A REPLACE  B BACK"
                .byte 0

; ---- the load list (page digits at row 4 cols 20-21 and 26-27) ----
m_ls_a:         REC 4, 4, "LOAD TRACK"
                REC 4, 15, "PAGE"
                REC 4, 23, "OF"
                REC 26, 4, "A LOAD  B BACK  L R PAGE"
                .byte 0

; ---- attributes: rows 4-27 (attribute rows 1-6) -> palette 3, orange text ----
m_attr:         .byte $23, $C8, $40 | 48, $FF
                .byte 0

; ---- clear rows 4-27, three rows per list (96 tiles: one vblank each) ----
.macro CLR3 r
        FILL r, 0, 32, T_SPACE
        FILL r+1, 0, 32, T_SPACE
        FILL r+2, 0, 32, T_SPACE
        .byte 0
.endmacro
m_clr0:         CLR3 4
m_clr1:         CLR3 7
m_clr2:         CLR3 10
m_clr3:         CLR3 13
m_clr4:         CLR3 16
m_clr5:         CLR3 19
m_clr6:         CLR3 22
m_clr7:         CLR3 25

msg_lo: .lobytes m_save_slot, m_load_slot, m_saving, m_loading, m_saved, m_loaded
        .lobytes m_nofuji, m_empty, m_neterr, m_baddata, m_blank, m_notracks
        .lobytes m_ed_a, m_ed_b, m_hint_name, m_hint_user, m_hintclr, m_cf_a, m_ls_a, m_attr
        .lobytes m_clr0, m_clr1, m_clr2, m_clr3, m_clr4, m_clr5, m_clr6, m_clr7
msg_hi: .hibytes m_save_slot, m_load_slot, m_saving, m_loading, m_saved, m_loaded
        .hibytes m_nofuji, m_empty, m_neterr, m_baddata, m_blank, m_notracks
        .hibytes m_ed_a, m_ed_b, m_hint_name, m_hint_user, m_hintclr, m_cf_a, m_ls_a, m_attr
        .hibytes m_clr0, m_clr1, m_clr2, m_clr3, m_clr4, m_clr5, m_clr6, m_clr7
        .assert * - msg_hi = MSG_COUNT, error, "msg tables out of step with msgs.inc"

; Column of the two variable digits on row 16 (col 10 + text length + 1).
msg_diglo:   .byte 20, 20, 17, 18, 21, 22, 0, 0, 20, 0, 0, 0
             .res MSG_COUNT - 12, 0
msg_digkind: .byte DIG_NONE, DIG_SLOT, DIG_SLOTNAME, DIG_SLOTNAME, DIG_SLOTNAME, DIG_SLOTNAME
             .byte DIG_NONE, DIG_NONE, DIG_HEX, DIG_NONE, DIG_NONE, DIG_NONE
             .res MSG_COUNT - 12, DIG_NONE
