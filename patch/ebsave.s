; ebsave.s -- Excitebike's SAVE and LOAD, re-pointed from the Famicom Data
; Recorder to a FujiNet N: device talking HTTP to the track repository.
;
; Both entry points replace a JSR in the game's main loop ($C1EA / $C1F7).
; They run with NMI off -- the game's logic lives in its NMI handler -- on a
; screen the game has just cleared. We draw in vblank with the game's list
; drawer, read the pad with the game's routine, do the transfer, and return;
; the caller sets $48 to $FF, turns NMI back on, and the design menu rebuilds.
;
; SAVE: slot picker (shows what the slot holds) -> name editor titled with the
;       slot -> owner check (confirm if someone else's) -> POST.
; LOAD: list of saved slots -> GET the chosen one.

        .include "fujinet.inc"
        .include "excite.inc"
        .include "msgs.inc"
        .include "macros.inc"

        .import fn_chk
        .import net_open, net_open_post, net_mode, net_write, net_status, net_read, net_close
        .import msg_diglo, msg_digkind, s_by, s_empty, s_noinfo
        .import wait_vbl, ui_keys, ui_list_rom, ui_list_ram, ui_show_rom, ui_clear, ui_attr_set
        .import rec_start, rec_byte, rec_hdr, rec_copy, rec_fill, rec_end
        .import txt_dig2, txt_a2t
        .import ed_run, ak_load_user, ak_save_user, ls_run, ls_fetch
        .export eb_save, eb_load, eb_irq, eb_show, eb_result

        .segment "CODE"

; ---------------------------------------------------------------- helpers

; eb_show -- X = message id. In vblank: draw its ROM list, then what the
; message wants from RAM: the slot digits or the error code on row 16, and
; the track name on row 18.
.proc eb_show
        stx     EB_T1
        jsr     wait_vbl
        ldx     EB_T1
        jsr     ui_list_rom
        ldx     EB_T1
        lda     msg_digkind,x
        beq     done
        jsr     rec_start
        lda     #16
        ldy     #2
        pha
        lda     msg_diglo,x
        tax
        pla
        jsr     rec_hdr
        ldx     EB_T1
        lda     msg_digkind,x
        cmp     #DIG_HEX
        beq     hex
        lda     EB_SLOT
        jsr     txt_dig2
        pha
        txa
        jsr     rec_byte
        pla
        jsr     rec_byte
        ldx     EB_T1
        lda     msg_digkind,x
        cmp     #DIG_SLOTNAME
        bne     draw
        lda     #18
        ldx     #10
        ldy     #8
        jsr     rec_hdr
        lda     #<EB_NAME
        sta     UI_PTR
        lda     #>EB_NAME
        sta     UI_PTR+1
        ldx     #8
        jsr     rec_copy
        jmp     draw
hex:    lda     EB_LASTERR      ; tiles $00-$0F are 0-9, A-F
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     rec_byte
        lda     EB_LASTERR
        and     #$0F
        jsr     rec_byte
draw:   jsr     rec_end
        jsr     ui_list_ram
done:   rts
.endproc

; eb_add -- EB_SLOT = (EB_SLOT + A) mod 100.
.proc eb_add
        clc
        adc     EB_SLOT
        cmp     #100
        bcc     :+
        sbc     #100
:       sta     EB_SLOT
        rts
.endproc

; ---------------------------------------------------------- slot picker
; eb_prompt -- rows 16/18/20/22: SAVE SLOT nn, the track name, what the slot
; holds (fetched once the number has rested for half a second), the key hint.
; Up/Down +-1, Left/Right +-10, held directions repeat; A or Start confirms
; (C clear), B backs out (C set). The caller has cleared the screen.
.proc eb_prompt
        lda     EB_SLOT
        cmp     #100
        bcc     :+
        lda     #0
        sta     EB_SLOT
:       ldx     #MSG_SAVE_SLOT
        jsr     ui_show_rom
        lda     #$FF
        sta     UI_INFOSLOT     ; nothing fetched yet
        sta     EB_PREV         ; whatever is held now does not count
        lda     #0
        sta     EB_HOLD
        sta     UI_SETTLE
        lda     #1
        sta     UI_FRAME        ; dirty: draw the number
loop:   lda     UI_FRAME
        beq     rest
        jsr     pr_draw         ; number, name, blank info row (one vblank)
        lda     #0
        sta     UI_FRAME
        sta     UI_SETTLE
        beq     keys
rest:   jsr     wait_vbl
        lda     UI_SETTLE
        cmp     #30
        bcs     settled
        inc     UI_SETTLE
        bne     keys
settled: lda    UI_INFOSLOT
        cmp     EB_SLOT
        beq     keys
        jsr     pr_info         ; ask the server about this slot, show it
keys:   jsr     ui_keys
        lda     EB_NEW
        and     #$90            ; A or Start
        bne     confirm
        lda     EB_NEW
        and     #$40            ; B
        bne     cancel
        lda     EB_NEW
        and     #$0F
        beq     loop
        lda     EB_NEW
        and     #$08            ; Up
        beq     :+
        lda     #1
        jsr     eb_add
:       lda     EB_NEW
        and     #$04            ; Down
        beq     :+
        lda     #99
        jsr     eb_add
:       lda     EB_NEW
        and     #$01            ; Right
        beq     :+
        lda     #10
        jsr     eb_add
:       lda     EB_NEW
        and     #$02            ; Left
        beq     :+
        lda     #90
        jsr     eb_add
:       lda     #1
        sta     UI_FRAME
        jmp     loop
confirm: clc
        rts
cancel: sec
        rts
.endproc

; pr_draw -- in vblank: the two digits (row 16 col 20), the name (row 18),
; and a blank info row (row 20) so stale info never sits under a new number.
.proc pr_draw
        jsr     rec_start
        lda     #16
        ldx     #20
        ldy     #2
        jsr     rec_hdr
        lda     EB_SLOT
        jsr     txt_dig2
        pha
        txa
        jsr     rec_byte
        pla
        jsr     rec_byte
        lda     #18
        ldx     #10
        ldy     #8
        jsr     rec_hdr
        lda     #<EB_NAME
        sta     UI_PTR
        lda     #>EB_NAME
        sta     UI_PTR+1
        ldx     #8
        jsr     rec_copy
        lda     #20
        ldx     #6
        ldy     #$40|20
        jsr     rec_hdr
        lda     #T_SPACE
        jsr     rec_byte
        jsr     rec_end
        jsr     wait_vbl
        jmp     ui_list_ram
.endproc

; pr_fetch -- ask the server who holds EB_SLOT. C clear: UI_INFOCNT (0 empty,
; 1 held), UI_ONAME / UI_OUSER as tiles, channel closed. C set: UI_INFOCNT =
; $FF, UI_RESULT = the message (ls_fetch closed the channel). Either way
; UI_INFOSLOT = EB_SLOT so the picker does not ask again until it changes.
.proc pr_fetch
        lda     #1
        jsr     ls_fetch
        bcs     fail
        lda     FN_RPLY         ; count
        sta     UI_INFOCNT
        ldy     #0
oname:  lda     FN_RPLY+5,y     ; record 0: slot at +4, name +5, user +13
        jsr     txt_a2t
        sta     UI_ONAME,y
        iny
        cpy     #8
        bne     oname
        ldy     #0
ouser:  lda     FN_RPLY+13,y
        jsr     txt_a2t
        sta     UI_OUSER,y
        iny
        cpy     #8
        bne     ouser
        jsr     net_close
        lda     EB_SLOT
        sta     UI_INFOSLOT
        clc
        rts
fail:   lda     #$FF
        sta     UI_INFOCNT
        lda     EB_SLOT
        sta     UI_INFOSLOT
        sec
        rts
.endproc

; pr_info -- pr_fetch, then row 20: EMPTY | NO INFO | name BY user.
.proc pr_info
        jsr     pr_fetch
        jsr     rec_start
        lda     #20
        ldx     #6
        ldy     #20
        jsr     rec_hdr
        lda     UI_INFOCNT
        beq     empty
        cmp     #$FF
        beq     noinfo
        lda     #<UI_ONAME
        sta     UI_PTR
        lda     #>UI_ONAME
        sta     UI_PTR+1
        ldx     #8
        jsr     rec_copy
        lda     #<s_by
        sta     UI_PTR
        lda     #>s_by
        sta     UI_PTR+1
        ldx     #4
        jsr     rec_copy
        lda     #<UI_OUSER
        sta     UI_PTR
        lda     #>UI_OUSER
        sta     UI_PTR+1
        ldx     #8
        jsr     rec_copy
        jmp     draw
empty:  lda     #<s_empty
        sta     UI_PTR
        lda     #>s_empty
        sta     UI_PTR+1
        ldx     #5
        jsr     rec_copy
        lda     #T_SPACE
        ldx     #15
        jsr     rec_fill
        jmp     draw
noinfo: lda     #<s_noinfo
        sta     UI_PTR
        lda     #>s_noinfo
        sta     UI_PTR+1
        ldx     #7
        jsr     rec_copy
        lda     #T_SPACE
        ldx     #13
        jsr     rec_fill
draw:   jsr     rec_end
        jsr     wait_vbl
        jmp     ui_list_ram
.endproc

; eb_result -- X = message. Show it for ~90 frames, or until A, B or Start
; after the first 30 (a double tap must not hide an error).
; (The countdown is not EB_HOLD: ui_keys owns that one for autorepeat.)
.proc eb_result
        jsr     eb_show
        lda     #90
        sta     UI_FRAME
        lda     #$FF
        sta     EB_PREV
loop:   jsr     wait_vbl
        jsr     ui_keys
        lda     UI_FRAME
        cmp     #60             ; the first half second cannot be skipped
        bcs     tick
        lda     EB_NEW
        and     #$D0
        bne     done
tick:   dec     UI_FRAME
        bne     loop
done:   rts
.endproc

; eb_leave -- common exit: blank our rows, un-mute the APU, back to the game
; (which clears and rebuilds the menu anyway).
.proc eb_leave
        jsr     ui_clear
        lda     #$0F
        sta     APU_STATUS
        rts
.endproc

; eb_restore -- the LOAD state copies $65-$6A to the best times and commits
; $05E0 to the master track as soon as we return, whatever happened. Make both
; copies no-ops so a cancelled or failed load changes nothing.
.proc eb_restore
        ldx     #2
:       lda     EB_BEST_A,x
        sta     EB_HDR+5,x
        lda     EB_BEST_B,x
        sta     EB_HDR+8,x
        dex
        bpl     :-
        jmp     EB_COPYTRK
.endproc

; eb_owner_check -- decide whether EB_SLOT may be written, using what the
; picker already fetched (or fetching now). C clear: go ahead (empty, ours, or
; A REPLACE pressed). C set: A = 0 -> B BACK, return to the picker;
; A != 0 -> an error was shown, leave.
.proc eb_owner_check
        lda     UI_INFOSLOT
        cmp     EB_SLOT
        bne     fetch
        lda     UI_INFOCNT
        cmp     #$FF
        bne     decide
fetch:  jsr     pr_fetch
        bcc     decide
        ldx     UI_RESULT
        jsr     eb_result
        lda     #1
        sec
        rts
decide: lda     UI_INFOCNT
        beq     ok
        ldy     #7
same:   lda     UI_OUSER,y
        cmp     EB_USER,y
        bne     other
        dey
        bpl     same
ok:     clc
        rts
other:  jsr     ui_clear
        jsr     ui_attr_set
        ldx     #MSG_CF_A
        jsr     ui_show_rom
        jsr     rec_start
        lda     #8
        ldx     #11
        ldy     #2
        jsr     rec_hdr
        lda     EB_SLOT
        jsr     txt_dig2
        pha
        txa
        jsr     rec_byte
        pla
        jsr     rec_byte
        lda     #10
        ldx     #12
        ldy     #8
        jsr     rec_hdr
        lda     #<UI_ONAME
        sta     UI_PTR
        lda     #>UI_ONAME
        sta     UI_PTR+1
        ldx     #8
        jsr     rec_copy
        lda     #12
        ldx     #12
        ldy     #8
        jsr     rec_hdr
        lda     #<UI_OUSER
        sta     UI_PTR
        lda     #>UI_OUSER
        sta     UI_PTR+1
        ldx     #8
        jsr     rec_copy
        jsr     rec_end
        jsr     wait_vbl
        jsr     ui_list_ram
        lda     #$FF
        sta     EB_PREV
wait:   jsr     wait_vbl
        jsr     ui_keys
        lda     EB_NEW
        and     #$90            ; A or Start: replace
        bne     yes
        lda     EB_NEW
        and     #$40            ; B: back to the picker
        beq     wait
        lda     #0
        sec
        rts
yes:    clc
        rts
.endproc

; ------------------------------------------------------------------- SAVE
; The game has already built the 64-byte header at $60 and copied the track
; to $05E0. Ask for a slot, a name and (if needed) permission, then POST both
; blocks, 320 bytes, to .../api/track/NN?name=...&user=....
.proc eb_save
        lda     #0
        sta     APU_STATUS      ; the sound engine is paused; hush its last note
        jsr     fn_chk
        JNE     nofuji
        jsr     ak_load_user    ; once per power-on, before any screen
        lda     EB_FLAGS
        and     #FL_NAMEOK
        bne     picker
        ldx     #7              ; first use since power-on: an empty name,
        lda     #T_SPACE        ; not the cold-boot zeros (which are digit tiles)
:       sta     EB_NAME,x
        dex
        bpl     :-
        lda     EB_FLAGS
        ora     #FL_NAMEOK
        sta     EB_FLAGS
picker: jsr     ui_clear
        jsr     ui_attr_set
        jsr     eb_prompt       ; which slot
        bcc     :+
        jmp     leave
:       jsr     ed_run          ; what to call it; B returns to the picker
        bcc     :+
        jmp     picker
:       lda     EB_FLAGS
        and     #FL_USEREDIT
        beq     :+
        jsr     ak_save_user
:       jsr     eb_owner_check
        bcc     post
        cmp     #0              ; B BACK -> picker; an error -> leave
        bne     :+
        jmp     picker
:       jmp     leave
post:   jsr     ui_clear
        ldx     #MSG_SAVING
        jsr     eb_show
        jsr     net_open_post
        JNE     fail
        lda     #NHMODE_POST
        jsr     net_mode
        bne     failc
        lda     #<EB_HDR
        sta     FN_PTR
        lda     #>EB_HDR
        sta     FN_PTR+1
        lda     #64
        jsr     net_write
        bne     failc
        lda     #<EB_TRK
        sta     FN_PTR
        lda     #>EB_TRK
        sta     FN_PTR+1
        lda     #0              ; 256
        jsr     net_write
        bne     failc
        lda     #NHMODE_BODY
        jsr     net_mode
        bne     failc
        jsr     net_status      ; this is the call that performs the POST
        bne     failc
        lda     FN_RPLY+3       ; the N: status code
        cmp     #NSTAT_OK
        beq     ok
        cmp     #NSTAT_EOF      ; an empty 2xx body reads as EOF: also fine
        bne     failc
ok:     jsr     net_close
        ldx     #MSG_SAVED
        jsr     eb_result
leave:  jmp     eb_leave
failc:  pha
        jsr     net_close
        pla
fail:   sta     EB_LASTERR
        ldx     #MSG_NETERR
        jsr     eb_result
        jmp     eb_leave
nofuji: ldx     #MSG_NOFUJI
        jsr     eb_result
        jmp     eb_leave
.endproc

; ------------------------------------------------------------------- LOAD
; Pick a slot from the list, then GET .../api/track/NN: 320 bytes, header
; then track. Nothing in RAM changes until the whole reply has been checked.
.proc eb_load
        lda     #0
        sta     APU_STATUS
        jsr     fn_chk
        JNE     nofuji
        jsr     ls_run
        bcc     chosen
        ldx     UI_RESULT       ; 0 = the player backed out
        JEQ     cancel
        jsr     eb_result
        jmp     cancel
chosen: jsr     ui_clear
        ldx     #MSG_LOADING
        jsr     eb_show
        lda     #NOPEN_GET
        jsr     net_open
        JNE     fail
        lda     #20
        sta     EB_HOLD         ; STATUS retries while the body is still short
stat:   jsr     net_status      ; this is the call that performs the GET
        JNE     failc
        lda     FN_RPLY+3
        cmp     #NSTAT_NOTFOUND
        JEQ     empty
        cmp     #NSTAT_OK
        JNE     failc
        lda     FN_RPLY+1       ; avail >= 320 ($0140)?
        cmp     #2
        bcs     have
        cmp     #1
        bne     wait
        lda     FN_RPLY
        cmp     #$40
        bcs     have
wait:   dec     EB_HOLD
        beq     bad
        jsr     wait_vbl
        jmp     stat
have:   lda     #$40            ; read 320
        ldx     #1
        jsr     net_read
        JNE     failc
        lda     FN_RXLO
        cmp     #$40
        bne     bad
        lda     FN_RXHI
        cmp     #1
        bne     bad
        ldy     #1
sig:    lda     FN_RPLY,y       ; header bytes 1-4 must be the game's signature
        cmp     EB_SIG,y
        bne     bad
        iny
        cpy     #5
        bne     sig
        ldy     #1
hdr:    lda     FN_RPLY,y       ; signature + best times -> $61-$6A
        sta     EB_HDR,y
        iny
        cpy     #11
        bne     hdr
        ldx     #0
trk:    lda     FN_RPLY+64,x    ; the track -> $05E0-$06DF
        sta     EB_TRK,x
        inx
        bne     trk
        jsr     net_close
        ldx     #MSG_LOADED
        jsr     eb_result
        jmp     eb_leave
empty:  jsr     net_close
        ldx     #MSG_EMPTY
        jsr     eb_result
        jmp     cancel
bad:    jsr     net_close
        ldx     #MSG_BADDATA
        jsr     eb_result
        jmp     cancel
failc:  pha
        jsr     net_close
        pla
fail:   sta     EB_LASTERR
        ldx     #MSG_NETERR
        jsr     eb_result
        jmp     cancel
nofuji: ldx     #MSG_NOFUJI
        jsr     eb_result
cancel: jsr     eb_restore
        jmp     eb_leave
.endproc

; eb_irq -- the IRQ vector used to point at sound data; IRQs never fire.
.proc eb_irq
        rti
.endproc
