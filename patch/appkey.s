; appkey.s -- the username lives in the FujiNet's shared "player name" app key
; (creator $0001, app $01, key $00: the one the lobby and its games use), so it
; survives power cycles and is the same name everywhere.

        .include "fujinet.inc"
        .include "excite.inc"

        .import fn_beg, fn_run, txt_a2t, txt_t2a, txt_fieldlen
        .export ak_load_user, ak_save_user

        .segment "CODE"

; ak_begin -- A = app key command: start a FUJI transaction with no parameters.
.proc ak_begin
        sta     FN_CMD
        lda     #FNDEVFUJI
        sta     FN_DEV
        lda     #0
        sta     FN_NPR
        jmp     fn_beg
.endproc

; ak_open -- A = mode (0 read, 1 write): OPEN_APPKEY for the shared player name.
.proc ak_open
        sta     UI_TMP
        lda     #FNCAKOPEN
        jsr     ak_begin
        lda     #$01            ; creator $0001, little-endian
        sta     FN_TX
        lda     #$00
        sta     FN_TX
        lda     #$01            ; app
        sta     FN_TX
        lda     #$00            ; key
        sta     FN_TX
        lda     UI_TMP          ; mode
        sta     FN_TX
        lda     #$00            ; reserved
        sta     FN_TX
        jmp     fn_run
.endproc

; ak_close -- CLOSE_APPKEY, result ignored.
.proc ak_close
        lda     #FNCAKCLOSE
        jsr     ak_begin
        jmp     fn_run
.endproc

; ak_blank -- EB_USER = 8 spaces.
.proc ak_blank
        ldx     #7
        lda     #T_SPACE
:       sta     EB_USER,x
        dex
        bpl     :-
        rts
.endproc

; ak_valid -- A = ASCII: C clear if it is a letter or digit.
.proc ak_valid
        cmp     #'0'
        bcc     bad
        cmp     #'9'+1
        bcc     ok
        cmp     #'A'
        bcc     bad
        cmp     #'Z'+1
        bcc     ok
        cmp     #'a'
        bcc     bad
        cmp     #'z'+1
        bcc     ok
bad:    sec
        rts
ok:     clc
        rts
.endproc

; ak_load_user -- once per power-on: read the key into EB_USER (as tiles) if
; it holds 2-8 letters/digits; otherwise leave the field blank for the editor.
; A cartridge that answers but has no SD just leaves the flag clear, so the
; read is tried again next time.
.proc ak_load_user
        lda     EB_FLAGS
        and     #FL_KEYREAD
        bne     done
        jsr     ak_blank
        lda     #0
        jsr     ak_open
        bne     done
        lda     #FNCAKREAD
        jsr     ak_begin
        jsr     fn_run
        bne     close
        lda     FN_RPLY+1       ; length high byte
        bne     close
        lda     FN_RPLY         ; length 2-8?
        cmp     #2
        bcc     close
        cmp     #9
        bcs     close
        sta     UI_CNT
        ldy     #0
copy:   lda     FN_RPLY+2,y
        jsr     ak_valid
        bcs     blank
        jsr     txt_a2t
        sta     EB_USER,y
        iny
        cpy     UI_CNT
        bne     copy
        beq     close
blank:  jsr     ak_blank
close:  jsr     ak_close
        lda     EB_FLAGS
        ora     #FL_KEYREAD
        sta     EB_FLAGS
done:   rts
.endproc

; ak_save_user -- write EB_USER (validated: 2-8 glyphs, no spaces) to the key.
; Failure is not fatal: the RAM copy stays and the write is retried next SAVE.
.proc ak_save_user
        lda     #1
        jsr     ak_open
        bne     done
        lda     #FNCAKWRITE
        jsr     ak_begin
        lda     #<EB_USER
        sta     UI_PTR
        lda     #>EB_USER
        sta     UI_PTR+1
        jsr     txt_fieldlen
        sta     UI_CNT
        ldy     #0
loop:   lda     EB_USER,y
        jsr     txt_t2a
        sta     FN_TX
        iny
        cpy     UI_CNT
        bne     loop
        jsr     fn_run
        bne     done
        jsr     ak_close
        lda     EB_FLAGS
        and     #<~FL_USEREDIT
        sta     EB_FLAGS
done:   rts
.endproc
