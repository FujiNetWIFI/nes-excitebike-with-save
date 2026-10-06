; fujinet.inc -- equates for the FujiNet cartridge mailbox on the NES.
;
; Copied from fujinet-firmware pico/nes/testrom/fujinet.inc (itself mirrored
; from firmware/include/fuji_mailbox.h). The only change: the zero-page block
; the library owns moved from $E0-$E8 (Excitebike's sound engine lives there)
; to $02-$0A, the tape routines' old scratch area, which is free while the
; game's NMI is off -- the only time this code runs.
;
; THE ONE RULE: only STA/STX/STY to $5500-$57FF, plain or indexed. Never an
; RMW instruction (INC/DEC/ASL/LSR/ROL/ROR abs): the 6502 writes the old value
; back first, and that lands as a spurious event. tools/checkrom.py rejects it.

; ---------------- cart -> console, painted ----------------
FN_RPLY   = $5000               ; the 1K reply window
FN_ACKS   = $5400               ; echoes SEQ when the reply is ready
FN_STAT   = $5401               ; bit0 link up, bit1 busy
FN_ERR    = $5402               ; FNE* below
FN_RCMD   = $5403               ; $06 ACK / $15 NAK
FN_RXLO   = $5404               ; reply length, little-endian
FN_RXHI   = $5405
FN_MAG0   = $5409               ; 'F'
FN_MAG1   = $540A               ; 'N'

; ---------------- console -> cart, write-only ----------------
FN_RSEL   = $5500               ; write V to +n (n < $80): register n = V
FN_TX     = $5700               ; a write anywhere in the page appends

; Registers.
FR_DEV    = $00
FR_CMD    = $01
FR_NPAR   = $02
FR_DRST   = $05                 ; any value: rewind the TX write pointer
FR_SEQ    = $10                 ; nonzero and != ACKSEQ: launch

; Errors, as fn_go / fn_ack return them in A.
FNEOK     = 0                   ; FN_ERR_OK
FNEWAIT   = $FF                 ; the cart never answered at all
FNENAK    = $EE                 ; the FujiNet said NAK

; Devices and commands, from include/fujiDeviceID.h and fujiCommandID.h.
FNDEVN    = $71                 ; N1:
FNCNOPEN  = $4F                 ; NET_OPEN      p0 mode(1) p1 trans(1) + devicespec
FNCNCLOSE = $43                 ; NET_CLOSE
FNCNREAD  = $52                 ; NET_READ      p0 len(2)
FNCNWRITE = $57                 ; NET_WRITE     p0 len(2) + data
FNCNSTAT  = $53                 ; NET_STATUS    -> avail(2) conn err
FNCNHMODE = $4D                 ; NET_SET_HTTP_MODE p0 any(1) p1 mode(1)

; HTTP open modes (lib/network-protocol/HTTP.h) and channel modes.
NOPEN_GET = 12                  ; GET_H: raw path, no resolve
NOPEN_POST = 13                 ; POST
NHMODE_BODY = 0
NHMODE_POST = 4                 ; SET_POST_DATA: WRITEs append to the body

; N: STATUS error codes (status_error_codes.h).
NSTAT_OK   = 1
NSTAT_EOF  = 136
NSTAT_NOTFOUND = 170

; ---------------- zero page the library owns ($02-$0A) ----------------
FN_SEQ    = $02                 ; the sequence we are waiting for
FN_CNT    = $03                 ; timeout quanta remaining
FN_DEV    = $04                 ; transaction setup, read by fn_beg
FN_CMD    = $05
FN_NPR    = $06
FN_TMO    = $07                 ; timeout, in ~0.5-0.7 s quanta
FN_PTR    = $08                 ; a data pointer (2 bytes)
FN_PCNT   = $0A                 ; spare

; The FUJI device and its app key commands (payload only, no parameters).
FNDEVFUJI = $70
FNCAKOPEN = $DC                 ; payload: creator lo, hi, app, key, mode (0 read / 1 write), 0
FNCAKREAD = $DD                 ; reply: len lo, len hi, data (<= 64)
FNCAKWRITE = $DE                ; payload: the data (<= 64), after an OPEN with mode 1
FNCAKCLOSE = $DB
