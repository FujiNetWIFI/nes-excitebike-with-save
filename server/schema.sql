-- schema.sql -- the Excitebike track repository.
--
-- One row per saved version of a slot. Every column NOT NULL with a DEFAULT,
-- indexes named IDX_<table>_<fields>, as in the other FujiNet servers.
-- store.go adds any column missing from an older database at startup.
CREATE TABLE track (
    id          INTEGER  PRIMARY KEY AUTOINCREMENT,
    slot        INTEGER  NOT NULL DEFAULT 0,       -- 0-99
    version     INTEGER  NOT NULL DEFAULT 1,       -- 1, 2, ... per slot
    data        BLOB     NOT NULL DEFAULT X'',     -- the 320 bytes the game saves
    remote      TEXT     NOT NULL DEFAULT '',      -- who uploaded it
    name        TEXT     NOT NULL DEFAULT '',      -- track name, <= 8 of A-Z 0-9 space
    username    TEXT     NOT NULL DEFAULT '',      -- player name, <= 8 of A-Z 0-9
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IDX_track_slot_version ON track (slot, version);
