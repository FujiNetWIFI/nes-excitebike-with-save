; net.s -- N: network device calls over the mailbox, one transaction each.
;
; Every routine returns A = 0 on success (Z set) or an error code: the cart's
; FN_ERR (1-4), FNENAK ($EE) when the FujiNet refused, FNEWAIT ($FF) when the
; cart never answered. Replies are left in the reply window at FN_RPLY.
;
; URLs are streamed straight into the TX page: url_base ("N:http://host/api/")
; from the build, then the pieces below. Names travel in the query string,
; with '+' for space (the FujiNet strips spaces from a devicespec).

        .include "fujinet.inc"
        .include "excite.inc"
        .include "config.inc"

        .import fn_beg, fn_pb, fn_pw, fn_run, fn_txmem, fn_txstr
        .import txt_dig2, txt_t2a, txt_fieldlen
        .export net_open, net_open_post, net_open_begin, net_str, net_dig2, net_field
        .export net_mode, net_write, net_status, net_read, net_close
        .export s_page, s_slotq

        .segment "RODATA"
url_base: .byte SERVER_URL, 0
s_track:  .byte "track/", 0
s_qname:  .byte "?name=", 0
s_quser:  .byte "&user=", 0
s_page:   .byte "tracks?bin=1&page=", 0
s_slotq:  .byte "tracks?bin=1&slot=", 0

        .segment "CODE"

; net_setup -- A = command, X = parameter count; begins the transaction.
.proc net_setup
        sta     FN_CMD
        stx     FN_NPR
        lda     #FNDEVN
        sta     FN_DEV
        jmp     fn_beg
.endproc

; net_str -- A/X = lo/hi of a NUL-terminated ROM string: append it.
.proc net_str
        sta     FN_PTR
        stx     FN_PTR+1
        jmp     fn_txstr
.endproc

; net_dig2 -- A = 0-99: append two ASCII digits.
.proc net_dig2
        jsr     txt_dig2
        pha
        txa
        ora     #'0'
        sta     FN_TX
        pla
        ora     #'0'
        sta     FN_TX
        rts
.endproc

; net_field -- A/X = lo/hi of an 8-tile field: append it as ASCII, trailing
; spaces dropped, inner spaces as '+'.
.proc net_field
        sta     UI_PTR
        stx     UI_PTR+1
        jsr     txt_fieldlen
        sta     UI_CNT
        beq     done
        ldy     #0
loop:   lda     (UI_PTR),y
        jsr     txt_t2a
        cmp     #' '
        bne     put
        lda     #'+'
put:    sta     FN_TX
        iny
        cpy     UI_CNT
        bne     loop
done:   rts
.endproc

; net_open_begin -- A = HTTP open mode: OPEN with p0 mode, p1 translation 0,
; and url_base streamed; the caller appends the rest and calls fn_run.
.proc net_open_begin
        pha
        lda     #FNCNOPEN
        ldx     #2
        jsr     net_setup
        pla
        jsr     fn_pb           ; p0: mode
        lda     #0
        jsr     fn_pb           ; p1: translation none
        lda     #<url_base
        ldx     #>url_base
        jmp     net_str
.endproc

; net_open -- A = mode: open .../api/track/NN (the LOAD GET).
.proc net_open
        jsr     net_open_begin
        lda     #<s_track
        ldx     #>s_track
        jsr     net_str
        lda     EB_SLOT
        jsr     net_dig2
        jmp     fn_run
.endproc

; net_open_post -- open .../api/track/NN?name=...&user=... for the POST.
.proc net_open_post
        lda     #NOPEN_POST
        jsr     net_open_begin
        lda     #<s_track
        ldx     #>s_track
        jsr     net_str
        lda     EB_SLOT
        jsr     net_dig2
        lda     #<s_qname
        ldx     #>s_qname
        jsr     net_str
        lda     #<EB_NAME
        ldx     #>EB_NAME
        jsr     net_field
        lda     #<s_quser
        ldx     #>s_quser
        jsr     net_str
        lda     #<EB_USER
        ldx     #>EB_USER
        jsr     net_field
        jmp     fn_run
.endproc

; net_mode -- A = HTTP channel mode (NHMODE_*).
.proc net_mode
        pha
        lda     #FNCNHMODE
        ldx     #2
        jsr     net_setup
        lda     #0
        jsr     fn_pb           ; p0: unused
        pla
        jsr     fn_pb           ; p1: the mode
        jmp     fn_run
.endproc

; net_write -- A = length (0 = 256), source at (FN_PTR).
; One 16-bit parameter costs 3 TX bytes; 3 + 256 fits the 320-byte stream.
.proc net_write
        sta     EB_T0
        lda     #FNCNWRITE
        ldx     #1
        jsr     net_setup
        ldx     #0
        lda     EB_T0
        bne     short
        inx                     ; 256 = $0100
short:  jsr     fn_pw
        ldx     EB_T0           ; 0 means 256 to fn_txmem as well
        jsr     fn_txmem
        jmp     fn_run
.endproc

; net_status -- reply: FN_RPLY+0/1 avail (LE), +2 connected, +3 error.
; On an HTTP channel the first STATUS performs the request itself.
.proc net_status
        lda     #FNCNSTAT
        ldx     #0
        jsr     net_setup
        jmp     fn_run
.endproc

; net_read -- A/X = length lo/hi; data lands at FN_RPLY, count in FN_RXLO/HI.
.proc net_read
        pha
        txa
        pha
        lda     #FNCNREAD
        ldx     #1
        jsr     net_setup
        pla
        tax
        pla
        jsr     fn_pw
        jmp     fn_run
.endproc

.proc net_close
        lda     #FNCNCLOSE
        ldx     #0
        jsr     net_setup
        jmp     fn_run
.endproc
