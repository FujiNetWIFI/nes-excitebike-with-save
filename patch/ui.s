; ui.s -- screen plumbing shared by the prompt, editor, confirmation and list:
; vblank sync, the pad with edge detection and autorepeat, drawing ROM and RAM
; lists, clearing our rows, and the attribute bytes that make text readable.

        .include "excite.inc"
        .include "msgs.inc"

        .import msg_lo, msg_hi
        .export wait_vbl, ui_keys, ui_list_rom, ui_list_ram, ui_show_rom
        .export ui_clear, ui_attr_set

        .segment "CODE"

; wait_vbl -- return at the start of the next vblank (clears a stale flag first).
.proc wait_vbl
        bit     PPU_STATUS
:       bit     PPU_STATUS
        bpl     :-
        rts
.endproc

; ui_keys -- read pad 1 once per frame. EB_NEW = buttons that went down since
; the last call; a direction held 20 frames repeats every 6.
.proc ui_keys
        jsr     EB_PADS
        lda     EB_PREV
        eor     #$FF
        and     EB_PAD1
        sta     EB_NEW
        lda     EB_PAD1
        sta     EB_PREV
        and     #$0F
        beq     norep
        inc     EB_HOLD
        lda     EB_HOLD
        cmp     #20
        bcc     done
        lda     #14
        sta     EB_HOLD
        lda     EB_PAD1
        and     #$0F
        ora     EB_NEW
        sta     EB_NEW
        rts
norep:  lda     #0
        sta     EB_HOLD
done:   rts
.endproc

; ui_list_rom -- X = list id: draw it now (caller is in vblank).
.proc ui_list_rom
        lda     msg_lo,x
        sta     UI_PTR
        lda     msg_hi,x
        jmp     EB_DRAWLIST
.endproc

; ui_list_ram -- draw the list built in UI_REC now (caller is in vblank).
.proc ui_list_ram
        lda     #<UI_REC
        sta     UI_PTR
        lda     #>UI_REC
        jmp     EB_DRAWLIST
.endproc

; ui_show_rom -- X = list id: wait for vblank, then draw it.
.proc ui_show_rom
        stx     UI_TMP
        jsr     wait_vbl
        ldx     UI_TMP
        jmp     ui_list_rom
.endproc

; ui_clear -- blank rows 4-27, three rows per vblank.
.proc ui_clear
        ldx     #MSG_CLR0
loop:   stx     UI_TMP
        jsr     wait_vbl
        ldx     UI_TMP
        jsr     ui_list_rom
        ldx     UI_TMP
        inx
        cpx     #MSG_CLR0+8
        bne     loop
        rts
.endproc

; ui_attr_set -- rows 4-27 -> palette 3 (the game clears attributes to 0,
; which would draw our text light blue in white boxes).
.proc ui_attr_set
        ldx     #MSG_ATTR
        jmp     ui_show_rom
.endproc
