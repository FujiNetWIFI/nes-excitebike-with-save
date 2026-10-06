; fujimbx.s -- the 6502 side of the FujiNet cartridge mailbox.
;
; Copied from fujinet-firmware pico/nes/testrom/fujilib.s with the zero page
; relocated (fujinet.inc) and two streaming helpers added. A register write
; is ONE store: `sta FN_RSEL,x` with the register in X and the value in A.

        .include "fujinet.inc"

        .export fn_chk, fn_beg, fn_pb, fn_pw, fn_go, fn_ack, fn_run
        .export fn_txmem, fn_txstr

        .segment "CODE"

; fn_rw -- register X = A.
.proc fn_rw
        sta     FN_RSEL,x
        rts
.endproc

; fn_chk -- Z set if a FujiNet cartridge is answering ('F','N' magic).
.proc fn_chk
        lda     FN_MAG0
        cmp     #'F'
        bne     done
        lda     FN_MAG1
        cmp     #'N'
done:   rts
.endproc

; fn_beg -- begin the transaction described by FN_DEV / FN_CMD / FN_NPR.
; Rewinds the TX stream last, so parameters may be appended at once.
.proc fn_beg
        lda     #16             ; ~8-11 s: longer than the cart's own 5 s budget
        sta     FN_TMO          ;   so a real timeout surfaces as ITS error
        lda     FN_DEV
        ldx     #FR_DEV
        jsr     fn_rw
        lda     FN_CMD
        ldx     #FR_CMD
        jsr     fn_rw
        lda     FN_NPR
        ldx     #FR_NPAR
        jsr     fn_rw
        lda     #0
        ldx     #FR_DRST
        jmp     fn_rw
.endproc

; fn_pb -- append a one-byte parameter with value A.
.proc fn_pb
        pha
        lda     #1
        sta     FN_TX
        pla
        sta     FN_TX
        rts
.endproc

; fn_pw -- append a two-byte little-endian parameter. A = low, X = high.
.proc fn_pw
        pha
        lda     #2
        sta     FN_TX
        pla
        sta     FN_TX
        txa
        sta     FN_TX
        rts
.endproc

; fn_txmem -- append X bytes (0 = 256) from (FN_PTR) to the TX stream.
.proc fn_txmem
        ldy     #0
loop:   lda     (FN_PTR),y
        sta     FN_TX
        iny
        dex
        bne     loop
        rts
.endproc

; fn_txstr -- append the NUL-terminated string at (FN_PTR), without the NUL.
.proc fn_txstr
        ldy     #0
loop:   lda     (FN_PTR),y
        beq     done
        sta     FN_TX
        iny
        bne     loop
done:   rts
.endproc

; fn_go -- commit and wait. Returns A = FNE* (0 = the transaction completed).
;
; The next sequence number comes from the CART'S OWN persisted ACKSEQ + 1,
; never from a counter in RAM: a console RESET restarts the game but does not
; reset the cartridge.
.proc fn_go
        lda     FN_ACKS
        clc
        adc     #1
        bne     have
        lda     #1              ; 0 is reserved as "never used"
have:   sta     FN_SEQ
        ldx     #FR_SEQ
        jsr     fn_rw           ; launching it is this single store
        lda     FN_TMO
        sta     FN_CNT
outer:  ldy     #0
mid:    ldx     #0
        ; ACKSEQ is published LAST, after the whole reply is in place.
inner:  lda     FN_ACKS
        cmp     FN_SEQ
        beq     got
        dex
        bne     inner
        dey
        bne     mid
        dec     FN_CNT
        bne     outer
        lda     #FNEWAIT
        rts
got:    lda     FN_ERR
        rts
.endproc

; fn_ack -- 0 on success, FNENAK if the FujiNet said no. Call after fn_go
; returned 0.
.proc fn_ack
        lda     FN_RCMD
        cmp     #$06
        beq     ok
        lda     #FNENAK
        rts
ok:     lda     #FNEOK
        rts
.endproc

; fn_run -- fn_go then fn_ack: A = 0 on a completed, acknowledged transaction,
; else the error code (Z clear).
.proc fn_run
        jsr     fn_go
        bne     done
        jsr     fn_ack
done:   rts
.endproc
