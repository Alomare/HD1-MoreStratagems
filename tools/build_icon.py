"""Builds the More Stratagems icons: the SEAF Unit's icon, recoloured from the installed game, and two icons
from ready-made PNGs. All three share one material, res/icons.material.

Usage: python tools/build_icon.py [path to Helldivers/contents]

Writes res/icons.material (three sub-materials, SEAF first), res/seaf_unit_icon.texture,
res/homing_payload_icon.texture and res/perforator_turret_icon.texture, all for the boot bundle (see
"resources" in obsidian.json). Also writes internal/icons_preview.png to look at, and
internal/icons_manifest.json with the two new texture resource entries for obsidian.json. Needs Pillow.

The icons are drawn like the game's own: 80x80 uncompressed textures with the mips and header of the Reinforce
icon, and material records copied from the Reinforce's in hud/hud, so the Loadout screen's clip variables and
the HUD's shader are the same. Only each record's name and texture differ. The material's layout is a version
(10), a count, then 13-word records, the same as hud/hud's.
"""
import colorsys
import io
import json
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES, INTERNAL = ROOT / "res", ROOT / "internal"
CONTENTS = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Program Files (x86)\Steam\steamapps\common\Helldivers\contents")
COMMON = "95b2365a6369ee36"  # resource_packages/common, which holds hud/hud
BUNDLE = "9cf71054ea26dddf"  # the boot bundle obsidian.json loads these into

# Keep in step with the Lua that loads these names.
ICON = "seaf_unit_icon"
MATERIAL = "more_stratagems/icons"
TEXTURE = "more_stratagems/seaf_unit_icon"

# The stratagem whose icon is recoloured: the Reinforce, whose icon name is "stratagem_reinforcements"
# (see loadout_settings.lua).
SOURCE = "stratagem_reinforcements"
# The blue stratagem whose icon's blue the Reinforce icon takes.
REFERENCE = "stratagem_resupply"

# The icons drawn from PNGs, after the SEAF's in the material: (icon name, texture name, PNG).
PNG_ICONS = [
    ("homing_payload_icon", "more_stratagems/homing_payload_icon", Path(r"C:\Users\vps26\Downloads\homingpayload.png")),
    ("perforator_turret_icon", "more_stratagems/perforator_turret_icon", Path(r"C:\Users\vps26\Downloads\penetratorturret.png")),
]

# Vanilla icons for the preview, by their texture's name hash, both on a coloured background box like the
# stratagem tiles: a red-brown offensive one (stratagem_missile_strike, hud/hud record 075a50e5) and an olive
# green one (hud/hud record 7b8ab5ca, its stratagem name not known here).
PREVIEW_RED = 0xcde05b6f3c278e3e
PREVIEW_GREEN = 0x8eb0c6e73be4bc22

MATERIAL_VERSION = 10
DIFFUSE_MAP = 0x3aa8b87e
RECORD_WORDS = 13
ICON_SIZE = (80, 80)


def murmur64(data, seed=0):
    m, r, mask = 0xc6a4a7935bd1e995, 47, (1 << 64) - 1
    h = (seed ^ (len(data) * m)) & mask
    tail = len(data) & ~7
    for (k,) in struct.iter_unpack("<Q", data[:tail]):
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    rest = data[tail:]
    if rest:
        h = ((h ^ int.from_bytes(rest, "little")) * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    return h ^ (h >> r)


def bundle_entries(path):
    """A bundle's resources: (type, name, data of the first variant)."""
    data = path.read_bytes()
    if len(data) < 12 or struct.unpack_from("<I", data, 0)[0] != 0xF0000004:
        raise SystemExit(f"not a bundle: {path}")
    total = struct.unpack_from("<I", data, 4)[0]
    raw, pos = bytearray(), 12
    while pos < len(data) and len(raw) < total:
        (size,) = struct.unpack_from("<I", data, pos)
        pos += 4
        chunk = data[pos:pos + size]
        pos += size
        raw += chunk if size == 0x10000 else zlib.decompress(chunk)
    (count,) = struct.unpack_from("<I", raw, 0)
    pos = 260 + count * 16
    for _ in range(count):
        kind, name, variants, _ = struct.unpack_from("<QQII", raw, pos)
        pos += 24
        heads = [struct.unpack_from("<III", raw, pos + 12 * i) for i in range(variants)]
        pos += 12 * variants
        first = None
        for _, size, _ in heads:
            if first is None:
                first = bytes(raw[pos:pos + size])
            pos += size
        yield kind, name, first


def game_icons():
    """hud/hud's records for the Reinforce and the blue reference stratagem, their textures' raw bytes, and every
    texture in the common bundle by name hash."""
    material, texture = murmur64(b"material"), murmur64(b"texture")
    hud = murmur64(b"hud/hud")
    entries = list(bundle_entries(CONTENTS / COMMON))
    data = next(d for k, n, d in entries if k == material and n == hud)
    words = struct.unpack_from("<%dI" % (len(data) // 4), data, 0)
    records = {}
    for name in (SOURCE, REFERENCE):
        at = words.index(murmur64(name.encode()) >> 32)
        record = words[at:at + RECORD_WORDS]
        if record[5] != DIFFUSE_MAP:
            raise SystemExit(f"{name}: not the record layout this tool knows")
        records[name] = record
    textures = {n: d for k, n, d in entries if k == texture}
    tex = {name: textures[r[6] | (r[7] << 32)] for name, r in records.items()}
    return records, tex, textures


def sample_tone(image, low, high):
    """The most common opaque colour of the image whose value is in [low, high), pure white aside."""
    counts = Counter()
    for r, g, b, a in image.getdata():
        if a < 128 or (r, g, b) == (255, 255, 255):
            continue
        v = max(r, g, b) / 255
        if low <= v < high:
            counts[(r, g, b)] += 1
    return counts.most_common(1)[0][0]


# The Reinforce's own tones, by value (max channel / 255): its outline (150, 110, 40) at 0.59, its gold
# background (200, 160, 75) at 0.78, its back figures' shade (243, 201, 124) at 0.95 and its front
# figure's cream (255, 235, 207) at 1.0.
SOURCE_TONES = [0.59, 0.78, 0.95, 1.0]


def recolour(icon, reference):
    """Maps the Reinforce's tones onto the Resupply's: outline to its edge, gold background to its teal,
    and the cream figures to its bullets' grey-blue, the front one brightest. Near-white stays white."""
    edge = sample_tone(reference, 0.0, 0.25)
    background = sample_tone(reference, 0.3, 0.5)
    shade = sample_tone(reference, 0.5, 0.65)
    light = sample_tone(reference, 0.7, 1.0)
    print("sampled edge", edge, "background", background, "bullet shade", shade, "bullet light", light)
    anchors = list(zip(SOURCE_TONES, [edge, background, shade, light]))

    def mapped(value):
        if value <= anchors[0][0]:
            return anchors[0][1]
        for (v0, c0), (v1, c1) in zip(anchors, anchors[1:]):
            if value <= v1:
                t = (value - v0) / (v1 - v0)
                return tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
        return anchors[-1][1]

    w, h = icon.size
    out = icon.copy()
    po = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = po[x, y]
            if a == 0:
                continue
            if x in (0, w - 1) or y in (0, h - 1):
                # The border matches the reference's edge.
                po[x, y] = (*edge, a)
                continue
            v = max(r, g, b) / 255
            if min(r, g, b) > 230 and max(r, g, b) - min(r, g, b) < 40:
                # Near-white highlights (the plus) stay white, as the mission icons' highlights do.
                continue
            po[x, y] = (*mapped(v), a)
    return out


def load_png(path):
    """A PNG as an 80x80 RGBA icon, resized with Lanczos. The colours are kept as given. The resize runs on
    premultiplied alpha, so transparent pixels don't bleed their colour into the edges."""
    image = Image.open(path)
    print(f"{path.name}: original size {image.size[0]}x{image.size[1]}, mode {image.mode}")
    return image.convert("RGBa").resize(ICON_SIZE, Image.Resampling.LANCZOS).convert("RGBA")


def texture(header_from, image):
    """The game's layout: the Reinforce texture's DDS header, BGRA mips, and its four byte tail."""
    height, width = struct.unpack_from("<II", header_from, 12)
    mips = struct.unpack_from("<I", header_from, 28)[0]
    fourcc, bits = header_from[84:88], struct.unpack_from("<I", header_from, 88)[0]
    if (width, height) != image.size or fourcc != bytes(4) or bits != 32:
        raise SystemExit("the Reinforce's texture isn't the uncompressed 32 bit image this tool knows")
    levels, size = [], image.size
    level = image
    for _ in range(mips):
        levels.append(level.tobytes("raw", "BGRA"))
        size = (max(1, size[0] // 2), max(1, size[1] // 2))
        level = level.resize(size, Image.Resampling.BOX)
    body = b"".join(levels)
    if 128 + len(body) + 4 != len(header_from):
        raise SystemExit("the Reinforce's texture has a layout this tool doesn't know")
    return header_from[:128] + body + header_from[-4:]


def material(entries, source_record):
    """The material file: version, count, then one record per (icon name, texture name), each a copy of the
    Reinforce's record with its name and texture changed."""
    body = b""
    for icon, texture_name in entries:
        tex = murmur64(texture_name.encode())
        record = list(source_record)
        record[0] = murmur64(icon.encode()) >> 32
        record[6], record[7] = tex & 0xffffffff, tex >> 32
        body += struct.pack("<%dI" % RECORD_WORDS, *record)
    return struct.pack("<II", MATERIAL_VERSION, len(entries)) + body


def check_material(data, entries):
    """Reads the material back and checks its count and each record's sub-material and texture name hashes
    against the names it should hold."""
    version, count = struct.unpack_from("<II", data, 0)
    if version != MATERIAL_VERSION or count != len(entries) or len(data) != 8 + count * RECORD_WORDS * 4:
        raise SystemExit(f"icons.material: version {version}, count {count}, {len(data)} bytes; expected {len(entries)} records")
    for i, (icon, texture_name) in enumerate(entries):
        words = struct.unpack_from("<%dI" % RECORD_WORDS, data, 8 + i * RECORD_WORDS * 4)
        if words[0] != murmur64(icon.encode()) >> 32:
            raise SystemExit(f"icons.material record {i}: sub-material name does not hash to {icon}")
        if words[6] | (words[7] << 32) != murmur64(texture_name.encode()):
            raise SystemExit(f"icons.material record {i}: texture name does not hash to {texture_name}")
        print(f"record {i}: {icon} -> {texture_name}, hashes match")


def preview(tiles, scale=3, gap=16, split=32):
    """The icons side by side, with a wider gap before the vanilla ones (the last two)."""
    w, h = ICON_SIZE[0] * scale, ICON_SIZE[1] * scale
    width = len(tiles) * w + (len(tiles) - 1) * gap + (split - gap)
    sheet = Image.new("RGBA", (width, h), (30, 30, 30, 255))
    x = 0
    for i, tile in enumerate(tiles):
        if i == len(tiles) - 2:
            x += split - gap
        sheet.paste(tile.resize((w, h), Image.Resampling.NEAREST), (x, 0))
        x += w + gap
    return sheet


def main():
    records, tex, textures = game_icons()
    source_record = records[SOURCE]
    source = Image.open(io.BytesIO(tex[SOURCE])).convert("RGBA")
    reference = Image.open(io.BytesIO(tex[REFERENCE])).convert("RGBA")
    seaf = recolour(source, reference)
    RES.mkdir(exist_ok=True)
    INTERNAL.mkdir(exist_ok=True)

    # The SEAF's texture is written from the Reinforce's header, as before.
    (RES / f"{ICON}.texture").write_bytes(texture(tex[SOURCE], seaf))
    tiles = [seaf]
    entries = [(ICON, TEXTURE)]
    new = []
    for icon, texture_name, path in PNG_ICONS:
        image = load_png(path)
        (RES / f"{icon}.texture").write_bytes(texture(tex[SOURCE], image))
        tiles.append(image)
        entries.append((icon, texture_name))
        new.append({"type": "texture", "name": texture_name, "bundle": BUNDLE, "data": f"res/{icon}.texture"})

    data = material(entries, source_record)
    check_material(data, entries)
    (RES / "icons.material").write_bytes(data)

    # Vanilla red (offensive) and green (defensive) icons, for comparing colours.
    tiles.append(Image.open(io.BytesIO(textures[PREVIEW_RED])).convert("RGBA"))
    tiles.append(Image.open(io.BytesIO(textures[PREVIEW_GREEN])).convert("RGBA"))
    preview(tiles).save(INTERNAL / "icons_preview.png")
    (INTERNAL / "icons_manifest.json").write_text(json.dumps(new, indent=2) + "\n", encoding="utf-8")
    print("wrote", RES / "icons.material", ", ".join(f"res/{i}.texture" for i, _ in entries))


if __name__ == "__main__":
    main()
