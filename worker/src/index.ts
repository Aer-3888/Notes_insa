export interface Env {
  DB: D1Database;
  RATE_LIMIT: KVNamespace;
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
}

interface AverageRow {
  ue_name: string;
  subject_name: string;
  avg: number;
  min: number;
  max: number;
  count: number;
}

// ── Helpers ────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-App-Version",
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
async function hashIp(ip: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(ip + "notes-insa-salt"),
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
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
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return error("Invalid JSON body");
  }

  if (!validateSubmitBody(body)) {
    return error(
      "Invalid payload. Expected: { department, semester, subjects: [{ue, name, grade}] }",
    );
  }

  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const ipHash = await hashIp(ip);

  const limited = await isRateLimited(
    env.RATE_LIMIT,
    ipHash,
    body.department.trim(),
    body.semester,
  );
  if (limited) {
    // Return 200 silently — no need to tell the client it was rate-limited
    return json({ ok: true });
  }

  // Insert each subject as a separate row
  const stmt = env.DB.prepare(
    `INSERT INTO submissions (department, semester, ue_name, subject_name, grade)
     VALUES (?, ?, ?, ?, ?)`,
  );

  const inserts = body.subjects.map((s) =>
    stmt.bind(
      body.department.trim(),
      body.semester,
      s.ue.trim(),
      s.name.trim(),
      Math.round(s.grade * 100) / 100, // store with 2 decimal precision
    ),
  );

  await env.DB.batch(inserts);

  return json({ ok: true });
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

  const result = await env.DB.prepare(
    `SELECT
       ue_name,
       subject_name,
       ROUND(AVG(grade), 2) AS avg,
       ROUND(MIN(grade), 2) AS min,
       ROUND(MAX(grade), 2) AS max,
       COUNT(*)             AS count
     FROM submissions
     WHERE department  = ?
       AND semester    = ?
       AND submitted_at > datetime('now', '-180 days')
     GROUP BY ue_name, subject_name
     HAVING COUNT(*) >= 3
     ORDER BY ue_name, subject_name`,
  )
    .bind(department, semester)
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
