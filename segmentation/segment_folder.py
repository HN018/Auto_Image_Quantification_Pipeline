"""
Segment every multichannel TIFF in a folder with a fine-tuned Cellpose model and save
ImageJ/FIJI ROIs as <image>_ROI.zip in an output folder (default: next to the images).

Same steps as validated in the notebooks:
  GRAM-W channel -> resample to TARGET um/pixel -> Cellpose -> masks back to full size
  -> remove cells within EDGE_UM of the border -> remove objects below a minimum area
  -> polygon ROIs (cell_001, cell_002, ...)

Existing <image>_ROI.zip files are never overwritten unless --overwrite is given,
so ROI sets you have already reviewed are safe.

Example (Miniforge Prompt, with the cellpose environment active):
  python segment_folder.py --input "D:\\data\\exp1" --output "D:\\data\\exp1_ROIs" --model "C:\\Users\\me\\cellpose_tool\\GRAMW_v4" --benchmark
"""
VERSION = "1.0 (2026-10-24)"   # GRAMW_v4 | 0.35 um/px | float32 | edge 0.8 um | min area 200 um2 SR + non-SR

import argparse
import csv
import os
import sys
import time
from pathlib import Path

import numpy as np
import tifffile
from skimage.transform import rescale, resize
from skimage.measure import find_contours, regionprops
from skimage.segmentation import clear_border, relabel_sequential
from roifile import ImagejRoi, roiwrite


def parse_args():
    p = argparse.ArgumentParser(description="Cellpose GRAM-W batch segmentation -> FIJI ROI sets")
    p.add_argument("--input", required=True, help="folder with multichannel .tif images")
    p.add_argument("--output", default="", help="folder for the _ROI.zip files and the log (default: the image folder)")
    p.add_argument("--model", required=True, help="path to the trained model file (e.g. GRAMW_v4)")
    p.add_argument("--channel", type=int, default=0, help="GRAM-W channel, 0-based (FIJI channel 1 = 0)")
    p.add_argument("--target", type=float, default=0.35, help="pixel size (um) used for segmentation (0.35 validated; fastest step on the lab PC)")
    p.add_argument("--edge", type=float, default=0.8, help="remove cells closer than this (um) to the border")
    p.add_argument("--min-area-sr", type=float, default=200,
                   help="remove objects smaller than this (um^2) in SR images")
    p.add_argument("--min-area-nonsr", type=float, default=200,
                   help="remove objects smaller than this (um^2) in non-SR images")
    p.add_argument("--sr-max-pixel", type=float, default=0.09,
                   help="images with pixel size below this (um) count as SR")
    p.add_argument("--threads", type=int, default=0, help="CPU threads (0 = all cores)")
    p.add_argument("--overwrite", action="store_true", help="replace existing _ROI.zip files")
    p.add_argument("--benchmark", action="store_true", help="only process the first 3 images and report timing")
    p.add_argument("--pause", action="store_true", help="wait for Enter at the end (keeps the window open)")
    return p.parse_args()


def pixel_size(tif):
    """Pixel size in um from the TIFF resolution tag, or None."""
    xres = tif.pages[0].tags.get("XResolution")
    if xres is None:
        return None
    pixels, length = xres.value
    if pixels == 0:
        return None
    px = length / pixels
    return None if px == 1.0 else px          # 1.0 usually means "uncalibrated"


def load_gram(path, channel):
    """Return (2D GRAM-W image, pixel size in um or None, note)."""
    with tifffile.TiffFile(path) as tif:
        s = tif.series[0]
        arr, axes = s.asarray(), s.axes
        px = pixel_size(tif)
    note = ""
    if arr.ndim == 2:
        return arr, px, note
    if "C" in axes:
        ax = axes.index("C")
    else:                                    # unlabeled: shortest non-YX axis = channels
        cand = [i for i, a in enumerate(axes) if a not in "YX"]
        ax = min(cand, key=lambda i: arr.shape[i])
    if channel >= arr.shape[ax]:
        raise ValueError(f"channel {channel} requested but file has {arr.shape[ax]} channels")
    arr = np.take(arr, channel, axis=ax)
    axes = axes[:ax] + axes[ax + 1:]
    extra = tuple(i for i, a in enumerate(axes) if a not in "YX")
    if extra:
        arr = arr.max(axis=extra)
        note = f"max-projected {''.join(axes[i] for i in extra)}"
    return arr, px, note


def remove_small(masks, min_pixels):
    """Set objects with fewer than min_pixels pixels to background. Returns (masks, number removed)."""
    counts = np.bincount(masks.ravel())
    small = np.nonzero(counts < min_pixels)[0]
    small = small[small > 0]                    # label 0 is background
    if small.size:
        masks = np.where(np.isin(masks, small), 0, masks)
    return masks, int(small.size)


def masks_to_rois(masks, prefix="cell"):
    """One polygon ROI per labelled cell, in ImageJ pixel coordinates."""
    rois = []
    for k, r in enumerate(regionprops(masks), start=1):
        minr, minc, _, _ = r.bbox
        contours = find_contours(np.pad(r.image.astype(np.uint8), 1), 0.5)
        if not contours:
            continue
        c = max(contours, key=len)
        x = c[:, 1] - 1 + minc + 0.5
        y = c[:, 0] - 1 + minr + 0.5
        rois.append(ImagejRoi.frompoints(np.column_stack([x, y]), name=f"{prefix}_{k:03d}"))
    return rois


def main():
    args = parse_args()
    folder = Path(args.input)
    if not folder.is_dir():
        sys.exit(f"Input folder not found: {folder}")
    if not Path(args.model).is_file():
        sys.exit(f"Model file not found: {args.model}")

    out_dir = Path(args.output) if args.output else folder
    out_dir.mkdir(parents=True, exist_ok=True)

    import torch
    if args.threads > 0:
        torch.set_num_threads(args.threads)
    from cellpose import models

    images = sorted(p for p in folder.iterdir()
                    if p.suffix.lower() in (".tif", ".tiff") and not p.stem.endswith("_masks"))
    if args.benchmark:
        images = images[:3]
    print(f"segment_folder.py version {VERSION}", flush=True)
    print(f"images: {folder}", flush=True)
    print(f"ROIs + log: {out_dir}", flush=True)
    print(f"{len(images)} images | model {Path(args.model).name} | {torch.get_num_threads()} CPU threads", flush=True)

    t0 = time.time()
    print(f"segmenting at {args.target} um/pixel | min area SR {args.min_area_sr:g} um2, "
          f"non-SR {args.min_area_nonsr:g} um2", flush=True)
    try:   # full 32-bit precision: bfloat16 is very slow on most CPUs
        model = models.CellposeModel(gpu=False, pretrained_model=str(args.model), use_bfloat16=False)
    except TypeError:
        model = models.CellposeModel(gpu=False, pretrained_model=str(args.model))
    dtype = next(model.net.parameters()).dtype
    print(f"model loaded in {time.time() - t0:.1f} s | weights {dtype}", flush=True)

    log_path = out_dir / "segmentation_log.csv"
    new_log = not log_path.exists()
    times = []
    with open(log_path, "a", newline="") as fh:
        log = csv.writer(fh)
        if new_log:
            log.writerow(["image", "status", "cells", "seconds", "pixel_um", "note"])
        for i, f in enumerate(images, start=1):
            out = out_dir / (f.stem + "_ROI.zip")
            prefix = f"[{i}/{len(images)}] {f.name}"
            if out.exists() and not args.overwrite:
                print(f"{prefix}: skipped (ROI file exists)", flush=True)
                log.writerow([f.name, "skipped_exists", "", "", "", ""])
                continue
            try:
                t = time.time()
                gram, px, note = load_gram(f, args.channel)
                if px is None:
                    print(f"{prefix}: SKIPPED - no pixel size in file", flush=True)
                    log.writerow([f.name, "no_pixel_size", "", "", "", note])
                    continue
                small = rescale(gram.astype(np.float32), px / args.target, order=1,
                                preserve_range=True, anti_aliasing=True)
                pred = model.eval(small)[0]
                masks = resize(pred, gram.shape, order=0, preserve_range=True,
                               anti_aliasing=False).astype(np.int32)
                masks = clear_border(masks, buffer_size=max(1, round(args.edge / px)))
                is_sr = px < args.sr_max_pixel
                min_um2 = args.min_area_sr if is_sr else args.min_area_nonsr
                masks, n_small = remove_small(masks, min_um2 / (px * px))
                masks = relabel_sequential(masks)[0]
                rois = masks_to_rois(masks)
                note = (note + f" removed {n_small} < {min_um2:g} um2").strip() if n_small else note
                if out.exists():
                    out.unlink()
                if rois:
                    roiwrite(out, rois)
                dt = time.time() - t
                times.append(dt)
                print(f"{prefix}: {len(rois)} cells, {dt:.1f} s {note}", flush=True)
                log.writerow([f.name, "ok", len(rois), f"{dt:.1f}", f"{px:.4f}", note])
            except Exception as e:
                print(f"{prefix}: ERROR {e}", flush=True)
                log.writerow([f.name, "error", "", "", "", str(e)])
            fh.flush()

    if times:
        print(f"done: {len(times)} segmented, mean {np.mean(times):.1f} s/image, "
              f"total {sum(times) / 60:.1f} min", flush=True)
    else:
        print("done: nothing segmented", flush=True)
    print(f"log: {log_path}", flush=True)
    if args.pause:
        input("Press Enter to close this window...")


if __name__ == "__main__":
    main()
