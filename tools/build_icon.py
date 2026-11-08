"""Builds the Reinforce stratagem's icon from the installed game: the Reinforce icon recoloured to the blue of
the regular supply stratagems, such as the Resupply.

Usage: python tools/build_icon.py [path to Helldivers/contents]

Writes res/icons.material and res/seaf_unit_icon.texture, both for the boot bundle (see "resources" in
obsidian.json), and internal/seaf_unit_icon_preview.png to look at. Needs Pillow.

The icon is drawn like the game's own: an 80x80 uncompressed texture with two mips, in the Reinforce
icon's header, and a material record copied from the Reinforce's in hud/hud, so the Loadout screen's clip
variables and the HUD's shader are the same. Only its name and texture differ.
"""
import colorsys
import io
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

# Keep in step with the Lua that loads these names.
ICON = "seaf_unit_icon"
MATERIAL = "more_stratagems/icons"
TEXTURE = "more_stratagems/seaf_unit_icon"

# The stratagem whose icon is recoloured: the Reinforce, whose icon name is "stratagem_reinforcements"
# (see loadout_settings.lua).
SOURCE = "stratagem_reinforcements"
# The blue stratagem whose icon's blue the Reinforce icon takes.
REFERENCE = "stratagem_resupply"

MATERIAL_VERSION = 10
DIFFUSE_MAP = 0x3aa8b87e
RECORD_WORDS = 13


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
    """hud/hud's records for the Reinforce and the blue reference stratagem, and their textures' raw bytes."""
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
    return records, tex


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


def material(source_record):
    tex = murmur64(TEXTURE.encode())
    record = list(source_record)
    record[0] = murmur64(ICON.encode()) >> 32
    record[6], record[7] = tex & 0xffffffff, tex >> 32
    return struct.pack("<II", MATERIAL_VERSION, 1) + struct.pack("<%dI" % RECORD_WORDS, *record)


def main():
    records, tex = game_icons()
    source = Image.open(io.BytesIO(tex[SOURCE])).convert("RGBA")
    reference = Image.open(io.BytesIO(tex[REFERENCE])).convert("RGBA")
    icon = recolour(source, reference)
    RES.mkdir(exist_ok=True)
    INTERNAL.mkdir(exist_ok=True)
    (RES / "seaf_unit_icon.texture").write_bytes(texture(tex[SOURCE], icon))
    (RES / "icons.material").write_bytes(material(records[SOURCE]))
    w, h = icon.size
    preview = Image.new("RGBA", (w * 12 + 32, h * 4), (30, 30, 30, 255))
    preview.paste(source.resize((w * 4, h * 4), Image.Resampling.NEAREST), (0, 0))
    preview.paste(icon.resize((w * 4, h * 4), Image.Resampling.NEAREST), (w * 4 + 16, 0))
    preview.paste(reference.resize((w * 4, h * 4), Image.Resampling.NEAREST), (w * 8 + 32, 0))
    preview.save(INTERNAL / "seaf_unit_icon_preview.png")
    print("wrote", RES / "seaf_unit_icon.texture", RES / "icons.material")


if __name__ == "__main__":
    main()
