-- Notes INSA, class averages database
-- Run with: wrangler d1 execute notes-insa-db --file=./schema.sql

CREATE TABLE IF NOT EXISTS submissions (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_hash     TEXT    NOT NULL DEFAULT '',
  academic_year TEXT    NOT NULL,
  department    TEXT    NOT NULL,
  semester      INTEGER NOT NULL CHECK(semester BETWEEN 1 AND 12),
  ue_name       TEXT    NOT NULL,
  subject_name  TEXT    NOT NULL,
  grade         REAL    NOT NULL CHECK(grade >= 0 AND grade <= 20),
  submitted_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- One row per student per subject per academic year, upsert relies on this.
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_subject
  ON submissions(user_hash, academic_year, department, semester, ue_name, subject_name)
  WHERE user_hash != '';

CREATE INDEX IF NOT EXISTS idx_dept_sem_year
  ON submissions(department, semester, academic_year);

CREATE INDEX IF NOT EXISTS idx_submitted_at
  ON submissions(submitted_at);

-- ── Coefficients ──────────────────────────────────────────────────────────
-- Community-shared subject coefficients, keyed per dept+semester+year.
-- Populated from Mobinsapi.Coefficients() and reused by all users.

CREATE TABLE IF NOT EXISTS coefficients (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  department    TEXT    NOT NULL,
  semester      INTEGER NOT NULL CHECK(semester BETWEEN 1 AND 12),
  academic_year TEXT    NOT NULL,
  ue_name       TEXT    NOT NULL,
  subject_name  TEXT    NOT NULL,
  coefficient   REAL    NOT NULL CHECK(coefficient > 0),
  submitted_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_coeff_subject
  ON coefficients(department, semester, academic_year, ue_name, subject_name);

CREATE INDEX IF NOT EXISTS idx_coeff_lookup
  ON coefficients(department, semester, academic_year);

-- Migration for existing deployments (safe to run multiple times):
-- ALTER TABLE submissions ADD COLUMN user_hash TEXT NOT NULL DEFAULT '';

-- ── Association directory ────────────────────────────────────────────────
-- D1 is the source of truth for future association editors. The Worker turns
-- these records into one public JSON document in KV after every authorised
-- change, so Flutter clients never need access to this authoring data.

CREATE TABLE IF NOT EXISTS association_profiles (
  id               TEXT PRIMARY KEY,
  name             TEXT NOT NULL,
  short_name       TEXT,
  category         TEXT NOT NULL,
  summary          TEXT,
  description      TEXT,
  logo_url         TEXT,
  building_code    TEXT,
  links_json       TEXT NOT NULL DEFAULT '{}',
  source_url       TEXT,
  last_verified_at TEXT,
  created_at       TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS association_events (
  id               TEXT PRIMARY KEY,
  association_id   TEXT NOT NULL REFERENCES association_profiles(id) ON DELETE CASCADE,
  title            TEXT NOT NULL,
  starts_at        TEXT NOT NULL,
  ends_at          TEXT,
  description      TEXT,
  location         TEXT,
  building_code    TEXT,
  url              TEXT,
  cover_url        TEXT,
  is_all_day       INTEGER NOT NULL DEFAULT 0 CHECK(is_all_day IN (0, 1)),
  created_at       TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_association_events_starts_at
  ON association_events(starts_at);
CREATE INDEX IF NOT EXISTS idx_association_events_association
  ON association_events(association_id);

-- Invited contacts are scoped to exactly one association. The admin page will
-- use passwordless magic links once a sending domain has been onboarded.
CREATE TABLE IF NOT EXISTS association_owners (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  association_id   TEXT NOT NULL REFERENCES association_profiles(id) ON DELETE CASCADE,
  email            TEXT NOT NULL COLLATE NOCASE,
  role             TEXT NOT NULL DEFAULT 'editor' CHECK(role IN ('editor', 'owner')),
  active           INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
  created_at       TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(association_id, email)
);

CREATE TABLE IF NOT EXISTS association_sessions (
  id               TEXT PRIMARY KEY,
  owner_id         INTEGER NOT NULL REFERENCES association_owners(id) ON DELETE CASCADE,
  token_hash       TEXT NOT NULL UNIQUE,
  expires_at       TEXT NOT NULL,
  created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_association_sessions_owner
  ON association_sessions(owner_id);

-- Magic links are deliberately distinct from sessions: a link is consumed
-- once during verification, then creates a reusable, short-lived session.
CREATE TABLE IF NOT EXISTS association_magic_links (
  id               TEXT PRIMARY KEY,
  owner_id         INTEGER NOT NULL REFERENCES association_owners(id) ON DELETE CASCADE,
  token_hash       TEXT NOT NULL UNIQUE,
  expires_at       TEXT NOT NULL,
  used_at          TEXT,
  created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_association_magic_links_owner
  ON association_magic_links(owner_id);
