"""Builds the SEAF Unit's armour set from the installed game: the default Helldiver helmet, body and cape,
recoloured (yellow to blue, black to a very dark blue), as resources of their own.

Usage: python tools/build_armor.py [path to Helldivers/contents]

Writes res/armor/, internal/armor_manifest.json (the "resources" entries and the "custom_armor" option to
merge into obsidian.json) and internal/seaf_armor_preview.png. Needs numpy and Pillow.

How a piece is made, as the sky units of Photo Mode are:

  unit      a copy of the game's unit whose only change is the 8 byte name of the material, held 16 bytes from
            the end (the Snow variants keep their material there too).
  bones     a copy of the unit's bones resource. The game keeps one under the unit's own name, and
            UnitAux.skin_item reads the unit's bones to link the piece to the Helldiver.
  material  a copy of the game's material with the names of the colour textures swapped for new ones.
  texture   the colour atlases, recoloured here and written in the original's format, size, mips and tail.

Every other texture the materials use (normal maps, the mask, the skin) is copied under a new name too, so
the whole set stands alone in the boot bundle, which is loaded from the start and never unloads. The game's
own pieces and textures are not touched, so other players' armour stays as it is.
"""
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stingray as st  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
RES, INTERNAL = ROOT / "res" / "armor", ROOT / "internal"
if len(sys.argv) > 1:
    st.CONTENTS = Path(sys.argv[1])

SOURCE = "68e5a323f59aa64c"   # resource_packages/mission_common: every default piece is in it
BOOT = "9cf71054ea26dddf"     # foundation: loaded first, never unloads
PREFIX = "more_stratagems/armor/"
OPTION = "custom_armor"

DIFFUSE_MAP = 0x3aa8b87e      # murmur32("diffuse_map"), the variable a material names a colour texture by
UNIT, BONES, MATERIAL, TEXTURE = (st.murmur64(t) for t in ("unit", "bones", "material", "texture"))

CHARS = "characters/helldiver_private_01/"
# Each piece: the new files, the game's units copied, and the colour atlases (by the name hash the game's
# material gives them) that are recoloured, with the look each gets. The body has two: the armour atlas,
# and the small one of the helmet slot. The skin texture stays as it is.
PIECES = [
    {"key": "helmet", "material": "seaf_helmet",
     "units": {"seaf_helmet": CHARS + "helldiver_default_helmet_01"},
     "atlases": {0x337b8cce7cfbbc69: ("helmet_diffuse", "helmet")}},
    {"key": "body", "material": "seaf_body",
     "units": {"seaf_body_male": CHARS + "helldiver_default_male_01",
               "seaf_body_female": CHARS + "helldiver_default_female_01"},
     "atlases": {0x1caeba1e7d785bc0: ("body_diffuse", "body"), 0x1d99cca6c104bbc8: ("body_head_diffuse", "body")}},
    {"key": "cape", "material": "seaf_cape",
     "units": {"seaf_cape": CHARS + "helldiver_default_cape_01"},
     "atlases": {0xb869c7c0d0346ca9: ("cape_diffuse", "cape")}},
]


# ---- colour ---------------------------------------------------------------------------------------------

def to_hsv(rgb):
    """rgb in 0..1, shape (..., 3); hue in degrees."""
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    safe = np.where(d == 0, 1, d)
    h = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) * 60
    h = np.where(d == 0, 0, h)
    s = np.where(mx == 0, 0, d / np.where(mx == 0, 1, mx))
    return h, s, mx


def from_hsv(h, s, v):
    h = (h % 360) / 60
    c = v * s
    x = c * (1 - np.abs(h % 2 - 1))
    z = np.zeros_like(h)
    sector = np.floor(h).astype(int) % 6
    r = np.choose(sector, [c, x, z, z, x, c])
    g = np.choose(sector, [x, c, c, x, z, z])
    b = np.choose(sector, [z, z, x, c, c, x])
    m = v - c
    return np.stack([r + m, g + m, b + m], -1)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# The scheme: the default Helldiver with the yellow turned blue and the black turned a very dark blue. Every
# other colour (white, grey, skin, metal, decals) and all shading stay as the game has them.
YELLOW_OUT_HUE = 218.0        # where the middle of the yellow band lands
YELLOW_CENTRE = 45.0          # the middle of the game's yellow
YELLOW_SPREAD = 0.45          # how much of the yellow's own hue spread is kept, so shaded gold stays a little different
DARK_HUE, DARK_SAT = 222.0, 0.85
DARK_LIFT = 0.09              # added to the value, so the darkest pixel is blue rather than black
# Value below which a pixel counts as black (full blend) and above which it is untouched, per look. The cape
# is cloth all over, between 0.09 and 0.2, with a light emblem above 0.4.
DARK_RANGE = {"helmet": (0.12, 0.22), "body": (0.12, 0.22), "cape": (0.30, 0.40)}


def masks(rgb, look):
    """(yellow weight, black weight, hue, saturation, value), the weights 0..1 per pixel."""
    h, s, v = to_hsv(rgb)
    # Yellow: hue 28..66 (fading out to 20 and 80), saturated. Skin sits below hue 20 and is left alone.
    hue_ok = smooth(h, 20, 28) * (1 - smooth(h, 66, 80))
    yellow = hue_ok * smooth(s, 0.2, 0.45) * smooth(v, 0.05, 0.14)
    lo, hi = DARK_RANGE[look]
    dark = (1 - smooth(v, lo, hi)) * (1 - yellow)
    return yellow, dark, h, s, v


def recolour_armour(rgb, look):
    """rgb 0..1. Yellow goes blue with saturation and value kept; black and near-black go very dark blue
    with the value kept (and lifted a little); everything else is returned as it came."""
    yellow, dark, h, s, v = masks(rgb, look)
    blue_h = YELLOW_OUT_HUE + (h - YELLOW_CENTRE) * YELLOW_SPREAD
    blue = from_hsv(blue_h, np.clip(s, 0, 0.95), np.clip(v ** 0.85, 0, 1))
    navy = from_hsv(np.full_like(v, DARK_HUE), np.full_like(v, DARK_SAT), np.clip(v * 0.9 + DARK_LIFT, 0, 1))
    out = rgb * (1 - yellow[..., None]) + blue * yellow[..., None]
    out = out * (1 - dark[..., None]) + navy * dark[..., None]
    return np.clip(out, 0, 1)


def recolour(rgba, look):
    """RGBA uint8 to RGBA uint8; alpha is kept."""
    rgb = rgba[..., :3].astype(np.float32) / 255
    out = recolour_armour(rgb, look)
    res = rgba.copy()
    res[..., :3] = np.round(out * 255).astype(np.uint8)
    return res


# ---- textures -------------------------------------------------------------------------------------------

def dds_info(data):
    h, w = struct.unpack_from("<II", data, 12)
    mips = max(struct.unpack_from("<I", data, 28)[0], 1)
    return w, h, mips, data[84:88].decode("latin-1")


def decode(texture):
    return np.asarray(Image.open(io.BytesIO(texture[:-4])).convert("RGBA"))


def shrink(img, size):
    """Each channel resized alone: Pillow weights colour by alpha on RGBA and darkens it."""
    return Image.merge(img.mode, [c.resize(size, Image.Resampling.BOX) for c in img.split()])


# Block compression. Pillow's DXT encoder is crude (thin lines come out speckled, and a DXT5 alpha is off by
# a few levels), so the blocks are made here: endpoints along each block's principal axis, refined twice by
# least squares, colour in the four colour mode.

def blocks(img):
    """(H, W, C) to (blocks, 16, C), in the order DDS stores them."""
    h, w, c = img.shape
    ph, pw = (-h) % 4, (-w) % 4
    if ph or pw:
        img = np.pad(img, ((0, ph), (0, pw), (0, 0)), mode="edge")
        h, w = img.shape[:2]
    return img.reshape(h // 4, 4, w // 4, 4, c).transpose(0, 2, 1, 3, 4).reshape(-1, 16, c)


def to565(c):
    c = np.clip(np.round(c), 0, 255)
    r = np.round(c[..., 0] * 31 / 255).astype(np.int32)
    g = np.round(c[..., 1] * 63 / 255).astype(np.int32)
    b = np.round(c[..., 2] * 31 / 255).astype(np.int32)
    return (r << 11) | (g << 5) | b


def from565(v):
    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
    return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], -1).astype(np.float64)


def colour_blocks(px):
    """px (n, 16, 3) in 0..255: the 8 bytes of each BC1 colour block."""
    n = px.shape[0]
    guess = np.array([0.57, 0.62, 0.53])
    mean = px.mean(1, keepdims=True)
    d = px - mean
    cov = np.einsum("nki,nkj->nij", d, d)
    axis = np.tile(guess, (n, 1))
    for _ in range(8):
        axis = np.einsum("nij,nj->ni", cov, axis)
        norm = np.linalg.norm(axis, axis=1, keepdims=True)
        axis = np.where(norm > 1e-9, axis / np.maximum(norm, 1e-9), guess)
    t = np.einsum("nki,ni->nk", d, axis)
    lo = mean[:, 0, :] + axis * t.min(1)[:, None]
    hi = mean[:, 0, :] + axis * t.max(1)[:, None]
    weights = np.array([[1, 0], [0, 1], [2 / 3, 1 / 3], [1 / 3, 2 / 3]])
    best = None
    for _ in range(3):
        c0, c1 = to565(hi), to565(lo)
        swap = c0 < c1
        c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
        flat = c0 == c1   # four colour mode needs c0 > c1
        c0 = np.where(flat & (c0 < 0xFFFF), c0 + 1, c0)
        c1 = np.where(flat & (c0 == c1) & (c1 > 0), c1 - 1, c1)
        p0, p1 = from565(c0), from565(c1)
        palette = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], 1)
        dist = ((px[:, :, None, :] - palette[:, None, :, :]) ** 2).sum(-1)
        idx, err = dist.argmin(-1), dist.min(-1).sum(1)
        if best is None:
            best = [err, c0, c1, idx]
        else:
            better = err < best[0]
            best = [np.where(better, err, best[0]), np.where(better, c0, best[1]),
                    np.where(better, c1, best[2]), np.where(better[:, None], idx, best[3])]
        w = weights[idx]
        a, b, c = (w[..., 0] ** 2).sum(1), (w[..., 0] * w[..., 1]).sum(1), (w[..., 1] ** 2).sum(1)
        det = a * c - b * b
        ok = np.abs(det) > 1e-6
        safe = np.where(ok, det, 1)[:, None]
        r0, r1 = np.einsum("nk,nkc->nc", w[..., 0], px), np.einsum("nk,nkc->nc", w[..., 1], px)
        hi = np.where(ok[:, None], (c[:, None] * r0 - b[:, None] * r1) / safe, hi)
        lo = np.where(ok[:, None], (a[:, None] * r1 - b[:, None] * r0) / safe, lo)
    _, c0, c1, idx = best
    bits = np.zeros(n, np.uint32)
    for i in range(16):
        bits |= idx[:, i].astype(np.uint32) << (2 * i)
    out = np.empty((n, 8), np.uint8)
    out[:, 0], out[:, 1], out[:, 2], out[:, 3] = c0 & 255, c0 >> 8, c1 & 255, c1 >> 8
    for k in range(4):
        out[:, 4 + k] = (bits >> (8 * k)) & 255
    return out


def alpha_blocks(a):
    """a (n, 16) in 0..255: the 8 bytes of each BC3 alpha block, eight value mode."""
    n = a.shape[0]
    a0, a1 = np.round(a.max(1)), np.round(a.min(1))
    palette = np.stack([a0, a1] + [((7 - i) * a0 + i * a1) / 7 for i in range(1, 7)], 1)
    idx = np.abs(a[:, :, None] - palette[:, None, :]).argmin(-1)
    bits = np.zeros(n, np.uint64)
    for i in range(16):
        bits |= idx[:, i].astype(np.uint64) << np.uint64(3 * i)
    out = np.empty((n, 8), np.uint8)
    out[:, 0], out[:, 1] = a0.astype(np.uint8), a1.astype(np.uint8)
    for k in range(6):
        out[:, 2 + k] = ((bits >> np.uint64(8 * k)) & np.uint64(255)).astype(np.uint8)
    return out


def level(img, fmt):
    """One mip level's bytes: BC1 for DXT1, BC3 for DXT5."""
    px = np.asarray(img).astype(np.float64)
    colour = colour_blocks(blocks(px[..., :3]))
    if fmt == "DXT1":
        return colour.tobytes()
    return np.concatenate([alpha_blocks(blocks(px[..., 3:4])[..., 0]), colour], 1).tobytes()


def encode(rgba, template):
    """The original's header and tail around new pixels: same format, size and mip count."""
    w, h, mips, fmt = dds_info(template)
    if fmt not in ("DXT1", "DXT5") or rgba.shape[:2] != (h, w):
        raise SystemExit(f"a texture this tool does not know: {fmt} {w}x{h}")
    levels, img = [], Image.fromarray(rgba)
    for _ in range(mips):
        levels.append(level(img, fmt))
        img = shrink(img, (max(1, img.width // 2), max(1, img.height // 2)))
    out = template[:128] + b"".join(levels) + template[-4:]
    if len(out) != len(template):
        raise SystemExit(f"the new texture is {len(out)} bytes, the game's {len(template)}")
    return out


# ---- resources ------------------------------------------------------------------------------------------

def count(data, value):
    return [o for o in range(len(data) - 7) if struct.unpack_from("<Q", data, o)[0] == value]


def swap_u64(data, old, new):
    """data with the one 8 byte occurrence of old replaced; anything else is an error."""
    at = count(data, old)
    if len(at) != 1:
        raise SystemExit(f"{old:016x} occurs {len(at)} times, expected once")
    return data[:at[0]] + struct.pack("<Q", new) + data[at[0] + 8:]


def texture_slots(material, textures):
    """(offset of the texture hash, variable name, hash) of each texture a material names. A texture is
    named as the 4 byte hash of the variable and the 8 byte hash of the texture."""
    return [(o + 4, struct.unpack_from("<I", material, o)[0], struct.unpack_from("<Q", material, o + 4)[0])
            for o in range(0, len(material) - 11, 4)
            if struct.unpack_from("<Q", material, o + 4)[0] in textures]


def piece_material(src, piece):
    """The name hash of the game's material for a piece: the last 16 bytes of the first unit hold the name hash."""
    data = src[(UNIT, st.murmur64(next(iter(piece["units"].values()))))]
    return struct.unpack_from("<Q", data, len(data) - 16)[0]


def load_source():
    wanted = {}
    for kind, name, datas in st.entries(st.CONTENTS / SOURCE):
        wanted[(kind, name)] = datas[0]
    return wanted


def build():
    src = load_source()
    files = {}      # file name -> bytes
    manifest = []   # (type, resource name, file)
    pairs = {}      # new name -> (original, new) textures for the preview
    textures = {n: d for (k, n), d in src.items() if k == TEXTURE}
    copied = {}

    def add_texture(stem, data):
        files[f"{stem}.texture"] = data
        manifest.append(("texture", PREFIX + stem, f"{stem}.texture"))
        return st.murmur64(PREFIX + stem)

    for piece in PIECES:
        old_material = piece_material(src, piece)
        material = src[(MATERIAL, old_material)]
        for new_unit, path in piece["units"].items():
            data = src[(UNIT, st.murmur64(path))]
            if struct.unpack_from("<Q", data, len(data) - 16)[0] != old_material:
                raise SystemExit(f"{path} does not end in the material of the piece")
            new_material = st.murmur64(PREFIX + piece["material"])
            files[f"{new_unit}.unit"] = swap_u64(data, old_material, new_material)
            files[f"{new_unit}.bones"] = src[(BONES, st.murmur64(path))]
            manifest.append(("unit", PREFIX + new_unit, f"{new_unit}.unit"))
            manifest.append(("#%016x" % BONES, PREFIX + new_unit, f"{new_unit}.bones"))
        # The material: every texture it names under a new name.
        slots = texture_slots(material, textures)
        found = {h for _, _, h in slots}
        missing = set(piece["atlases"]) - found
        if missing:
            raise SystemExit(f"{piece['key']}: the material does not name {[hex(m) for m in missing]}")
        out = bytearray(material)
        for at, var, h in slots:
            if h in piece["atlases"]:
                stem, look = piece["atlases"][h]
                if var != DIFFUSE_MAP:
                    raise SystemExit(f"{stem} is not a diffuse map")
                if (stem not in pairs):
                    original = textures[h]
                    new = encode(recolour(decode(original), look), original)
                    pairs[stem] = (original, new)
                    add_texture(f"seaf_{stem}", new)
                new_hash = st.murmur64(PREFIX + f"seaf_{stem}")
            else:
                stem = f"tex_{h:016x}"
                if h not in copied:
                    copied[h] = add_texture(stem, textures[h])
                new_hash = copied[h]
            struct.pack_into("<Q", out, at, new_hash)
        files[f"{piece['material']}.material"] = bytes(out)
        manifest.append(("material", PREFIX + piece["material"], f"{piece['material']}.material"))
    return src, files, manifest, pairs


def check(src, files, manifest):
    """The new resources against the game's: what differs, and that nothing else does."""
    textures = {n: d for (k, n), d in src.items() if k == TEXTURE}
    ours = {st.murmur64(PREFIX + stem): d for stem, d in
            ((f[:-8], d) for f, d in files.items() if f.endswith(".texture"))}
    for piece in PIECES:
        for new_unit, path in piece["units"].items():
            a, b = src[(UNIT, st.murmur64(path))], files[f"{new_unit}.unit"]
            diff = [i for i in range(len(a)) if a[i] != b[i]]
            assert len(a) == len(b) and diff and diff[0] >= len(a) - 16 and diff[-1] < len(a) - 8, (new_unit, diff[:4])
            print(f"unit {new_unit}: {len(b)} bytes, {len(diff)} bytes differ, all in the material name at {len(a) - 16}")
        a, b = src[(MATERIAL, piece_material(src, piece))], files[f"{piece['material']}.material"]
        diff = [i for i in range(0, len(a), 4) if a[i:i + 4] != b[i:i + 4]]
        slots = texture_slots(a, textures)
        covered = {s + k for s, _, _ in slots for k in (0, 4)}
        assert len(a) == len(b) and all(i in covered for i in diff), "the material differs outside the texture names"
        for _, _, h in slots:
            at = [s for s, _, hh in slots if hh == h]
            assert all(struct.unpack_from("<Q", b, s)[0] in ours for s in at), "a texture left pointing at the game's"
        print(f"material {piece['material']}: {len(b)} bytes, {len(slots)} texture names swapped")
    for h, d in ours.items():
        w, hh, mips, fmt = dds_info(d)
        print(f"texture {h:016x}: {w}x{hh} {fmt} {mips} mips, {len(d)} bytes, tail {d[-4:].hex()}")


def preview(pairs):
    cell = 384
    names = list(pairs)
    sheet = Image.new("RGB", (cell * 2 + 30, len(names) * (cell + 10) + 10), (36, 36, 40))
    y = 10
    for stem in names:
        for i, data in enumerate(pairs[stem]):
            img = Image.fromarray(decode(data), "RGBA")
            w, h = img.size
            # Alpha over a checker, so a cape's edge shows.
            back = Image.new("RGBA", img.size, (90, 90, 96, 255))
            back.alpha_composite(img)
            back = back.convert("RGB").resize((cell, cell), Image.Resampling.NEAREST if w < cell else Image.Resampling.LANCZOS)
            sheet.paste(back, (10 + i * (cell + 10), y))
        y += cell + 10
    sheet.save(INTERNAL / "seaf_armor_preview.png")


def write(files, manifest):
    RES.mkdir(parents=True, exist_ok=True)
    for old in RES.iterdir():
        if old.name not in files:
            old.unlink()
    for name, data in files.items():
        (RES / name).write_bytes(data)
    entries = [{"type": t, "name": n, "bundle": BOOT, "data": f"res/armor/{f}", "when": {OPTION: True}} for t, n, f in manifest]
    option = {
        "id": OPTION, "type": "toggle", "default": True,
        "label": {"en": "SEAF custom armour"},
        "description": {"en": "SEAF Units wear a blue version of the default Helldiver armour, made for them. Changing this needs a full deploy in Obsidian. Off, they wear the Snow armour."},
    }
    INTERNAL.mkdir(exist_ok=True)
    (INTERNAL / "armor_manifest.json").write_text(
        json.dumps({"options": [option], "resources": entries}, indent=2) + "\n", encoding="utf-8")


def main():
    src, files, manifest, pairs = build()
    check(src, files, manifest)
    write(files, manifest)
    preview(pairs)
    print(f"wrote {len(files)} files to {RES}, {len(manifest)} resources")


if __name__ == "__main__":
    main()
