#!/usr/bin/env python3
"""Cut the raw UI-kit JPGs (white/grey backgrounds, small text labels) out into transparent PNGs.

  python3 -I tools/art/import_ui.py [--src DIR] [--out assets/art]

For every UI sheet: background = near-white pixels connected to the image edge (flood fill),
text labels = foreground islands much smaller than the frame (dropped), optional "holes" =
enclosed white regions (portrait ring, minimap ring) made transparent too. The alpha gets a 1px
erode + small blur so edges are soft instead of white-fringed.
Status icons (EM06-EM14) sit on black: same idea with a near-black background.

Outputs: assets/art/ui/*.png and assets/art/status/*.png. Needs Pillow + numpy.
"""
import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

DEFAULT_SRC = "/tmp/claude-0/-home-user/11830cd4-db11-509f-ba13-bf47ce1014e3/scratchpad/dl/img/media"

# prefix -> list of (output name, max size) ; "split" = keep several islands, left to right
UI_JOBS = [
	{"prefix": "UI03", "names": ["slot"], "size": 256},
	{"prefix": "UI04", "names": ["slot_ult"], "size": 256},
	{"prefix": "UI05", "names": ["slot_item"], "size": 256},
	{"prefix": "UI06", "names": ["side_panel"], "size": 512},
	{"prefix": "UI07", "names": ["tab_normal", "tab_hover", "tab_selected"], "size": 384, "split": "rows"},
	{"prefix": "UI08", "names": ["button_normal", "button_hover", "button_pressed", "button_disabled"], "size": 384, "split": "rows"},
	{"prefix": "UI09", "names": ["resource_bar"], "size": 512, "holes": True},
	{"prefix": "UI10", "names": ["minimap_frame"], "size": 512, "holes": True},
	{"prefix": "UI11", "names": ["tooltip"], "size": 256},
	{"prefix": "UI12", "names": ["bar_frame"], "size": 512},
	{"prefix": "UI13", "names": ["portrait_frame_dark"], "size": 512},
	{"prefix": "UI14", "names": ["toast"], "size": 512},
	{"prefix": "UI15", "names": ["cursor_hand", "cursor_sword", "cursor_cast", "cursor_hammer", "cursor_no"], "size": 128, "split": "cols", "minfrac": 0.02},
	{"prefix": "UI16", "names": ["portrait_frame"], "size": 512, "holes": True},
]
STATUS_JOBS = [
	("EM06", "stun"), ("EM07", "root"), ("EM08", "slow"), ("EM09", "weaken"), ("EM10", "haste"),
	("EM11", "damage_up"), ("EM12", "armor_up"), ("EM13", "troll_slayer"), ("EM14", "recall"),
]


def label(mask):
	"""Connected components (4-neighbour) of a boolean array via PIL flood fill.
	Returns a list of boolean masks, largest first."""
	h, w = mask.shape
	work = Image.fromarray((mask * 255).astype(np.uint8), "L").copy()
	comps = []
	arr = np.array(work)
	while True:
		pts = np.argwhere(arr == 255)
		if len(pts) == 0:
			break
		y, x = pts[0]
		ImageDraw.floodfill(work, (int(x), int(y)), 128)
		now = np.array(work)
		comp = now == 128
		comps.append(comp)
		work.paste(0, mask=Image.fromarray((comp * 255).astype(np.uint8), "L"))
		arr = np.array(work)
	comps.sort(key=lambda c: -c.sum())
	return comps


def reached_from_edge(candidate):
	"""candidate: bool array. Pixels of it connected to the image border."""
	h, w = candidate.shape
	padded = np.zeros((h + 2, w + 2), dtype=np.uint8)
	padded[:, :] = 255  # the frame around the image counts as background
	padded[1:-1, 1:-1] = np.where(candidate, 255, 0)
	img = Image.fromarray(padded, "L").copy()
	ImageDraw.floodfill(img, (0, 0), 128)
	out = np.array(img) == 128
	return out[1:-1, 1:-1]


def soft_alpha(fg):
	img = Image.fromarray((fg * 255).astype(np.uint8), "L")
	img = img.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.9))
	return img


def bg_candidate(rgb):
	r, g, b = rgb[..., 0].astype(int), rgb[..., 1].astype(int), rgb[..., 2].astype(int)
	mn = np.minimum(np.minimum(r, g), b)
	mx = np.maximum(np.maximum(r, g), b)
	return (mn > 222) & (mx - mn < 22)


def cut(path, holes, minfrac):
	rgb = np.array(Image.open(path).convert("RGB"))
	cand = bg_candidate(rgb)
	bg = reached_from_edge(cand)
	fg = ~bg
	if holes:
		inner = cand & ~bg
		for comp in label(inner):
			if comp.sum() > 1500:
				fg &= ~comp
	comps = label(fg)
	if not comps:
		raise RuntimeError("nothing found in " + path)
	big = comps[0].sum()
	keep = [c for c in comps if c.sum() >= big * minfrac]
	return rgb, keep


def to_rgba(rgb, mask):
	alpha = soft_alpha(mask)
	img = Image.fromarray(rgb, "RGB").convert("RGBA")
	img.putalpha(alpha)
	bbox = alpha.point(lambda v: 255 if v > 8 else 0).getbbox()
	return img.crop(bbox)


def fit(img, size):
	w, h = img.size
	k = size / max(w, h)
	if k < 1:
		img = img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
	return img


def do_ui(src, out):
	os.makedirs(out, exist_ok=True)
	for job in UI_JOBS:
		files = glob.glob(os.path.join(src, job["prefix"] + "_*.jpg"))
		if not files:
			print("missing", job["prefix"])
			continue
		path = sorted(files)[0]
		split = job.get("split")
		rgb, comps = cut(path, job.get("holes", False), job.get("minfrac", 0.06 if split else 0.2))
		names = job["names"]
		if split:
			key = (lambda c: np.argwhere(c)[:, 0].mean()) if split == "rows" else (lambda c: np.argwhere(c)[:, 1].mean())
			comps.sort(key=key)
			if len(comps) != len(names):
				print("WARNING %s: found %d pieces, expected %d" % (job["prefix"], len(comps), len(names)))
			for name, comp in zip(names, comps):
				fit(to_rgba(rgb, comp), job["size"]).save(os.path.join(out, name + ".png"))
				print("wrote", name)
		else:
			merged = np.zeros_like(comps[0])
			for c in comps:
				merged |= c
			fit(to_rgba(rgb, merged), job["size"]).save(os.path.join(out, names[0] + ".png"))
			print("wrote", names[0])


def do_status(src, out):
	os.makedirs(out, exist_ok=True)
	for prefix, name in STATUS_JOBS:
		files = glob.glob(os.path.join(src, prefix + "_*.jpg"))
		if not files:
			print("missing", prefix)
			continue
		rgb = np.array(Image.open(sorted(files)[0]).convert("RGB"))
		lum = rgb.max(axis=2)
		cand = lum < 34
		bg = reached_from_edge(cand)
		fg = ~bg
		comps = label(fg)
		keep = np.zeros_like(fg)
		for c in comps:
			if c.sum() >= comps[0].sum() * 0.05:
				keep |= c
		img = to_rgba(rgb, keep)
		# square canvas, then the icon size used in the HUD
		side = max(img.size)
		canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
		canvas.paste(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2))
		canvas.resize((128, 128), Image.LANCZOS).save(os.path.join(out, name + ".png"))
		print("wrote status", name)


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--src", default=DEFAULT_SRC)
	root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
	ap.add_argument("--out", default=os.path.join(root, "assets", "art"))
	args = ap.parse_args()
	do_ui(args.src, os.path.join(args.out, "ui"))
	do_status(args.src, os.path.join(args.out, "status"))


if __name__ == "__main__":
	sys.exit(main())
