// Live washer/dryer status for the two INSA Rennes WASHiN laundries.
//
// WASHiN exposes status only behind an OAuth2 password grant, so the Worker
// logs in once with a dedicated service account, caches the token, and reads
// both sites with it. One shared snapshot serves every student, capping upstream
// reads at roughly one per STATUS_TTL_SECONDS. The Location header picks the
// site per request, so one token covers both 174 and 175.

const WASHIN_API = "https://mobile.kosmoshub.com/washin/api";
const WASHIN_TOKEN_URL = "https://mobile.kosmoshub.com/washin/oauth/v2/token";

// App-level OAuth client, public in the APK (not a user secret).
const CLIENT_ID = "1_1881648594";
const CLIENT_SECRET = "A4f5d4gf59aT4566999999GHJ";

const USER_AGENT = "okhttp/4.12.0";

const SITES: ReadonlyArray<{ id: number; name: string }> = [
  { id: 174, name: "Les Glénans (Bât 16)" },
  { id: 175, name: "Cézembre (Bât 15)" },
];

// Path segment on /catalog/machines/{type}.
const TYPE_WASHER = 1;
const TYPE_DRYER = 2;

const TOKEN_KEY = "washin:token";
const STATUS_KEY = "washin:status";

// Freshness window before a refresh is triggered.
const STATUS_TTL_SECONDS = 30;
// Hard KV TTL, longer so an outage serves stale data instead of nothing.
const STATUS_HARD_TTL_SECONDS = 3600;
// Refresh the token this early before it expires.
const TOKEN_EXPIRY_SLACK_SECONDS = 120;

export type MachineState =
  | "free"
  | "busy"
  | "reserved"
  | "finished"
  | "broken"
  | "unknown";

export interface LaundryMachine {
  name: string;
  size: string;
  state: MachineState;
  // Seconds left on the current cycle, 0 unless running.
  secLeft: number;
}

export interface LaundryGroup {
  free: number;
  total: number;
  machines: LaundryMachine[];
}

export interface LaundrySiteStatus {
  id: number;
  name: string;
  washers: LaundryGroup;
  dryers: LaundryGroup;
}

export interface LaundryPayload {
  sites: LaundrySiteStatus[];
  cachedAt: string;
  // Set when the refresh failed and this is a last-known snapshot.
  stale?: boolean;
}

interface WashinEnv {
  LAUNDRY_CACHE: KVNamespace;
  WASHIN_USER: string;
  WASHIN_PASS: string;
}

interface TokenRecord {
  access_token: string;
  refresh_token: string;
  expiresAt: number; // epoch ms
}

interface StatusRecord {
  payload: LaundryPayload;
  cachedAt: number; // epoch ms
}

// Only the fields we use; the endpoint returns a few more.
interface RawMachine {
  name?: string;
  size?: string;
  isBroken?: boolean;
  isAvailable?: boolean;
  isBusy?: boolean;
  isReserved?: boolean;
  endOfCycle?: boolean;
  secLeft?: number;
}

// Returns a fresh or cached snapshot, refreshing only when the cache is older
// than STATUS_TTL_SECONDS. Falls back to the last snapshot (flagged stale) on an
// upstream failure, and throws only when there is nothing to serve.
export async function getLaundryStatus(env: WashinEnv): Promise<LaundryPayload> {
  const cached = await readStatus(env.LAUNDRY_CACHE);
  const now = Date.now();
  if (cached && now - cached.cachedAt < STATUS_TTL_SECONDS * 1000) {
    return cached.payload;
  }

  try {
    const sites = await fetchAllSites(env);
    const payload: LaundryPayload = {
      sites,
      cachedAt: new Date().toISOString(),
    };
    await env.LAUNDRY_CACHE.put(
      STATUS_KEY,
      JSON.stringify({ payload, cachedAt: Date.now() } satisfies StatusRecord),
      { expirationTtl: STATUS_HARD_TTL_SECONDS },
    );
    return payload;
  } catch (err) {
    if (cached) {
      return { ...cached.payload, stale: true };
    }
    throw err;
  }
}

// Reads both sites with one token, retrying once with a fresh login if the
// token is rejected.
async function fetchAllSites(env: WashinEnv): Promise<LaundrySiteStatus[]> {
  let token = await getToken(env);
  try {
    return await readSites(token.access_token);
  } catch (err) {
    if (err instanceof UnauthorizedError) {
      token = await login(env);
      return await readSites(token.access_token);
    }
    throw err;
  }
}

async function readSites(accessToken: string): Promise<LaundrySiteStatus[]> {
  const sites: LaundrySiteStatus[] = [];
  for (const site of SITES) {
    const [washers, dryers] = await Promise.all([
      readGroup(accessToken, site.id, TYPE_WASHER),
      readGroup(accessToken, site.id, TYPE_DRYER),
    ]);
    sites.push({ id: site.id, name: site.name, washers, dryers });
  }
  return sites;
}

async function readGroup(
  accessToken: string,
  locationId: number,
  type: number,
): Promise<LaundryGroup> {
  const res = await fetch(`${WASHIN_API}/catalog/machines/${type}`, {
    headers: {
      "User-Agent": USER_AGENT,
      Accept: "application/json",
      Authorization: `Bearer ${accessToken}`,
      Location: String(locationId),
      Session: "",
    },
  });
  if (res.status === 401) throw new UnauthorizedError();
  if (!res.ok) {
    throw new Error(`machines ${locationId}/${type} HTTP ${res.status}`);
  }
  const raw = (await res.json()) as unknown;
  if (!Array.isArray(raw)) {
    throw new Error(`machines ${locationId}/${type}: unexpected body`);
  }
  const machines = raw.map((m) => mapMachine(m as RawMachine));
  return {
    total: machines.length,
    free: machines.filter((m) => m.state === "free").length,
    machines,
  };
}

// Collapses the WASHiN flags into one state, most-blocking first so a machine is
// never shown free while broken, finishing, or reserved.
function mapMachine(m: RawMachine): LaundryMachine {
  const state: MachineState = m.isBroken
    ? "broken"
    : m.endOfCycle
      ? "finished"
      : m.isBusy
        ? "busy"
        : m.isReserved
          ? "reserved"
          : m.isAvailable
            ? "free"
            : "unknown";
  return {
    name: m.name ?? "?",
    size: m.size ?? "",
    state,
    secLeft: state === "busy" ? Math.max(0, m.secLeft ?? 0) : 0,
  };
}

// Reuses the cached token until it is near expiry.
async function getToken(env: WashinEnv): Promise<TokenRecord> {
  const cached = await readToken(env.LAUNDRY_CACHE);
  if (
    cached &&
    cached.expiresAt - Date.now() > TOKEN_EXPIRY_SLACK_SECONDS * 1000
  ) {
    return cached;
  }
  return login(env);
}

async function login(env: WashinEnv): Promise<TokenRecord> {
  const res = await fetch(WASHIN_TOKEN_URL, {
    method: "POST",
    headers: {
      "User-Agent": USER_AGENT,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "password",
      username: env.WASHIN_USER,
      password: env.WASHIN_PASS,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
    }),
  });
  if (!res.ok) throw new Error(`WASHiN login HTTP ${res.status}`);
  const body = (await res.json()) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
  };
  if (!body.access_token) throw new Error("WASHiN login: no access_token");
  const record: TokenRecord = {
    access_token: body.access_token,
    refresh_token: body.refresh_token ?? "",
    expiresAt: Date.now() + (body.expires_in ?? 3600) * 1000,
  };
  await env.LAUNDRY_CACHE.put(TOKEN_KEY, JSON.stringify(record), {
    expirationTtl: (body.expires_in ?? 3600) + 300,
  });
  return record;
}

async function readToken(kv: KVNamespace): Promise<TokenRecord | null> {
  const raw = await kv.get(TOKEN_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as TokenRecord;
  } catch {
    return null;
  }
}

async function readStatus(kv: KVNamespace): Promise<StatusRecord | null> {
  const raw = await kv.get(STATUS_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as StatusRecord;
  } catch {
    return null;
  }
}

// Signals a rejected token so the caller can re-login once.
class UnauthorizedError extends Error {
  constructor() {
    super("WASHiN unauthorized");
    this.name = "UnauthorizedError";
  }
}
