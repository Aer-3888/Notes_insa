/// ADE group list.
///
/// The app reads timetables straight from INSA's own ADE anonymous export, but
/// ADE exposes no anonymous *resource listing* (its /jsp/webapi needs a session).
/// So the group names come from the ade-planning wrapper, refreshed here once a
/// day and served from KV. One upstream request per day serves every user, and
/// the app ships a bundled copy so it still works if this route is unavailable.

export interface AdeGroup {
  id: number;
  name: string;
}

export interface AdeGroupsPayload {
  version: number;
  projectId: number;
  fetchedAt: string;
  groups: AdeGroup[];
}

export const ADE_GROUPS_KEY = "ade:groups";

/// Kept far longer than the refresh interval so a failed refresh serves stale
/// data rather than nothing. Only a successful fetch overwrites it.
const HARD_TTL_SECONDS = 30 * 24 * 3600;

const WRAPPER_ORIGIN = "https://ade-planning.insa-rennes.fr";

/// The wrapper gates /api/ behind a fixed cookie. It is a constant, not a
/// session: presenting it is what a browser does on any page load.
const WRAPPER_TOKEN = "9944b09199c62bcf9418ad846dd0e4bbdfc6ee4b";

const USER_AGENT =
  "CampusINSA/1.0 (+https://github.com/Aer-3888/Notes_insa)";

interface WrapperResource {
  id: string;
  name: string;
}

/// Fetches the student group list from the wrapper and normalizes it.
/// Only the `student` category is kept: rooms and modules are not selectable.
export async function fetchAdeGroups(): Promise<AdeGroupsPayload> {
  const response = await fetch(`${WRAPPER_ORIGIN}/api/resources/`, {
    headers: {
      Cookie: `ade_auth_token=${WRAPPER_TOKEN}`,
      "User-Agent": USER_AGENT,
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error(`ade resources HTTP ${response.status}`);
  }

  const raw = (await response.json()) as Record<string, WrapperResource[]>;
  const students = raw.student ?? [];
  const groups: AdeGroup[] = [];
  for (const r of students) {
    const id = Number.parseInt(r.id, 10);
    const name = (r.name ?? "").trim();
    if (Number.isFinite(id) && name.length > 0) groups.push({ id, name });
  }
  if (groups.length === 0) throw new Error("ade resources returned no groups");

  groups.sort((a, b) => a.name.localeCompare(b.name, "fr"));
  return {
    version: 1,
    projectId: 2,
    fetchedAt: new Date().toISOString(),
    groups,
  };
}

/// Refreshes the stored list. Never clears it on failure.
export async function refreshAdeGroups(kv: KVNamespace): Promise<number> {
  const payload = await fetchAdeGroups();
  await kv.put(ADE_GROUPS_KEY, JSON.stringify(payload), {
    expirationTtl: HARD_TTL_SECONDS,
  });
  return payload.groups.length;
}

/// Reads the stored list, refreshing on a cold cache.
export async function readAdeGroups(
  kv: KVNamespace,
): Promise<AdeGroupsPayload | null> {
  const stored = await kv.get(ADE_GROUPS_KEY);
  if (stored !== null) return JSON.parse(stored) as AdeGroupsPayload;
  try {
    await refreshAdeGroups(kv);
  } catch {
    return null;
  }
  const seeded = await kv.get(ADE_GROUPS_KEY);
  return seeded === null ? null : (JSON.parse(seeded) as AdeGroupsPayload);
}
