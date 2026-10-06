; text.s -- the font codec and the draw-record builder.
;
; Names live in RAM as font tiles ($00-$09 digits, $0A-$23 letters, $FC
; space) so drawing is a plain copy; they become ASCII only on the wire.

        .include "excite.inc"

        .export txt_a2t, txt_t2a, txt_fieldlen, txt_dig2, txt_next, txt_prev
        .export rec_start, rec_byte, rec_hdr, rec_copy, rec_fill, rec_end

        .segment "CODE"

; txt_a2t -- A = ASCII -> tile. Lowercase folds to upper; anything else is a space.
.proc txt_a2t
        cmp     #'0'
        bcc     space
        cmp     #'9'+1
        bcc     digit
        cmp     #'A'
        bcc     space
        cmp     #'Z'+1
        bcc     upper
        cmp     #'a'
        bcc     space
        cmp     #'z'+1
        bcs     space
        sec
        sbc     #'a'-'A'
upper:  sec
        sbc     #'A'-$0A
        rts
digit:  sec
        sbc     #'0'
        rts
space:  lda     #T_SPACE
        rts
.endproc

; txt_t2a -- A = tile -> ASCII (space for anything that is not a glyph).
.proc txt_t2a
        cmp     #10
        bcs     :+
        clc
        adc     #'0'
        rts
:       cmp     #$24
        bcs     space
        clc
        adc     #'A'-$0A
        rts
space:  lda     #' '
        rts
.endproc

; txt_fieldlen -- (UI_PTR) -> 8 tiles; A = index of the last non-space + 1 (0-8).
.proc txt_fieldlen
        ldy     #7
:       lda     (UI_PTR),y
        cmp     #T_SPACE
        bne     found
        dey
        bpl     :-
        lda     #0
        rts
found:  iny
        tya
        rts
.endproc

; txt_dig2 -- A = 0-99 -> X = tens tile, A = ones tile.
.proc txt_dig2
        ldx     #0
loop:   cmp     #10
        bcc     done
        sbc     #10
        inx
        bne     loop
done:   rts
.endproc

; The editor's glyph cycle: index 0 = space, 1-26 = A-Z, 27-36 = 0-9.
.proc txt_idx                   ; A = tile -> A = index
        cmp     #T_SPACE
        bne     :+
        lda     #0
        rts
:       cmp     #$0A
        bcc     digit
        sec
        sbc     #9
        rts
digit:  clc
        adc     #27
        rts
.endproc
.proc txt_tile                  ; A = index -> tile
        cmp     #0
        bne     :+
        lda     #T_SPACE
        rts
:       cmp     #27
        bcs     digit
        clc
        adc     #9
        rts
digit:  sec
        sbc     #27
        rts
.endproc

; txt_next / txt_prev -- A = tile, X = lowest allowed index (0, or 1 to
; forbid the space) -> A = the next / previous tile in the cycle.
.proc txt_next
        stx     UI_TMP
        jsr     txt_idx
        clc
        adc     #1
        cmp     #37
        bcc     :+
        lda     UI_TMP
:       jmp     txt_tile
.endproc
.proc txt_prev
        stx     UI_TMP
        jsr     txt_idx
        cmp     UI_TMP
        beq     wrap
        bcc     wrap
        sec
        sbc     #1
        jmp     txt_tile
wrap:   lda     #36
        jmp     txt_tile
.endproc

; ---- draw records, built in UI_REC outside vblank and drawn with one call ----

.proc rec_start
        lda     #0
        sta     UI_RI
        rts
.endproc

; rec_byte -- append A (clobbers X, keeps A and Y).
.proc rec_byte
        ldx     UI_RI
        sta     UI_REC,x
        inc     UI_RI
        rts
.endproc

; rec_hdr -- A = row, X = col, Y = len byte: append a record header.
.proc rec_hdr
        pha
        sty     UI_LEN
        stx     UI_COL
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #$20
        jsr     rec_byte        ; ppu hi
        pla
        and     #7
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     UI_COL
        jsr     rec_byte        ; ppu lo
        lda     UI_LEN
        jmp     rec_byte
.endproc

; rec_copy -- append X tiles from (UI_PTR).
.proc rec_copy
        stx     UI_CNT
        ldy     #0
loop:   lda     (UI_PTR),y
        ldx     UI_RI
        sta     UI_REC,x
        inc     UI_RI
        iny
        dec     UI_CNT
        bne     loop
        rts
.endproc

; rec_fill -- append X copies of tile A.
.proc rec_fill
        stx     UI_CNT
loop:   ldx     UI_RI
        sta     UI_REC,x
        inc     UI_RI
        dec     UI_CNT
        bne     loop
        rts
.endproc

; rec_end -- terminate the list.
.proc rec_end
        lda     #0
        jmp     rec_byte
.endproc
