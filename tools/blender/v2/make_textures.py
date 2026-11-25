"""Makes the V2 game textures from CC0 MakeHuman system assets (plain Python 3 + Pillow; outputs are committed, so CI does not need to run it).
    python tools/blender/v2/make_textures.py
Writes assets/players/v2/textures/:
  skin_detail.png  tone-neutral skin detail (the MakeHuman light-skin diffuse divided by its own blurred colour): the game multiplies it by the identity
                   skin tone, so every tone keeps the same pores, lips and creases without a separate texture per ethnicity
  skin_normal.png  fine pore and crease relief derived from the detail luminance (tangent-space normal map)
  iris_<name>.png  eye textures; brow_<id>.png, lashes.png  alpha cards (tinted by the hair colour in the game)
"""
import os

from PIL import Image, ImageChops, ImageFilter, ImageOps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DATA = os.path.join(os.environ["APPDATA"], "Blender Foundation", "Blender", "4.5", "extensions", ".user", "user_default", "mpfb", "data")
OUT = os.path.join(ROOT, "assets", "players", "v2", "textures")


def skin():
    src = Image.open(os.path.join(DATA, "skins", "young_caucasian_male", "young_lightskinned_male_diffuse.png")).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    blur = src.filter(ImageFilter.GaussianBlur(48))
    # detail = src / blur, stored around mid grey (0.5 means x1.0)
    px_s, px_b = src.load(), blur.load()
    out = Image.new("RGB", src.size)
    po = out.load()
    for y in range(src.size[1]):
        for x in range(src.size[0]):
            s, b = px_s[x, y], px_b[x, y]
            po[x, y] = tuple(max(0, min(255, int(128 * (s[i] + 1) / (b[i] + 1)))) for i in range(3))
    out.save(os.path.join(OUT, "skin_detail.png"), optimize=True)
    # normal map from the high-frequency luminance
    lum = ImageOps.grayscale(src)
    high = ImageChops.subtract(lum, lum.filter(ImageFilter.GaussianBlur(6)), scale=1.0, offset=128)
    h = high.load()
    n = Image.new("RGB", src.size)
    pn = n.load()
    w, hh = src.size
    k = 2.2
    for y in range(hh):
        for x in range(w):
            dx = (h[(x + 1) % w, y] - h[(x - 1) % w, y]) / 255.0 * k
            dy = (h[x, (y + 1) % hh] - h[x, (y - 1) % hh]) / 255.0 * k
            l = (dx * dx + dy * dy + 1.0) ** 0.5
            pn[x, y] = (int((-dx / l * 0.5 + 0.5) * 255), int((dy / l * 0.5 + 0.5) * 255), int((1.0 / l * 0.5 + 0.5) * 255))
    n.save(os.path.join(OUT, "skin_normal.png"), optimize=True)


def small(src, dst, size):
    Image.open(src).convert("RGBA").resize((size, size), Image.LANCZOS).save(os.path.join(OUT, dst), optimize=True)


def card(src, dst, size):
    """A hair card for tinting: colour pure white, coverage in the alpha (the game multiplies by the hair colour)."""
    im = Image.open(src).convert("RGBA").resize((size, size), Image.LANCZOS)
    alpha = im.getchannel("A")
    white = Image.new("RGBA", im.size, (255, 255, 255, 255))
    white.putalpha(alpha)
    white.save(os.path.join(OUT, dst), optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    if not os.path.exists(os.path.join(OUT, "skin_detail.png")):
        skin()
    for name in ("brown", "brownlight", "green", "grey", "blue", "deepblue"):
        small(os.path.join(DATA, "eyes", "materials", name + "_eye.png"), "iris_%s.png" % name, 512)
    for b in ("eyebrow001", "eyebrow006", "eyebrow009", "eyebrow011"):
        card(os.path.join(DATA, "eyebrows", b, b + ".png"), "brow_%s.png" % b[-3:], 512)
    lash = [f for f in os.listdir(os.path.join(DATA, "eyelashes", "eyelashes01")) if f.endswith(".png")][0]
    card(os.path.join(DATA, "eyelashes", "eyelashes01", lash), "lashes.png", 512)
    print("textures written to", OUT)


main()
