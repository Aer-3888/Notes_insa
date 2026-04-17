-- Notes INSA — class averages database
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

-- One row per student per subject per academic year — upsert relies on this.
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
