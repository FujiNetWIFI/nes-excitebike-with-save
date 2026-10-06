; macros.inc -- shared assembler macros for the patch.

; Long-range conditional jumps for flows that outgrow a branch's reach.
.macro  JNE target
        .local  skip
        beq     skip
        jmp     target
skip:
.endmacro
.macro  JEQ target
        .local  skip
        bne     skip
        jmp     target
skip:
.endmacro

; Excitebike font: 0-9 = $00-$09, A-Z = $0A-$23, space $FC.
.macro  TXT str
        .repeat .strlen(str), i
            .if .strat(str, i) = ' '
                .byte T_SPACE
            .elseif .strat(str, i) >= '0' .and .strat(str, i) <= '9'
                .byte .strat(str, i) - '0'
            .else
                .byte .strat(str, i) - 'A' + $0A
            .endif
        .endrepeat
.endmacro

; A $D3C1 text record at row/col of nametable 0.
; (ca65 binds & tighter than +, so every argument is parenthesised.)
.macro  REC row, col, str
        .byte   $20 + ((row) >> 3), (((row) & 7) << 5) + (col), .strlen(str)
        TXT     str
.endmacro
; A fill record: n copies of one tile (n < 64).
.macro  FILL row, col, n, tile
        .byte   $20 + ((row) >> 3), (((row) & 7) << 5) + (col), $40 | (n), tile
.endmacro

; Row 16 / row 20 text at col 10, each preceded by a 14-cell blank (cols 9-22).
.macro  ROW16 str
        FILL    16, 9, 14, T_SPACE
        REC     16, 10, str
.endmacro
.macro  ROW20 str
        FILL    20, 9, 14, T_SPACE
        REC     20, 10, str
.endmacro
.macro  BLANK16
        FILL    16, 9, 14, T_SPACE
.endmacro
.macro  BLANK20
        FILL    20, 9, 14, T_SPACE
.endmacro
