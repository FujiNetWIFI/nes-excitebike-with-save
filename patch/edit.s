; edit.s -- the name editor shown by SAVE: a NAME field and a USER field of
; eight cells each. Left/Right move the cursor (across both fields), Up/Down
; cycle the glyph under it, A or Start accept, B goes back to the slot picker.
;
;   row 4  SAVE SLOT nn        row 8  NAME  [........]   row 9  marker row
;   row 12 USER  [........]    row 13 marker row          row 16 hint
;   rows 20/22/24 key hints

        .include "excite.inc"
        .include "msgs.inc"

        .import wait_vbl, ui_keys, ui_list_ram, ui_show_rom, ui_clear, ui_attr_set
        .import rec_start, rec_byte, rec_hdr, rec_copy, rec_fill, rec_end
        .import txt_next, txt_prev, txt_fieldlen, txt_dig2, ak_load_user
        .export ed_run

        .segment "CODE"

; ed_run -- returns C clear with EB_NAME / EB_USER accepted, C set on B.
.proc ed_run
        lda     EB_FLAGS
        and     #FL_NAMEOK
        bne     named
        ldx     #7              ; first use since power-on: an empty name
        lda     #T_SPACE
:       sta     EB_NAME,x
        dex
        bpl     :-
        lda     EB_FLAGS
        ora     #FL_NAMEOK
        sta     EB_FLAGS
named:  jsr     ak_load_user
        jsr     ui_clear
        jsr     ui_attr_set
        ldx     #MSG_ED_A
        jsr     ui_show_rom
        ldx     #MSG_ED_B
        jsr     ui_show_rom
        jsr     rec_start       ; the slot this name is for, in the title
        lda     #4
        ldx     #19
        ldy     #2
        jsr     rec_hdr
        lda     EB_SLOT
        jsr     txt_dig2
        pha
        txa
        jsr     rec_byte
        pla
        jsr     rec_byte
        jsr     rec_end
        jsr     wait_vbl
        jsr     ui_list_ram
        lda     #0
        sta     UI_FIELD
        sta     UI_POS
        sta     UI_HINT
        sta     EB_HOLD
        lda     #$FF
        sta     EB_PREV         ; whatever is held now does not count
loop:   jsr     ed_build
        jsr     wait_vbl
        jsr     ui_list_ram
        jsr     ui_keys
        lda     EB_NEW
        beq     loop
        lda     UI_HINT         ; any key takes the hint away
        beq     nohint
        lda     #0
        sta     UI_HINT
        ldx     #MSG_HINTCLR
        jsr     ui_show_rom
nohint: lda     EB_NEW
        and     #$40            ; B
        beq     :+
        sec
        rts
:       lda     EB_NEW
        and     #$90            ; A or Start
        beq     move
        jsr     ed_valid
        bcs     loop
        clc
        rts
move:   lda     EB_NEW
        and     #$01            ; Right
        beq     :+
        inc     UI_POS
        lda     UI_POS
        cmp     #8
        bcc     :+
        lda     #0
        sta     UI_POS
        lda     UI_FIELD
        eor     #1
        sta     UI_FIELD
:       lda     EB_NEW
        and     #$02            ; Left
        beq     :+
        dec     UI_POS
        bpl     :+
        lda     #7
        sta     UI_POS
        lda     UI_FIELD
        eor     #1
        sta     UI_FIELD
:       lda     EB_NEW
        and     #$08            ; Up: next glyph
        beq     :+
        jsr     ed_cell
        jsr     txt_next
        jsr     ed_store
:       lda     EB_NEW
        and     #$04            ; Down: previous glyph
        beq     :+
        jsr     ed_cell
        jsr     txt_prev
        jsr     ed_store
:       jmp     loop
.endproc

; ed_cell -- A = tile under the cursor, X = lowest glyph index for this field.
.proc ed_cell
        ldx     UI_POS
        lda     UI_FIELD
        bne     user
        lda     EB_NAME,x
        ldx     #0
        rts
user:   lda     EB_USER,x
        ldx     #1              ; no spaces in a username
        rts
.endproc

; ed_store -- A = tile -> the cell under the cursor.
.proc ed_store
        ldx     UI_POS
        ldy     UI_FIELD
        bne     user
        sta     EB_NAME,x
        rts
user:   sta     EB_USER,x
        lda     EB_FLAGS
        ora     #FL_USEREDIT
        sta     EB_FLAGS
        rts
.endproc

; ed_build -- UI_REC = both fields and both marker rows (about 32 tiles).
.proc ed_build
        jsr     rec_start
        lda     #8
        ldx     #12
        ldy     #8
        jsr     rec_hdr
        lda     #<EB_NAME
        sta     UI_PTR
        lda     #>EB_NAME
        sta     UI_PTR+1
        ldx     #8
        jsr     rec_copy
        lda     #9
        ldx     #12
        ldy     #8
        jsr     rec_hdr
        ldx     #0
        jsr     ed_marker
        lda     #12
        ldx     #12
        ldy     #8
        jsr     rec_hdr
        lda     #<EB_USER
        sta     UI_PTR
        lda     #>EB_USER
        sta     UI_PTR+1
        ldx     #8
        jsr     rec_copy
        lda     #13
        ldx     #12
        ldy     #8
        jsr     rec_hdr
        ldx     #1
        jsr     ed_marker
        jmp     rec_end
.endproc

; ed_marker -- X = field: 8 tiles, the cursor under this field's active cell.
.proc ed_marker
        cpx     UI_FIELD
        beq     active
        lda     #T_SPACE
        ldx     #8
        jmp     rec_fill
active: ldy     #0
loop:   tya
        cmp     UI_POS
        bne     space
        lda     #T_CURSOR
        bne     put
space:  lda     #T_SPACE
put:    ldx     UI_RI
        sta     UI_REC,x
        inc     UI_RI
        iny
        cpy     #8
        bne     loop
        rts
.endproc

; ed_valid -- C clear if the name has a glyph and the user is 2-8 glyphs with
; no gap; otherwise show the matching hint and return C set.
.proc ed_valid
        lda     #<EB_NAME
        sta     UI_PTR
        lda     #>EB_NAME
        sta     UI_PTR+1
        jsr     txt_fieldlen
        bne     nameok
        ldx     #MSG_HINT_NAME
        bne     hint
nameok: lda     #<EB_USER
        sta     UI_PTR
        lda     #>EB_USER
        sta     UI_PTR+1
        jsr     txt_fieldlen
        cmp     #2
        bcc     baduser
        tay
        dey
:       lda     EB_USER,y
        cmp     #T_SPACE
        beq     baduser
        dey
        bpl     :-
        clc
        rts
baduser: ldx    #MSG_HINT_USER
hint:   jsr     ui_show_rom
        lda     #1
        sta     UI_HINT
        sec
        rts
.endproc
