-- Notes INSA — class averages database
-- Run with: wrangler d1 execute notes-insa-db --file=./schema.sql

CREATE TABLE IF NOT EXISTS submissions (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  department   TEXT    NOT NULL,
  semester     INTEGER NOT NULL CHECK(semester BETWEEN 1 AND 12),
  ue_name      TEXT    NOT NULL,
  subject_name TEXT    NOT NULL,
  grade        REAL    NOT NULL CHECK(grade >= 0 AND grade <= 20),
  submitted_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_dept_sem
  ON submissions(department, semester);

CREATE INDEX IF NOT EXISTS idx_submitted_at
  ON submissions(submitted_at);
