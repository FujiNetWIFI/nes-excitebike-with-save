; msgs.inc -- ids of the ROM draw lists in strings.s, shared with the flows.
MSG_SAVE_SLOT = 0               ; picker static part: title row 16 + hint row 22
MSG_LOAD_SLOT = 1
MSG_SAVING    = 2
MSG_LOADING   = 3
MSG_SAVED     = 4
MSG_LOADED    = 5
MSG_NOFUJI    = 6
MSG_EMPTY     = 7
MSG_NETERR    = 8
MSG_BADDATA   = 9
MSG_BLANK     = 10
MSG_NOTRACKS  = 11
MSG_ED_A      = 12              ; editor: title and field labels
MSG_ED_B      = 13              ; editor: key hints
MSG_HINT_NAME = 14              ; editor: ENTER A NAME
MSG_HINT_USER = 15              ; editor: USER 2 TO 8 CHARS
MSG_HINTCLR   = 16              ; editor: blank the hint row
MSG_CF_A      = 17              ; overwrite confirmation, static part
MSG_LS_A      = 18              ; load list, static part
MSG_ATTR      = 19              ; attribute bytes for rows 4-27 -> palette 3
MSG_CLR0      = 20              ; 8 lists clearing rows 4-27, three rows each
MSG_COUNT     = 28

; What eb_show adds to a row-16 message from RAM.
DIG_NONE     = 0
DIG_SLOT     = 1                ; two decimal digits of EB_SLOT
DIG_HEX      = 2                ; two hex digits of EB_LASTERR
DIG_SLOTNAME = 3                ; the slot digits, and EB_NAME on row 18
