; frag.s -- the 16 bytes the original ROM keeps at $FFF0-$FFFF, relocated to
; $BFF0 so "FUJI" can take their place. $FFF0-$FFF9 is a sound fragment the
; song table entry at $FDF6 points to; build.py patches that pointer's high
; byte ($FDF8) to $BF. frag.inc is generated from the ROM at build time.
        .segment "FRAG"
        .include "frag.inc"
