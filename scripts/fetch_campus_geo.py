#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Bake the INSA campus geometry asset from OpenStreetMap.

Run by hand; the output is committed. Usage:

    python scripts/fetch_campus_geo.py            # use cached OSM response
    python scripts/fetch_campus_geo.py --refresh  # re-query Overpass

Emits assets/data/campus_geo.json. Fails loudly if the baked data would
not support routing; see check_invariants.
"""

import argparse
import collections
import io
import json
import math
import os
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, '.campus_geo_cache.json')
OVERRIDES = os.path.join(ROOT, 'assets', 'data', 'campus_geo_overrides.json')
PLACES = os.path.join(ROOT, 'assets', 'data', 'campus_places.json')
OUT = os.path.join(ROOT, 'assets', 'data', 'campus_geo.json')

# Fetch wider than we keep, so paths leading onto the site stay connected.
FETCH_BBOX = (48.1190, -1.6400, 48.1260, -1.6290)
# Buildings kept for rendering.
SITE_BBOX = (48.1195, -1.6390, 48.1250, -1.6310)
# Graph kept for routing; wider, so arriving from the tram still routes.
ROUTE_BBOX = (48.1188, -1.6398, 48.1256, -1.6296)

ORIGIN_LAT, ORIGIN_LON = 48.1220, -1.6350
M_PER_DEG_LAT = 111320.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN_LAT))

# Cost multipliers: bias against roads so nobody is routed down a delivery
# route running beside a footpath.
WEIGHTS = {
    'footway': 1.0, 'path': 1.0, 'pedestrian': 1.0,
    'steps': 1.6, 'living_street': 1.1, 'cycleway': 1.1,
    'service': 1.4, 'track': 1.5, 'unclassified': 1.8, 'residential': 1.8,
}
USABLE_ENTRANCE = ('main', 'yes')

OVERPASS = 'https://overpass-api.de/api/interpreter'
QUERY = """[out:json][timeout:170];
(
  way["building"](%f,%f,%f,%f);
  relation["building"](%f,%f,%f,%f);
  way["highway"~"^(%s)$"](%f,%f,%f,%f);
  node["entrance"](%f,%f,%f,%f);
);
out body;
>;
out skel qt;
""" % (FETCH_BBOX + FETCH_BBOX + ('|'.join(sorted(WEIGHTS)),) + FETCH_BBOX
       + FETCH_BBOX)


def fetch(refresh):
    if not refresh and os.path.exists(CACHE):
        with io.open(CACHE, encoding='utf-8') as f:
            return json.load(f)
    data = urllib.parse.urlencode({'data': QUERY}).encode()
    # Overpass answers 406 to requests without a real User-Agent.
    req = urllib.request.Request(
        OVERPASS, data=data,
        headers={'User-Agent': 'notes-insa-campus-geo/1.0'})
    with urllib.request.urlopen(req, timeout=200) as r:
        raw = json.loads(r.read().decode('utf-8'))
    with io.open(CACHE, 'w', encoding='utf-8') as f:
        f.write(json.dumps(raw))
    return raw


def to_xy(lat, lon):
    return ((lon - ORIGIN_LON) * M_PER_DEG_LON,
            (lat - ORIGIN_LAT) * M_PER_DEG_LAT)


def inside(bbox, lat, lon):
    return bbox[0] <= lat <= bbox[2] and bbox[1] <= lon <= bbox[3]


def stitch(rings):
    """Join way fragments end-to-end into closed rings."""
    frags = [list(r) for r in rings if len(r) >= 2]
    out = []
    while frags:
        cur = frags.pop(0)
        changed = True
        while changed and cur[0] != cur[-1]:
            changed = False
            for i, f in enumerate(frags):
                if f[0] == cur[-1]:
                    cur.extend(f[1:]); frags.pop(i); changed = True; break
                if f[-1] == cur[-1]:
                    cur.extend(reversed(f[:-1])); frags.pop(i); changed = True; break
                if f[-1] == cur[0]:
                    cur = f[:-1] + cur; frags.pop(i); changed = True; break
                if f[0] == cur[0]:
                    cur = list(reversed(f[1:])) + cur; frags.pop(i); changed = True; break
        if cur[0] == cur[-1] and len(cur) > 3:
            out.append(cur)
    return out


def ring_area(pts):
    a = 0.0
    for i in range(len(pts) - 1):
        a += pts[i][0] * pts[i + 1][1] - pts[i + 1][0] * pts[i][1]
    return abs(a) / 2.0


def build(raw):
    nodes, ways, rels = {}, {}, {}
    for e in raw['elements']:
        if e['type'] == 'node':
            prev = nodes.get(e['id'])
            if prev is None or (not prev.get('tags') and e.get('tags')):
                nodes[e['id']] = e
        elif e['type'] == 'way':
            prev = ways.get(e['id'])
            if prev is None or (not prev.get('tags') and e.get('tags')):
                ways[e['id']] = e
        elif e['type'] == 'relation':
            rels[e['id']] = e

    # ---- buildings: ways plus multipolygon relations -------------------
    # Relation members are the reason bat. 18 exists at all; a way-only
    # query silently drops it.
    footprints = []
    for w in ways.values():
        if 'building' not in w.get('tags', {}):
            continue
        pts = [nodes[n] for n in w.get('nodes', []) if n in nodes]
        if len(pts) < 4:
            continue
        footprints.append((w['tags'], [n['id'] for n in pts], pts))
    for r in rels.values():
        if 'building' not in r.get('tags', {}):
            continue
        outer = []
        for m in r.get('members', []):
            if m['type'] == 'way' and m.get('role') in ('outer', ''):
                w = ways.get(m['ref'])
                if w and w.get('nodes'):
                    outer.append(w['nodes'])
        for ring in stitch(outer):
            pts = [nodes[n] for n in ring if n in nodes]
            if len(pts) >= 4:
                footprints.append((r['tags'], ring, pts))

    buildings, ent_owner = [], {}
    for tags, nids, pts in footprints:
        lat = sum(p['lat'] for p in pts) / len(pts)
        lon = sum(p['lon'] for p in pts) / len(pts)
        if not inside(SITE_BBOX, lat, lon):
            continue
        ref = tags.get('ref', '') or ''
        code = None
        if ref.startswith('Bâtiment '):
            code = ref[len('Bâtiment '):].strip()
        ring = [to_xy(p['lat'], p['lon']) for p in pts]
        if ring[0] != ring[-1]:
            ring.append(ring[0])
        lv = tags.get('building:levels')
        try:
            levels = int(float(lv)) if lv else None
        except ValueError:
            levels = None
        b = dict(code=code, name=tags.get('name'), levels=levels,
                 ring=ring, area=ring_area(ring))
        buildings.append(b)
        for n in nids:
            ent_owner.setdefault(n, b)

    # ---- pedestrian graph ---------------------------------------------
    adj = collections.defaultdict(list)
    raw_edges = {}
    for w in ways.values():
        hw = w.get('tags', {}).get('highway')
        if hw not in WEIGHTS:
            continue
        ns = w.get('nodes', [])
        for a, b in zip(ns, ns[1:]):
            na, nb = nodes.get(a), nodes.get(b)
            if not na or not nb:
                continue
            if not (inside(ROUTE_BBOX, na['lat'], na['lon'])
                    and inside(ROUTE_BBOX, nb['lat'], nb['lon'])):
                continue
            pa, pb = to_xy(na['lat'], na['lon']), to_xy(nb['lat'], nb['lon'])
            d = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
            key = (min(a, b), max(a, b))
            if key in raw_edges:
                continue
            raw_edges[key] = (d, WEIGHTS[hw])
            adj[a].append(b)
            adj[b].append(a)

    # ---- entrances -----------------------------------------------------
    entrances = []
    for n in nodes.values():
        kind = n.get('tags', {}).get('entrance')
        if kind not in USABLE_ENTRANCE:
            continue
        owner = ent_owner.get(n['id'])
        if owner is None:
            continue
        entrances.append(dict(node=n['id'], kind=kind, code=owner['code'],
                              p=to_xy(n['lat'], n['lon']), owner=owner))
    return nodes, adj, raw_edges, buildings, entrances


def splice(nodes, adj, raw_edges, entrances):
    """Attach entrances that are not already graph nodes.

    55 of 76 entrances are shared with a footway and need nothing. The
    rest sit on the building outline only, so they are invisible to the
    router until spliced onto the nearest segment.
    """
    synthetic = {}
    # Spliced nodes become splice candidates themselves, so positions have
    # to come from one map rather than from the OSM nodes alone.
    pos = {}
    next_id = -1
    spliced = 0
    for e in entrances:
        if e['node'] in adj:
            continue
        px, py = e['p']
        best = None
        for (a, b) in list(raw_edges):
            d, w = raw_edges[(a, b)]
            ax, ay = pos.get(a) or to_xy(nodes[a]['lat'], nodes[a]['lon'])
            bx, by = pos.get(b) or to_xy(nodes[b]['lat'], nodes[b]['lon'])
            vx, vy = bx - ax, by - ay
            L2 = vx * vx + vy * vy
            t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / L2))
            cx, cy = ax + t * vx, ay + t * vy
            dd = math.hypot(px - cx, py - cy)
            if best is None or dd < best[0]:
                best = (dd, a, b, cx, cy, w)
        if best is None or best[0] > 25.0:
            continue
        dd, a, b, cx, cy, w = best
        # The projection often lands on an endpoint that is already a node.
        # Splitting there would leave a duplicate node and a zero-length edge.
        snap = None
        for end in (a, b):
            ex, ey = pos.get(end) or to_xy(nodes[end]['lat'], nodes[end]['lon'])
            if math.hypot(cx - ex, cy - ey) < 0.5:
                snap = end
                break
        if snap is not None:
            key = (min(snap, e['node']), max(snap, e['node']))
            raw_edges[key] = (max(dd, 0.1), 1.0)
            adj[snap].append(e['node'])
            adj[e['node']].append(snap)
            spliced += 1
            continue
        vid = next_id
        next_id -= 1
        synthetic[vid] = (cx, cy)
        pos[vid] = (cx, cy)
        del raw_edges[(min(a, b), max(a, b))]
        for other in (a, b):
            ox, oy = pos.get(other) or to_xy(nodes[other]['lat'], nodes[other]['lon'])
            raw_edges[(min(vid, other), max(vid, other))] = (
                math.hypot(cx - ox, cy - oy), w)
            adj[vid].append(other)
            adj[other].append(vid)
        raw_edges[(min(vid, e['node']), max(vid, e['node']))] = (dd, 1.0)
        adj[vid].append(e['node'])
        adj[e['node']].append(vid)
        spliced += 1
    return synthetic, spliced


def components(adj):
    seen, comps = set(), []
    for s in adj:
        if s in seen:
            continue
        stack, comp = [s], []
        seen.add(s)
        while stack:
            c = stack.pop()
            comp.append(c)
            for nb in adj[c]:
                if nb not in seen:
                    seen.add(nb)
                    stack.append(nb)
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    return comps


def check_invariants(buildings, entrances, adj, big, place_codes, nodes,
                     unmapped):
    """Every failure here is a routing bug that would only surface in the
    field, on a phone, with a student standing in the rain."""
    errs = []
    by_code = {b['code']: b for b in buildings if b['code']}
    for c in place_codes:
        if c not in by_code and c not in unmapped:
            errs.append('code %s has no footprint' % c)
    ent_by_code = collections.defaultdict(list)
    for e in entrances:
        if e['code']:
            ent_by_code[e['code']].append(e)
    for c in place_codes:
        if c not in by_code:
            continue
        es = ent_by_code.get(c, [])
        if not es:
            errs.append('code %s has no usable entrance' % c)
        elif not any(e['node'] in big for e in es):
            errs.append('code %s has no entrance on the main component' % c)

    # Coverage is only meaningful on the site itself. The route bbox reaches
    # past the campus and picks up fragments we never snap to.
    on_site = [n for n in adj if n in nodes
               and inside(SITE_BBOX, nodes[n]['lat'], nodes[n]['lon'])]
    linked = [n for n in on_site if n in big]
    if on_site and len(linked) / float(len(on_site)) < 0.90:
        errs.append('main component holds only %.1f%% of on-site graph nodes'
                    % (100.0 * len(linked) / len(on_site)))
    return errs, len(on_site), len(linked)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--refresh', action='store_true')
    args = ap.parse_args()

    raw = fetch(args.refresh)
    nodes, adj, raw_edges, buildings, entrances = build(raw)

    with io.open(PLACES, encoding='utf-8') as f:
        place_codes = sorted({p['code'] for p in json.load(f)},
                             key=lambda c: (len(c), c))

    if os.path.exists(OVERRIDES):
        with io.open(OVERRIDES, encoding='utf-8') as f:
            ov = json.load(f)
    else:
        ov = {}
    by_code = {b['code']: b for b in buildings if b['code']}
    for code, patch in (ov.get('levels') or {}).items():
        if code in by_code:
            by_code[code]['levels'] = patch
    for b in ov.get('buildings') or []:
        ring = [to_xy(p[0], p[1]) for p in b['ring']]
        if ring[0] != ring[-1]:
            ring.append(ring[0])
        nb = dict(code=b['code'], name=b.get('name'), levels=b.get('levels'),
                  ring=ring, area=ring_area(ring))
        buildings.append(nb)
        by_code[b['code']] = nb

    synthetic, spliced = splice(nodes, adj, raw_edges, entrances)
    comps = components(adj)
    big = set(comps[0]) if comps else set()

    unmapped = ov.get('unmapped') or {}
    errs, on_site, linked = check_invariants(
        buildings, entrances, adj, big, place_codes, nodes, unmapped)

    # index-addressed graph, main component only: snapping must never be
    # able to land on an island.
    keep = [n for n in adj if n in big]
    idx = {n: i for i, n in enumerate(keep)}
    gnodes = []
    for n in keep:
        if n in synthetic:
            gnodes.append(synthetic[n])
        else:
            gnodes.append(to_xy(nodes[n]['lat'], nodes[n]['lon']))
    gedges = []
    for (a, b), (d, w) in raw_edges.items():
        if a in idx and b in idx:
            gedges.append([idx[a], idx[b], round(d * w, 1)])

    def r1(p):
        return [round(p[0], 1), round(p[1], 1)]

    out = collections.OrderedDict()
    out['version'] = 1
    out['attribution'] = '© OpenStreetMap contributors, ODbL'
    out['origin'] = {'lat': ORIGIN_LAT, 'lon': ORIGIN_LON,
                     'mPerDegLat': round(M_PER_DEG_LAT, 3),
                     'mPerDegLon': round(M_PER_DEG_LON, 3)}
    out['buildings'] = [
        collections.OrderedDict([
            ('code', b['code']), ('name', b['name']), ('levels', b['levels']),
            ('ring', [r1(p) for p in b['ring']]),
        ]) for b in sorted(buildings, key=lambda b: -b['area'])
    ]
    out['entrances'] = [
        collections.OrderedDict([
            ('code', e['code']), ('kind', e['kind']),
            ('node', idx.get(e['node'], -1)), ('p', r1(e['p'])),
        ]) for e in entrances if e['code'] and e['node'] in idx
    ]
    out['graph'] = collections.OrderedDict([
        ('nodes', [r1(p) for p in gnodes]),
        ('edges', gedges),
    ])
    # Codes the map cannot place. The screen says so rather than guessing.
    out['unmapped'] = unmapped

    with io.open(OUT, 'w', encoding='utf-8') as f:
        f.write(json.dumps(out, ensure_ascii=False, separators=(',', ':')))

    size = os.path.getsize(OUT)
    coded = [b for b in buildings if b['code']]
    print('buildings      : %d (%d with an INSA code)' % (len(buildings), len(coded)))
    print('entrances      : %d usable, %d spliced onto the graph' % (len(out['entrances']), spliced))
    print('graph          : %d nodes, %d edges' % (len(gnodes), len(gedges)))
    print('components     : %d, %d of %d on-site nodes linked (%.1f%%)'
          % (len(comps), linked, on_site, 100.0 * linked / max(1, on_site)))
    print('missing levels : %s' % [b['code'] for b in coded if not b['levels']])
    if unmapped:
        print('unmapped codes : %s' % sorted(unmapped))
    print('asset          : %s (%.1f KB)' % (os.path.relpath(OUT, ROOT), size / 1024.0))
    if errs:
        print('\nVALIDATION FAILED:')
        for e in errs:
            print('  - %s' % e)
        return 1
    print('\nvalidation OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
