from PIL import Image, ImageFilter
from collections import deque
import numpy as np, os, json, subprocess, tempfile

SRC = "Design/Untitled Design.svg"
OUT = "Barnacle/Assets.xcassets/AppIcon.appiconset"
os.makedirs(OUT, exist_ok=True)

C = 1024          # canvas
S = 824           # macOS icon shape occupies 824 of 1024
N = 5.0           # superellipse exponent (macOS squircle)
ART_MAX = 672     # art bounding box, longer side, inside the shape (~82% of S)
SS = 4            # supersample for the mask

# --- squircle alpha mask, antialiased by supersampling ---
a = S / 2.0
n = C * SS
coord = (np.arange(n) + 0.5) / SS - C / 2.0
X = np.abs(coord) / a
f = X[None, :] ** N + X[:, None] ** N
mask_ss = (f <= 1.0).astype(np.float32)
mask = mask_ss.reshape(C, SS, C, SS).mean(axis=(1, 3))
alpha = Image.fromarray((mask * 255).astype(np.uint8), "L")

# --- white shape ---
shape = Image.new("RGBA", (C, C), (255, 255, 255, 0))
shape.putalpha(alpha)

# --- soft drop shadow so the white shape separates on light backgrounds ---
sh = Image.new("RGBA", (C, C), (0, 0, 0, 0))
sh.putalpha(alpha.point(lambda v: int(v * 0.20)))
sh = sh.filter(ImageFilter.GaussianBlur(14))
canvas = Image.new("RGBA", (C, C), (0, 0, 0, 0))
canvas.alpha_composite(sh, (0, 10))
canvas.alpha_composite(shape)

def optical_centre(rgb):
    """Centroid of the mark's filled silhouette, i.e. with its enclosed holes
    counted as part of the shape.

    Centring the bounding box is not the same as looking centred: this mark has
    one long thin lobe that stretches the box to the right without carrying any
    visual weight, so a box-centred version reads as sitting left. Filling the
    holes first is what makes the measure track the shape's extent rather than
    its stroke weight, which is the thing the eye actually balances."""
    solid = (255 - np.asarray(rgb).astype(int).min(axis=2)) > 25
    h, w = solid.shape
    outside = np.zeros_like(solid)
    q = deque()
    for y in range(h):
        for x in (0, w - 1):
            if not solid[y, x] and not outside[y, x]:
                outside[y, x] = True; q.append((y, x))
    for x in range(w):
        for y in (0, h - 1):
            if not solid[y, x] and not outside[y, x]:
                outside[y, x] = True; q.append((y, x))
    while q:                                   # flood the background inwards
        y, x = q.popleft()
        for ny, nx in ((y+1, x), (y-1, x), (y, x+1), (y, x-1)):
            if 0 <= ny < h and 0 <= nx < w and not solid[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True; q.append((ny, nx))
    filled = ~outside
    Y, X = np.mgrid[0:h, 0:w]
    t = filled.sum()
    return (X * filled).sum() / t, (Y * filled).sum() / t


# --- art: crop to its bounding box, scale, centre it optically in the shape ---
with tempfile.TemporaryDirectory() as tmp:
    # Quick Look ships with macOS and rasterizes the SVG onto opaque white
    subprocess.run(["qlmanage", "-t", "-s", "2048", "-o", tmp, SRC],
                   check=True, capture_output=True)
    src = Image.open(os.path.join(tmp, os.path.basename(SRC) + ".png")).convert("RGB")
arr = np.asarray(src).astype(int)
ys, xs = np.nonzero(arr.min(axis=2) < 250)
box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
art = src.crop(box)
w, h = art.size
cx, cy = optical_centre(art)
k = ART_MAX / max(w, h)   # fit the longer side, so orientation does not change the fit
art = art.resize((round(w * k), round(h * k)), Image.LANCZOS).convert("RGBA")
# place the art so its optical centre, not its box centre, lands on the canvas centre
canvas.alpha_composite(art, (round(C / 2 - cx * k), round(C / 2 - cy * k)))
print(f"optical centre offset from box centre: "
      f"({cx - w / 2:+.1f}, {cy - h / 2:+.1f}) src px -> "
      f"({(w / 2 - cx) * k:+.1f}, {(h / 2 - cy) * k:+.1f}) px nudge at {C}")

# --- write every macOS size ---
sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
         (256, 1), (256, 2), (512, 1), (512, 2)]
images = []
for pt, scale in sizes:
    px = pt * scale
    name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
    canvas.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
    images.append({"size": f"{pt}x{pt}", "idiom": "mac",
                   "filename": name, "scale": f"{scale}x"})

json.dump({"images": images, "info": {"version": 1, "author": "xcode"}},
          open(os.path.join(OUT, "Contents.json"), "w"), indent=2)
json.dump({"info": {"version": 1, "author": "xcode"}},
          open("Barnacle/Assets.xcassets/Contents.json", "w"), indent=2)
print("wrote", len(images), "icons")
