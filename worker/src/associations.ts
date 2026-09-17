export interface AssociationsEnv {
  DB: D1Database;
  ASSOCIATIONS?: KVNamespace;
}

type JsonRecord = Record<string, unknown>;

interface AssociationRow {
  id: string;
  name: string;
  short_name: string | null;
  category: string;
  summary: string | null;
  description: string | null;
  logo_url: string | null;
  building_code: string | null;
  links_json: string;
  source_url: string | null;
  last_verified_at: string | null;
}

interface EventRow {
  id: string;
  association_id: string;
  title: string;
  starts_at: string;
  ends_at: string | null;
  description: string | null;
  location: string | null;
  building_code: string | null;
  url: string | null;
  cover_url: string | null;
  is_all_day: number;
}

interface OwnerRow {
  association_id: string;
  role: string;
}

const publicKey = 'public:associations';
const publicCacheControl = 'public, max-age=60';

function response(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {'Content-Type': 'application/json', ...headers},
  });
}

function asRecord(value: unknown): JsonRecord | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

function text(value: unknown, max = 2000): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= max ? trimmed : null;
}

function optionalText(value: unknown, max = 2000): string | null {
  if (value === undefined || value === null) return null;
  return text(value, max);
}

function publicUrl(value: unknown): string | null {
  const candidate = optionalText(value, 2048);
  if (candidate === null) return null;
  try {
    const url = new URL(candidate);
    return url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

function links(value: unknown): JsonRecord | null {
  const candidate = asRecord(value);
  if (candidate === null) return null;
  const out: JsonRecord = {};
  for (const key of ['instagram', 'website', 'email', 'discord', 'facebook']) {
    const item = optionalText(candidate[key], 2048);
    if (item !== null) out[key] = item;
  }
  return out;
}

function isCategory(value: string): boolean {
  return [
    'bde', 'sport', 'culture', 'jeux', 'tech', 'gastronomie', 'engagement',
    'international', 'entreprise', 'filiere', 'autre',
  ].includes(value);
}

async function tokenHash(token: string): Promise<string> {
  const bytes = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}

async function ownerFor(
  request: Request,
  env: AssociationsEnv,
  associationId: string,
): Promise<OwnerRow | null> {
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return null;
  const rawToken = authorization.substring('Bearer '.length).trim();
  if (rawToken.length < 32) return null;
  const hash = await tokenHash(rawToken);
  return env.DB.prepare(
    `SELECT owners.association_id, owners.role
       FROM association_sessions AS sessions
       JOIN association_owners AS owners ON owners.id = sessions.owner_id
      WHERE sessions.token_hash = ?
        AND sessions.expires_at > datetime('now')
        AND owners.association_id = ?`,
  ).bind(hash, associationId).first<OwnerRow>();
}

function serializedLinks(value: string): JsonRecord {
  try {
    return asRecord(JSON.parse(value)) ?? {};
  } catch {
    return {};
  }
}

async function publish(env: AssociationsEnv): Promise<void> {
  if (env.ASSOCIATIONS === undefined) {
    throw new Error('ASSOCIATIONS KV binding is unavailable');
  }
  const profiles = await env.DB.prepare(
    `SELECT id, name, short_name, category, summary, description, logo_url,
            building_code, links_json, source_url, last_verified_at
       FROM association_profiles
      ORDER BY name COLLATE NOCASE`,
  ).all<AssociationRow>();
  const events = await env.DB.prepare(
    `SELECT id, association_id, title, starts_at, ends_at, description,
            location, building_code, url, cover_url, is_all_day
       FROM association_events
      ORDER BY starts_at`,
  ).all<EventRow>();
  const byAssociation = new Map<string, EventRow[]>();
  for (const event of events.results) {
    byAssociation.set(event.association_id, [
      ...(byAssociation.get(event.association_id) ?? []), event,
    ]);
  }
  const payload = {
    version: 1,
    updatedAt: new Date().toISOString(),
    associations: profiles.results.map((profile) => ({
      id: profile.id,
      name: profile.name,
      ...(profile.short_name === null ? {} : {shortName: profile.short_name}),
      category: profile.category,
      ...(profile.summary === null ? {} : {summary: profile.summary}),
      ...(profile.description === null ? {} : {description: profile.description}),
      ...(profile.logo_url === null ? {} : {logoUrl: profile.logo_url}),
      ...(profile.building_code === null ? {} : {buildingCode: profile.building_code}),
      links: serializedLinks(profile.links_json),
      ...(profile.source_url === null ? {} : {sourceUrl: profile.source_url}),
      ...(profile.last_verified_at === null
        ? {}
        : {lastVerifiedAt: profile.last_verified_at}),
      events: (byAssociation.get(profile.id) ?? []).map((event) => ({
        id: event.id,
        title: event.title,
        startsAt: event.starts_at,
        ...(event.ends_at === null ? {} : {endsAt: event.ends_at}),
        ...(event.description === null ? {} : {description: event.description}),
        ...(event.location === null ? {} : {location: event.location}),
        ...(event.building_code === null
          ? {}
          : {buildingCode: event.building_code}),
        ...(event.url === null ? {} : {url: event.url}),
        ...(event.cover_url === null ? {} : {coverUrl: event.cover_url}),
        ...(event.is_all_day === 0 ? {} : {isAllDay: true}),
      })),
    })),
  };
  await env.ASSOCIATIONS.put(publicKey, JSON.stringify(payload));
}

export async function handlePublicAssociations(
  env: AssociationsEnv,
  corsHeaders: HeadersInit,
): Promise<Response> {
  const value = await env.ASSOCIATIONS?.get(publicKey);
  if (value === undefined || value === null) {
    return response({error: 'Association feed unavailable'}, 503, corsHeaders);
  }
  return new Response(value, {
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'Cache-Control': publicCacheControl,
    },
  });
}

export async function handleMagicLinkRequest(): Promise<Response> {
  // A sender domain is not onboarded yet. Keeping the endpoint explicit avoids
  // pretending that an invitation was sent while preserving the future route.
  return response({error: 'Email invitations are not configured'}, 503);
}

export async function handleAdminAssociation(
  request: Request,
  env: AssociationsEnv,
  associationId: string,
): Promise<Response> {
  if (await ownerFor(request, env, associationId) === null) {
    return response({error: 'Unauthorized'}, 401);
  }
  if (request.method === 'GET') {
    const association = await env.DB.prepare(
      `SELECT id, name, short_name, category, summary, description, logo_url,
              building_code, links_json, source_url, last_verified_at
         FROM association_profiles WHERE id = ?`,
    ).bind(associationId).first<AssociationRow>();
    return association === null
      ? response({error: 'Not found'}, 404)
      : response(association);
  }
  if (request.method !== 'PUT') return response({error: 'Method not allowed'}, 405);
  let body: JsonRecord | null;
  try {
    body = asRecord(await request.json());
  } catch {
    body = null;
  }
  if (body === null) return response({error: 'Invalid association payload'}, 400);
  const name = text(body.name, 160);
  const category = text(body.category, 32);
  const profileLinks = links(body.links);
  if (name === null || category === null || !isCategory(category) || profileLinks === null) {
    return response({error: 'Invalid association payload'}, 400);
  }
  const result = await env.DB.prepare(
    `UPDATE association_profiles
        SET name = ?, short_name = ?, category = ?, summary = ?, description = ?,
            logo_url = ?, building_code = ?, links_json = ?, source_url = ?,
            last_verified_at = datetime('now'), updated_at = datetime('now')
      WHERE id = ?`,
  ).bind(
    name, optionalText(body.shortName, 80), category, optionalText(body.summary, 280),
    optionalText(body.description, 6000), publicUrl(body.logoUrl),
    optionalText(body.buildingCode, 32), JSON.stringify(profileLinks),
    publicUrl(body.sourceUrl), associationId,
  ).run();
  if (result.meta.changes === 0) return response({error: 'Not found'}, 404);
  try {
    await publish(env);
  } catch {
    return response({error: 'Saved, but publication is unavailable'}, 503);
  }
  return response({ok: true});
}

export async function handleAdminEvent(
  request: Request,
  env: AssociationsEnv,
  associationId: string,
  eventId?: string,
): Promise<Response> {
  if (await ownerFor(request, env, associationId) === null) {
    return response({error: 'Unauthorized'}, 401);
  }
  if (request.method === 'DELETE' && eventId !== undefined) {
    await env.DB.prepare(
      'DELETE FROM association_events WHERE id = ? AND association_id = ?',
    ).bind(eventId, associationId).run();
    await publish(env);
    return response({ok: true});
  }
  if (!['POST', 'PUT'].includes(request.method)) {
    return response({error: 'Method not allowed'}, 405);
  }
  let body: JsonRecord | null;
  try {
    body = asRecord(await request.json());
  } catch {
    body = null;
  }
  const id = eventId ?? (body === null ? null : text(body.id, 120));
  const title = body === null ? null : text(body.title, 200);
  const startsAt = body === null ? null : text(body.startsAt, 64);
  if (id === null || title === null || startsAt === null || Number.isNaN(Date.parse(startsAt))) {
    return response({error: 'Invalid event payload'}, 400);
  }
  await env.DB.prepare(
    `INSERT INTO association_events (
       id, association_id, title, starts_at, ends_at, description, location,
       building_code, url, cover_url, is_all_day, updated_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
     ON CONFLICT(id) DO UPDATE SET
       title = excluded.title, starts_at = excluded.starts_at, ends_at = excluded.ends_at,
       description = excluded.description, location = excluded.location,
       building_code = excluded.building_code, url = excluded.url,
       cover_url = excluded.cover_url, is_all_day = excluded.is_all_day,
       updated_at = datetime('now')
     WHERE association_events.association_id = excluded.association_id`,
  ).bind(
    id, associationId, title, startsAt, optionalText(body?.endsAt, 64),
    optionalText(body?.description, 6000), optionalText(body?.location, 200),
    optionalText(body?.buildingCode, 32), publicUrl(body?.url), publicUrl(body?.coverUrl),
    body?.isAllDay === true ? 1 : 0,
  ).run();
  try {
    await publish(env);
  } catch {
    return response({error: 'Saved, but publication is unavailable'}, 503);
  }
  return response({ok: true, id});
}
