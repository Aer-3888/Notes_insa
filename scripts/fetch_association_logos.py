#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Bake the association logo assets from the AEIR club images.

Run by hand; the output is committed. Usage:

    python scripts/fetch_association_logos.py            # use cached downloads
    python scripts/fetch_association_logos.py --refresh  # re-download

Emits assets/images/associations/<id>.webp and the generated id set in
lib/modules/associations/association_logo_assets.dart. Fails loudly if the
baked assets would not draw correctly in a circular slot; see check_invariants.

The sources are not a coherent set: some carry their own opaque background in
any colour, some are a transparent mark on a mostly empty canvas, a third are
not square, and a few are 3000 px. Drawn straight into a circle they give a
coloured band across a grey disc. Normalising them here means the app draws a
square that already fills its slot.
"""

import argparse
import collections
import io
import json
import os
import sys
import urllib.error
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, '.association_logos_cache')
DATA = os.path.join(ROOT, 'assets', 'data', 'associations.json')
OUT_DIR = os.path.join(ROOT, 'assets', 'images', 'associations')
OUT_DART = os.path.join(
    ROOT, 'lib', 'modules', 'associations', 'association_logo_assets.dart')
ASSET_DIR = 'assets/images/associations'

TIMEOUT = 30
USER_AGENT = 'notes-insa-logo-baker/1 (+https://github.com/Aer-3888)'

# Longest side of the baked square, in pixels. The largest slot is 56 dp, so
# this covers a 3x screen with headroom.
TARGET = 192

# Breathing room around the artwork, as a fraction of its longest side.
INSET = 0.08

# The circle clips the corners of the square, so trimmed artwork is shrunk
# until its farthest ink sits inside this fraction of the radius.
INK_RADIUS = 0.98

# A pixel counts as opaque above this alpha, a border above this fraction.
OPAQUE_ALPHA = 200
OPAQUE_BORDER = 0.9

# How far a border pixel may drift from the background colour and still be
# treated as margin worth trimming.
BG_TOLERANCE = 6

WEBP_QUALITY = 88
MAX_TOTAL_BYTES = 1024 * 1024


def associations():
    with io.open(DATA, encoding='utf-8') as f:
        return json.load(f)['associations']


def fetch(rows, refresh):
    """Raw bytes per id, None for a URL the host does not serve."""
    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)
    out = collections.OrderedDict()
    for row in rows:
        url = row.get('logoUrl')
        if not url:
            continue
        path = os.path.join(CACHE, row['id'])
        if not refresh and os.path.exists(path):
            with io.open(path, 'rb') as f:
                raw = f.read()
            out[row['id']] = raw or None
            continue
        try:
            request = urllib.request.Request(
                url, headers={'User-Agent': USER_AGENT})
            raw = urllib.request.urlopen(request, timeout=TIMEOUT).read()
        except (urllib.error.URLError, OSError) as e:
            print('  %-22s %s' % (row['id'], e))
            raw = b''
        with io.open(path, 'wb') as f:
            f.write(raw)
        out[row['id']] = raw or None
    return out


def border_pixels(im):
    w, h = im.size
    px = im.load()
    return ([px[x, 0] for x in range(w)] + [px[x, h - 1] for x in range(w)]
            + [px[0, y] for y in range(h)] + [px[w - 1, y] for y in range(h)])


def carries_background(border):
    """Whether the image already supplies its own background.

    Asked of the original, never of a trimmed copy: trimming removes the
    transparent margin, after which a mark that fills its own bounding box has
    opaque corners and would read as already backed.
    """
    opaque = sum(1 for p in border if p[3] >= OPAQUE_ALPHA)
    return opaque >= OPAQUE_BORDER * len(border)


def background_colour(border):
    counts = collections.Counter(p[:3] for p in border
                                 if p[3] >= OPAQUE_ALPHA)
    return counts.most_common(1)[0][0]


def near(a, b):
    return all(abs(a[i] - b[i]) <= BG_TOLERANCE for i in range(3))


def trim_opaque(im, bg):
    """Crop the uniform margin of [bg] off an image that has no alpha to use."""
    w, h = im.size
    px = im.load()
    left, right, top, bottom = 0, w - 1, 0, h - 1
    while left < right and all(near(px[left, y], bg) for y in range(h)):
        left += 1
    while right > left and all(near(px[right, y], bg) for y in range(h)):
        right -= 1
    while top < bottom and all(near(px[x, top], bg) for x in range(w)):
        top += 1
    while bottom > top and all(near(px[x, bottom], bg) for x in range(w)):
        bottom -= 1
    return im.crop((left, top, right + 1, bottom + 1))


def ink_radius(art, bg):
    """Distance from the centre to the farthest ink pixel, in pixels."""
    w, h = art.size
    px = art.load()
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    best = 0.0
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[3] < 16:
                continue
            if bg is not None and near(p, bg) and p[3] >= OPAQUE_ALPHA:
                continue
            best = max(best, ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5)
    return best


def trim_alpha(im):
    alpha = im.getchannel('A').point(lambda v: 255 if v > 10 else 0)
    box = alpha.getbbox()
    return im.crop(box) if box else None


def normalise(raw):
    """A [TARGET] square that fills a circular slot, and how it was built."""
    im = Image.open(io.BytesIO(raw)).convert('RGBA')
    source = im.size
    border = border_pixels(im)
    backed = carries_background(border)

    if backed:
        bg = background_colour(border) + (255,)
        art = trim_opaque(im, bg[:3])
    else:
        bg = (0, 0, 0, 0)
        art = trim_alpha(im)
        if art is None:
            return None, None

    bleed = backed and art.size == im.size
    longest = max(art.size)
    if bleed:
        scale = float(TARGET) / longest
    else:
        scale = (TARGET / (1.0 + 2.0 * INSET)) / longest
        radius = ink_radius(art, bg[:3] if backed else None)
        if radius > 0:
            scale = min(scale, INK_RADIUS * (TARGET / 2.0) / radius)

    drawn = (max(1, int(round(art.width * scale))),
             max(1, int(round(art.height * scale))))
    square = Image.new('RGBA', (TARGET, TARGET), bg)
    square.alpha_composite(
        art.resize(drawn, Image.Resampling.LANCZOS),
        ((TARGET - drawn[0]) // 2, (TARGET - drawn[1]) // 2))

    buffer = io.BytesIO()
    square.save(buffer, 'WEBP', quality=WEBP_QUALITY, method=6)
    return buffer.getvalue(), {
        'source': source,
        'backed': backed,
        'bleed': bleed,
        'bg': bg[:3] if backed else None,
        'trimmed': art.size,
        'drawn': drawn,
    }


def build(downloads):
    """Baked bytes, how each was built, and the ids that produced nothing."""
    baked = collections.OrderedDict()
    meta = collections.OrderedDict()
    missing = []
    unreadable = []
    for asso_id, raw in downloads.items():
        if raw is None:
            missing.append(asso_id)
            continue
        try:
            encoded, info = normalise(raw)
        except Exception as e:  # noqa: BLE001 - report, never abort the batch
            unreadable.append('%s (%s)' % (asso_id, e))
            continue
        if encoded is None:
            unreadable.append('%s (fully transparent)' % asso_id)
            continue
        baked[asso_id] = encoded
        meta[asso_id] = info
    return baked, meta, missing, unreadable


def check_invariants(rows, baked):
    errs = []
    known = {row['id'] for row in rows}
    for asso_id, encoded in baked.items():
        if asso_id not in known:
            errs.append('%s is not an association in associations.json'
                        % asso_id)
        with Image.open(io.BytesIO(encoded)) as im:
            if im.size != (TARGET, TARGET):
                errs.append('%s baked at %dx%d, not %dx%d'
                            % ((asso_id,) + im.size + (TARGET, TARGET)))

    on_disk = set()
    if os.path.isdir(OUT_DIR):
        on_disk = {os.path.splitext(n)[0] for n in os.listdir(OUT_DIR)
                   if n.endswith('.webp')}
    for stale in sorted(on_disk - set(baked)):
        errs.append('%s.webp is on disk but was not baked by this run' % stale)

    total = sum(len(e) for e in baked.values())
    if total > MAX_TOTAL_BYTES:
        errs.append('assets total %.1f KB, over the %.1f KB budget'
                    % (total / 1024.0, MAX_TOTAL_BYTES / 1024.0))
    if not baked:
        errs.append('no logo was baked at all')
    return errs


def write_assets(baked):
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    for name in os.listdir(OUT_DIR):
        if name.endswith('.webp') and os.path.splitext(name)[0] not in baked:
            os.remove(os.path.join(OUT_DIR, name))
    for asso_id, encoded in baked.items():
        with io.open(os.path.join(OUT_DIR, '%s.webp' % asso_id), 'wb') as f:
            f.write(encoded)


def dart_string(value):
    """[value] as the body of a single-quoted Dart string literal."""
    return value.replace('\\', r'\\').replace("'", r"\'").replace('$', r'\$')


def write_dart(baked, urls):
    lines = [
        '// GENERATED by scripts/fetch_association_logos.py.',
        '// Do not edit by hand; re-run the script instead.',
        '',
        '/// The logo each bundled asset under `assets/images/associations/` was',
        '/// baked from, by association id. An association absent here falls back',
        '/// to its initials, so a dead upstream URL costs no network call; one',
        '/// whose logo has since moved falls back to the remote image, because a',
        '/// baked file is only the normalised form of the URL it came from.',
        'const Map<String, String> kBundledAssociationLogos = <String, String>{',
    ]
    for asso_id in sorted(baked):
        entry = "  '%s': '%s'," % (asso_id, dart_string(urls[asso_id]))
        # dart format wraps at 80, and the output has to survive `dart format
        # --set-exit-if-changed` or every run of this script churns the file.
        if len(entry) > 80:
            entry = "  '%s':\n      '%s'," % (asso_id,
                                              dart_string(urls[asso_id]))
        lines.append(entry)
    lines += ['};', '']
    with io.open(OUT_DART, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--refresh', action='store_true')
    args = ap.parse_args()

    rows = associations()
    print('downloading (cache: %s)' % os.path.relpath(CACHE, ROOT))
    downloads = fetch(rows, args.refresh)
    baked, meta, missing, unreadable = build(downloads)
    errs = check_invariants(rows, baked)

    if not errs:
        write_assets(baked)
        write_dart(baked, {row['id']: row['logoUrl'] for row in rows
                           if row.get('logoUrl')})

    backed = [i for i in baked if meta[i]['backed']]
    bleed = [i for i in baked if meta[i]['bleed']]
    total = sum(len(e) for e in baked.values())
    biggest = sorted(baked, key=lambda i: len(baked[i]), reverse=True)[:3]
    print()
    print('associations   : %d (%d with a logoUrl)' % (len(rows),
                                                       len(downloads)))
    print('baked          : %d (%d backed, %d transparent marks, %d full bleed)'
          % (len(baked), len(backed), len(baked) - len(backed), len(bleed)))
    print('assets         : %s (%.1f KB, largest %s)'
          % (os.path.relpath(OUT_DIR, ROOT), total / 1024.0,
             ', '.join('%s %.1f KB' % (i, len(baked[i]) / 1024.0)
                       for i in biggest)))
    print('generated      : %s' % os.path.relpath(OUT_DART, ROOT))
    if missing:
        print('not served     : %s' % ', '.join(sorted(missing)))
    if unreadable:
        print('unreadable     : %s' % ', '.join(sorted(unreadable)))

    if errs:
        print('\nVALIDATION FAILED:')
        for e in errs:
            print('  - %s' % e)
        return 1
    print('\nvalidation OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
