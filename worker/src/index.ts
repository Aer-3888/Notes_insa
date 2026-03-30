export interface Env {
  DB: D1Database;
  RATE_LIMIT: KVNamespace;
  APP_SECRET: string;
  IP_SALT: string;
  USER_HASH_SALT: string;
}

// ── Types ──────────────────────────────────────────────────────────────────

interface SubmitSubject {
  ue: string;
  name: string;
  grade: number;
}

interface SubmitBody {
  department: string;
  semester: number;
  subjects: SubmitSubject[];
  username?: string; // optional — absent in old app versions
}

interface AverageRow {
  ue_name: string;
  subject_name: string;
  avg: number;
  min: number;
  max: number;
  count: number;
  // Grade distribution buckets — each covers a 1-point range [low, low+1)
  b0: number;  // [0,  1)
  b1: number;  // [1,  2)
  b2: number;  // [2,  3)
  b3: number;  // [3,  4)
  b4: number;  // [4,  5)
  b5: number;  // [5,  6)
  b6: number;  // [6,  7)
  b7: number;  // [7,  8)
  b8: number;  // [8,  9)
  b9: number;  // [9,  10)
  b10: number; // [10, 11)
  b11: number; // [11, 12)
  b12: number; // [12, 13)
  b13: number; // [13, 14)
  b14: number; // [14, 15)
  b15: number; // [15, 16)
  b16: number; // [16, 17)
  b17: number; // [17, 18)
  b18: number; // [18, 19)
  b19: number; // [19, 20]
}

// ── Helpers ────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-App-Version, X-App-Secret",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function error(message: string, status = 400): Response {
  return json({ error: message }, status);
}

/** SHA-256 hash of a string — used to anonymise IPs for rate-limiting. */
async function hashIp(ip: string, salt: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(ip + salt),
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** SHA-256 hash of a username — used to anonymise students server-side. */
async function hashUsername(username: string, salt: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(username + salt),
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Returns the current academic year string (e.g., "2025-2026").
 * The year starts in August (month index 7).
 */
function getCurrentAcademicYear(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();
  if (month >= 7) {
    return `${year}-${year + 1}`;
  } else {
    return `${year - 1}-${year}`;
  }
}

/** Returns true if the caller is rate-limited (1 submit per dept+semester per IP per 24 h). */
async function isRateLimited(
  kv: KVNamespace,
  ipHash: string,
  department: string,
  semester: number,
): Promise<boolean> {
  const key = `rl:${ipHash}:${department}:${semester}`;
  const existing = await kv.get(key);
  if (existing !== null) return true;
  // Store with 24-hour TTL (86400 seconds)
  await kv.put(key, "1", { expirationTtl: 86400 });
  return false;
}

// ── Validation ─────────────────────────────────────────────────────────────

function validateSubmitBody(body: unknown): body is SubmitBody {
  if (!body || typeof body !== "object") return false;
  const b = body as Record<string, unknown>;

  if (typeof b.department !== "string" || b.department.trim().length === 0)
    return false;
  if (
    typeof b.semester !== "number" ||
    !Number.isInteger(b.semester) ||
    b.semester < 1 ||
    b.semester > 12
  )
    return false;
  if (!Array.isArray(b.subjects) || b.subjects.length === 0) return false;
  if (b.subjects.length > 60) return false;
  if (b.username !== undefined && typeof b.username !== "string") return false;
  if (typeof b.username === "string" && b.username.trim().length === 0)
    return false;

  for (const s of b.subjects) {
    if (!s || typeof s !== "object") return false;
    if (typeof s.ue !== "string" || s.ue.trim().length === 0) return false;
    if (typeof s.name !== "string" || s.name.trim().length === 0) return false;
    if (typeof s.grade !== "number" || s.grade < 0 || s.grade > 20)
      return false;
  }

  return true;
}

// ── Handlers ───────────────────────────────────────────────────────────────

async function handleSubmit(request: Request, env: Env): Promise<Response> {
  const secret = request.headers.get("X-App-Secret");
  if (!secret || secret !== env.APP_SECRET) {
    return error("Unauthorized: APP_SECRET mismatch or missing header", 401);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return error("Invalid JSON body");
  }

  if (!validateSubmitBody(body)) {
    return error(
      "Invalid payload format or missing required fields in subjects array",
    );
  }

  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const ipHash = await hashIp(ip, env.IP_SALT);
  // Compute user hash server-side — salt never leaves Cloudflare.
  // Fall back to IP hash for old app versions that don't send a username.
  const userHash = body.username
    ? await hashUsername(body.username.trim(), env.USER_HASH_SALT)
    : "";
  const rateLimitId = userHash || ipHash;

  const limited = await isRateLimited(
    env.RATE_LIMIT,
    rateLimitId,
    body.department.trim(),
    body.semester,
  );
  if (limited) {
    return json({ ok: true, status: "rate_limited" });
  }
  const academicYear = getCurrentAcademicYear();

  try {
    // Upsert: if the same student (user_hash) submits the same subject again,
    // update their grade rather than inserting a duplicate row.
    // Rows without a user_hash (old app versions) always insert to preserve
    // backwards compatibility; those rely solely on IP rate-limiting for dedup.
    const stmt = userHash
      ? env.DB.prepare(
          `INSERT INTO submissions (user_hash, academic_year, department, semester, ue_name, subject_name, grade)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT (user_hash, academic_year, department, semester, ue_name, subject_name)
           WHERE user_hash != ''
           DO UPDATE SET grade = excluded.grade, submitted_at = datetime('now')`,
        )
      : env.DB.prepare(
          `INSERT INTO submissions (user_hash, academic_year, department, semester, ue_name, subject_name, grade)
           VALUES ('', ?, ?, ?, ?, ?, ?)`,
        );

    const inserts = body.subjects.map((s) =>
      userHash
        ? stmt.bind(
            userHash,
            academicYear,
            body.department.trim(),
            body.semester,
            s.ue.trim(),
            s.name.trim(),
            Math.round(s.grade * 100) / 100,
          )
        : stmt.bind(
            academicYear,
            body.department.trim(),
            body.semester,
            s.ue.trim(),
            s.name.trim(),
            Math.round(s.grade * 100) / 100,
          ),
    );

    await env.DB.batch(inserts);
  } catch (e: any) {
    return error(`Database error: ${e.message}`, 500);
  }

  return json({ ok: true, status: "submitted" });
}

async function handleAverages(
  request: Request,
  env: Env,
): Promise<Response> {
  const url = new URL(request.url);
  const department = url.searchParams.get("department")?.trim();
  const semesterRaw = url.searchParams.get("semester");

  if (!department || department.length === 0) {
    return error("Missing required query param: department");
  }

  const semester = parseInt(semesterRaw ?? "", 10);
  if (isNaN(semester) || semester < 1 || semester > 12) {
    return error("Missing or invalid query param: semester (must be 1–12)");
  }

  const academicYear = getCurrentAcademicYear();

  const result = await env.DB.prepare(
    `SELECT
       ue_name,
       subject_name,
       ROUND(AVG(grade), 2) AS avg,
       ROUND(MIN(grade), 2) AS min,
       ROUND(MAX(grade), 2) AS max,
       COUNT(*)             AS count,
       COUNT(CASE WHEN grade >= 0  AND grade <  1  THEN 1 END) AS b0,
       COUNT(CASE WHEN grade >= 1  AND grade <  2  THEN 1 END) AS b1,
       COUNT(CASE WHEN grade >= 2  AND grade <  3  THEN 1 END) AS b2,
       COUNT(CASE WHEN grade >= 3  AND grade <  4  THEN 1 END) AS b3,
       COUNT(CASE WHEN grade >= 4  AND grade <  5  THEN 1 END) AS b4,
       COUNT(CASE WHEN grade >= 5  AND grade <  6  THEN 1 END) AS b5,
       COUNT(CASE WHEN grade >= 6  AND grade <  7  THEN 1 END) AS b6,
       COUNT(CASE WHEN grade >= 7  AND grade <  8  THEN 1 END) AS b7,
       COUNT(CASE WHEN grade >= 8  AND grade <  9  THEN 1 END) AS b8,
       COUNT(CASE WHEN grade >= 9  AND grade <  10 THEN 1 END) AS b9,
       COUNT(CASE WHEN grade >= 10 AND grade <  11 THEN 1 END) AS b10,
       COUNT(CASE WHEN grade >= 11 AND grade <  12 THEN 1 END) AS b11,
       COUNT(CASE WHEN grade >= 12 AND grade <  13 THEN 1 END) AS b12,
       COUNT(CASE WHEN grade >= 13 AND grade <  14 THEN 1 END) AS b13,
       COUNT(CASE WHEN grade >= 14 AND grade <  15 THEN 1 END) AS b14,
       COUNT(CASE WHEN grade >= 15 AND grade <  16 THEN 1 END) AS b15,
       COUNT(CASE WHEN grade >= 16 AND grade <  17 THEN 1 END) AS b16,
       COUNT(CASE WHEN grade >= 17 AND grade <  18 THEN 1 END) AS b17,
       COUNT(CASE WHEN grade >= 18 AND grade <  19 THEN 1 END) AS b18,
       COUNT(CASE WHEN grade >= 19 AND grade <= 20 THEN 1 END) AS b19
     FROM submissions
     WHERE department  = ?
       AND semester    = ?
       AND academic_year = ?
     GROUP BY ue_name, subject_name
     ORDER BY ue_name, subject_name`,
  )
    .bind(department, semester, academicYear)
    .all<AverageRow>();

  return new Response(JSON.stringify(result.results), {
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  });
}

// ── Router ─────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (url.pathname === "/submit" && request.method === "POST") {
      return handleSubmit(request, env);
    }

    if (url.pathname === "/averages" && request.method === "GET") {
      return handleAverages(request, env);
    }

    return error("Not found", 404);
  },
};
