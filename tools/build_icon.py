"""Builds the A/AC-90 Repair Tower's icon from the installed game: the Tesla Tower's icon with its two
lightning bolts swapped for the REP-80's heart.

Usage: python tools/build_icon.py [path to Helldivers/contents]

Writes res/icons.material and res/repair_tower_icon.texture, both for the boot bundle (see "resources"
in obsidian.json), and internal/icon_preview.png to look at. Needs Pillow.

The icon is drawn like the game's own: an 80x80 uncompressed texture with two mips, in the Tesla
Tower's header, and a material record copied from the Tesla Tower's in hud/hud, so the Loadout
screen's clip variables and the HUD's shader are the same. Only its name and texture differ.
"""
import io
import struct
import sys
import zlib
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES, INTERNAL = ROOT / "res", ROOT / "internal"
CONTENTS = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Program Files (x86)\Steam\steamapps\common\Helldivers\contents")
COMMON = "95b2365a6369ee36"  # resource_packages/common, which holds hud/hud

# Keep in step with src/repair_tower.lua.
ICON = "remixed_repair_tower_icon"
MATERIAL = "remixed_stratagems/icons"
TEXTURE = "remixed_stratagems/repair_tower_icon"

MATERIAL_VERSION = 10
DIFFUSE_MAP = 0x3aa8b87e
RECORD_WORDS = 13
# The heart, in the REP-80 icon's pixels, and the size it's drawn at in place of each bolt.
HEART_BOX = (11, 27, 54, 64)
HEART_SIZE = (22, 19)


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
    """hud/hud's records for the Tesla Tower and the REP-80, and their textures' raw bytes."""
    material, texture = murmur64(b"material"), murmur64(b"texture")
    hud = murmur64(b"hud/hud")
    entries = list(bundle_entries(CONTENTS / COMMON))
    data = next(d for k, n, d in entries if k == material and n == hud)
    words = struct.unpack_from("<%dI" % (len(data) // 4), data, 0)
    records = {}
    for name in ("stratagem_tesla_tower", "stratagem_repairtool"):
        at = words.index(murmur64(name.encode()) >> 32)
        record = words[at:at + RECORD_WORDS]
        if record[5] != DIFFUSE_MAP:
            raise SystemExit(f"{name}: not the record layout this tool knows")
        records[name] = record
    textures = {n: d for k, n, d in entries if k == texture}
    tex = {name: textures[r[6] | (r[7] << 32)] for name, r in records.items()}
    return records, tex


def shapes(image, background, border):
    """The image's shapes, 8-connected, inside its 1px border: [(pixels, (x0, y0, x1, y1))]."""
    w, h = image.size
    px = image.load()
    seen, out = set(), []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if (x, y) in seen or px[x, y] in (background, border):
                continue
            todo, pts = deque([(x, y)]), []
            seen.add((x, y))
            while todo:
                cx, cy = todo.popleft()
                pts.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        n = (cx + dx, cy + dy)
                        if 1 <= n[0] < w - 1 and 1 <= n[1] < h - 1 and n not in seen and px[n] not in (background, border):
                            seen.add(n)
                            todo.append(n)
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            out.append((pts, (min(xs), min(ys), max(xs), max(ys))))
    return out


def draw(tesla, rep):
    w, h = tesla.size
    background, border = tesla.getpixel((w // 2, 3)), tesla.getpixel((0, 0))
    # The bolts: the shapes wholly in the top third, clear of the tower in the middle.
    bolts = [s for s in shapes(tesla, background, border) if s[1][3] < h // 3 + 2 and (s[1][2] < w * 0.36 or s[1][0] > w * 0.62)]
    if len(bolts) != 2:
        raise SystemExit(f"expected the Tesla Tower icon's two bolts, found {len(bolts)}")
    out = tesla.copy()
    px = out.load()
    for pts, _ in bolts:
        for p in pts:
            px[p] = background
    # The heart: the REP-80 icon's white, which its gear behind never is.
    x0, y0, x1, y1 = HEART_BOX
    mask = Image.new("L", (x1 - x0 + 1, y1 - y0 + 1), 0)
    rp, mp = rep.load(), mask.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if min(rp[x, y][:3]) > 200:
                mp[x - x0, y - y0] = 255
    heart = mask.resize(HEART_SIZE, Image.Resampling.LANCZOS)
    white = Image.new("RGBA", HEART_SIZE, (255, 255, 255, 255))
    for _, (bx0, by0, bx1, by1) in bolts:
        out.paste(white, ((bx0 + bx1) // 2 - HEART_SIZE[0] // 2, (by0 + by1) // 2 - HEART_SIZE[1] // 2), heart)
    return out


def texture(header_from, image):
    """The game's layout: the Tesla Tower texture's DDS header, BGRA mips, and its four byte tail."""
    height, width = struct.unpack_from("<II", header_from, 12)
    mips = struct.unpack_from("<I", header_from, 28)[0]
    fourcc, bits = header_from[84:88], struct.unpack_from("<I", header_from, 88)[0]
    if (width, height) != image.size or fourcc != bytes(4) or bits != 32:
        raise SystemExit("the Tesla Tower's texture isn't the uncompressed 32 bit image this tool knows")
    levels, size = [], image.size
    level = image
    for _ in range(mips):
        levels.append(level.tobytes("raw", "BGRA"))
        size = (max(1, size[0] // 2), max(1, size[1] // 2))
        level = level.resize(size, Image.Resampling.BOX)
    body = b"".join(levels)
    if 128 + len(body) + 4 != len(header_from):
        raise SystemExit("the Tesla Tower's texture has a layout this tool doesn't know")
    return header_from[:128] + body + header_from[-4:]


def material(tesla_record):
    tex = murmur64(TEXTURE.encode())
    record = list(tesla_record)
    record[0] = murmur64(ICON.encode()) >> 32
    record[6], record[7] = tex & 0xffffffff, tex >> 32
    return struct.pack("<II", MATERIAL_VERSION, 1) + struct.pack("<%dI" % RECORD_WORDS, *record)


def main():
    records, tex = game_icons()
    tesla = Image.open(io.BytesIO(tex["stratagem_tesla_tower"])).convert("RGBA")
    rep = Image.open(io.BytesIO(tex["stratagem_repairtool"])).convert("RGBA")
    icon = draw(tesla, rep)
    RES.mkdir(exist_ok=True)
    INTERNAL.mkdir(exist_ok=True)
    (RES / "repair_tower_icon.texture").write_bytes(texture(tex["stratagem_tesla_tower"], icon))
    (RES / "icons.material").write_bytes(material(records["stratagem_tesla_tower"]))
    w, h = icon.size
    preview = Image.new("RGBA", (w * 8 + 16, h * 4), (30, 30, 30, 255))
    preview.paste(tesla.resize((w * 4, h * 4), Image.Resampling.NEAREST), (0, 0))
    preview.paste(icon.resize((w * 4, h * 4), Image.Resampling.NEAREST), (w * 4 + 16, 0))
    preview.save(INTERNAL / "icon_preview.png")
    print("wrote", RES / "repair_tower_icon.texture", RES / "icons.material")


if __name__ == "__main__":
    main()
