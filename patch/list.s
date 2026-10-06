; list.s -- the LOAD screen: pages of ten slots from the server, each with
; its track name and owner, rendered straight out of the mailbox reply window.
;
;   row 4  LOAD TRACK   PAGE p OF n
;   rows 6-24 (even)  "* NN NAME---- USER----" from col 4
;   row 26 A LOAD  B BACK  L R PAGE
;
; Server reply (GET /api/tracks?bin=1&page=P, or &slot=NN), 204 bytes:
;   [count][page][pages][total] then 10 x { slot, name[8], user[8], laps, versions, 0 }

        .include "fujinet.inc"
        .include "excite.inc"
        .include "msgs.inc"
        .include "macros.inc"

        .import wait_vbl, ui_keys, ui_list_ram, ui_show_rom, ui_clear, ui_attr_set
        .import rec_start, rec_byte, rec_hdr, rec_copy, rec_fill, rec_end
        .import txt_a2t, txt_dig2
        .import net_open_begin, net_str, net_dig2, net_status, net_read, net_close
        .import s_page, s_slotq
        .export ls_fetch, ls_run

LS_SIZE = 204
LS_REC  = 20

        .segment "CODE"

; ls_fetch -- A = 0: page UI_PAGE, A = 1: slot EB_SLOT. C clear with the 204
; bytes at FN_RPLY and the channel still open (the caller closes it); C set
; with the channel closed and UI_RESULT = the message to show.
.proc ls_fetch
        pha
        lda     #NOPEN_GET
        jsr     net_open_begin
        pla
        bne     slotq
        lda     #<s_page
        ldx     #>s_page
        jsr     net_str
        lda     UI_PAGE
        jsr     net_dig2
        jmp     go
slotq:  lda     #<s_slotq
        ldx     #>s_slotq
        jsr     net_str
        lda     EB_SLOT
        jsr     net_dig2
go:     jsr     fn_run_open
        bne     neterr
        lda     #20
        sta     EB_HOLD
stat:   jsr     net_status      ; performs the GET
        bne     neterr
        lda     FN_RPLY+3
        cmp     #NSTAT_OK
        bne     neterr
        lda     FN_RPLY+1
        bne     have
        lda     FN_RPLY
        cmp     #LS_SIZE
        bcs     have
        dec     EB_HOLD
        beq     bad
        jsr     wait_vbl
        jmp     stat
have:   lda     #LS_SIZE
        ldx     #0
        jsr     net_read
        bne     neterr
        lda     FN_RXLO
        cmp     #LS_SIZE
        bne     bad
        lda     FN_RXHI
        bne     bad
        clc
        rts
bad:    jsr     net_close
        lda     #MSG_BADDATA
        sta     UI_RESULT
        sec
        rts
neterr: sta     EB_LASTERR
        jsr     net_close
        lda     #MSG_NETERR
        sta     UI_RESULT
        sec
        rts
.endproc

        .import fn_run
fn_run_open = fn_run

; ls_run -- the list screen. C clear: EB_SLOT and EB_NAME hold the choice and
; the channel is closed. C set: cancelled (UI_RESULT = 0) or failed
; (UI_RESULT = message).
.proc ls_run
        lda     EB_PAGE
        sta     UI_PAGE
        lda     #0
        sta     UI_CUR
        sta     UI_RESULT
        jsr     ui_clear
        jsr     ui_attr_set
        ldx     #MSG_LS_A
        jsr     ui_show_rom
fetch:  lda     #0
        jsr     ls_fetch
        bcc     :+
        sec
        rts
:       lda     FN_RPLY
        sta     UI_COUNT
        lda     FN_RPLY+1
        sta     UI_PAGE
        lda     FN_RPLY+2
        sta     UI_PAGES
        lda     UI_COUNT
        bne     have
        lda     UI_PAGE         ; an empty later page: the list shrank
        beq     none
        jsr     net_close
        lda     #0
        sta     UI_PAGE
        beq     fetch
none:   jsr     net_close
        lda     #MSG_NOTRACKS
        sta     UI_RESULT
        sec
        rts
have:   lda     UI_CUR
        cmp     UI_COUNT
        bcc     :+
        lda     UI_COUNT
        sec
        sbc     #1
        sta     UI_CUR
:       jsr     ls_pagenum
        lda     #0
        sta     UI_LINE
lines:  jsr     rec_start       ; two lines per vblank
        jsr     ls_line
        inc     UI_LINE
        jsr     ls_line
        inc     UI_LINE
        jsr     rec_end
        jsr     wait_vbl
        jsr     ui_list_ram
        lda     UI_LINE
        cmp     #10
        bcc     lines
        lda     UI_CUR
        sta     UI_PREVCUR
        lda     #$FF
        sta     EB_PREV
        lda     #0
        sta     EB_HOLD
loop:   jsr     wait_vbl
        lda     UI_CUR
        cmp     UI_PREVCUR
        beq     :+
        jsr     ls_marker
:       jsr     ui_keys
        lda     EB_NEW
        and     #$40            ; B
        beq     :+
        jsr     net_close
        lda     #0
        sta     UI_RESULT
        sec
        rts
:       lda     EB_NEW
        and     #$90            ; A or Start
        JNE     choose
        lda     EB_NEW
        and     #$04            ; Down
        beq     :+
        inc     UI_CUR
        lda     UI_CUR
        cmp     UI_COUNT
        bcc     :+
        lda     #0
        sta     UI_CUR
:       lda     EB_NEW
        and     #$08            ; Up
        beq     :+
        dec     UI_CUR
        bpl     :+
        lda     UI_COUNT
        sec
        sbc     #1
        sta     UI_CUR
:       lda     EB_NEW
        and     #$01            ; Right: next page
        beq     :+
        lda     UI_PAGE
        clc
        adc     #1
        cmp     UI_PAGES
        bcs     :+
        sta     UI_PAGE
        jmp     newpage
:       lda     EB_NEW
        and     #$02            ; Left: previous page
        beq     loop
        lda     UI_PAGE
        beq     loop
        dec     UI_PAGE
newpage: jsr    net_close
        lda     #0
        sta     UI_CUR
        jmp     fetch
choose: jsr     ls_recptr       ; UI_PTR -> the chosen record
        ldy     #0
        lda     (UI_PTR),y
        sta     EB_SLOT
        ldy     #1
        ldx     #0
:       lda     (UI_PTR),y
        jsr     txt_a2t
        sta     EB_NAME,x
        iny
        inx
        cpx     #8
        bne     :-
        lda     EB_FLAGS
        ora     #FL_NAMEOK
        sta     EB_FLAGS
        lda     UI_PAGE
        sta     EB_PAGE
        jsr     net_close       ; only now: CLOSE repaints the reply window
        clc
        rts
.endproc

; ls_recptr -- UI_PTR = FN_RPLY + 4 + UI_CUR * 20.
.proc ls_recptr
        lda     UI_CUR
        jmp     ls_ptr_for
.endproc
; ls_ptr_for -- A = record index -> UI_PTR.
.proc ls_ptr_for
        asl     a
        asl     a
        sta     UI_TMP          ; x4
        asl     a
        asl     a               ; x16
        clc
        adc     UI_TMP          ; x20
        clc
        adc     #4
        sta     UI_PTR
        lda     #>FN_RPLY
        sta     UI_PTR+1
        rts
.endproc

; ls_pagenum -- row 4: page number and page count, two digits each.
.proc ls_pagenum
        jsr     rec_start
        lda     #4
        ldx     #20
        ldy     #2
        jsr     rec_hdr
        lda     UI_PAGE
        clc
        adc     #1
        jsr     ls_dig2
        lda     #4
        ldx     #26
        ldy     #2
        jsr     rec_hdr
        lda     UI_PAGES
        jsr     ls_dig2
        jsr     rec_end
        jsr     wait_vbl
        jmp     ui_list_ram
.endproc

; ls_dig2 -- A = 0-99: append two digit tiles (a leading zero shows as a space).
.proc ls_dig2
        jsr     txt_dig2
        pha
        txa
        bne     :+
        lda     #T_SPACE
:       jsr     rec_byte
        pla
        jmp     rec_byte
.endproc

; ls_line -- append the record for list line UI_LINE: 22 cells from col 4:
; marker, space, slot, space, name, space, user; a blank line past the count.
.proc ls_line
        lda     UI_LINE
        cmp     UI_COUNT
        bcs     blank
        lda     UI_LINE
        asl     a
        clc
        adc     #6
        ldx     #4
        ldy     #22
        jsr     rec_hdr
        lda     UI_LINE
        cmp     UI_CUR
        bne     nomark
        lda     #T_CURSOR
        bne     :+
nomark: lda     #T_SPACE
:       jsr     rec_byte
        lda     #T_SPACE
        jsr     rec_byte
        lda     UI_LINE
        jsr     ls_ptr_for
        ldy     #0
        lda     (UI_PTR),y
        jsr     txt_dig2
        pha
        txa
        jsr     rec_byte
        pla
        jsr     rec_byte
        lda     #T_SPACE
        jsr     rec_byte
        ldy     #1
name:   lda     (UI_PTR),y
        jsr     txt_a2t
        jsr     rec_byte
        iny
        cpy     #9
        bne     name
        lda     #T_SPACE
        jsr     rec_byte
user:   lda     (UI_PTR),y
        jsr     txt_a2t
        jsr     rec_byte
        iny
        cpy     #17
        bne     user
        rts
blank:  lda     UI_LINE
        asl     a
        clc
        adc     #6
        ldx     #4
        ldy     #$40|22
        jsr     rec_hdr
        lda     #T_SPACE
        jmp     rec_byte
.endproc

; ls_marker -- in vblank: move the star from UI_PREVCUR to UI_CUR.
.proc ls_marker
        jsr     rec_start
        lda     UI_PREVCUR
        asl     a
        clc
        adc     #6
        ldx     #4
        ldy     #1
        jsr     rec_hdr
        lda     #T_SPACE
        jsr     rec_byte
        lda     UI_CUR
        asl     a
        clc
        adc     #6
        ldx     #4
        ldy     #1
        jsr     rec_hdr
        lda     #T_CURSOR
        jsr     rec_byte
        jsr     rec_end
        jsr     ui_list_ram
        lda     UI_CUR
        sta     UI_PREVCUR
        rts
.endproc
