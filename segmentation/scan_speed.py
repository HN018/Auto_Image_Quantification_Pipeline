"""
Measure how segmentation time depends on the pixel size, on THIS computer.

Run in Miniforge Prompt (cellpose environment active), from the folder with segment_folder.py:
  python scan_speed.py "C:\\path\\to\\GRAMW_v4" "C:\\path\\to\\SR_image.tif" "C:\\path\\to\\nonSR_image.tif"
"""
import sys
import time
from pathlib import Path

import numpy as np
from skimage.transform import rescale
from cellpose import models
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))   # find segment_folder.py one folder up
sys.path.insert(0, str(Path(__file__).resolve().parent))          # ...or in the same folder
from segment_folder import load_gram

TARGETS = [0.26, 0.31, 0.35, 0.40, 0.45]

model_path = Path(sys.argv[1])
if not model_path.is_file():
    sys.exit(f"Model file not found: {model_path}")
images = [Path(p) for p in sys.argv[2:]]

try:
    model = models.CellposeModel(gpu=False, pretrained_model=str(model_path), use_bfloat16=False)
except TypeError:
    model = models.CellposeModel(gpu=False, pretrained_model=str(model_path))

for f in images:
    gram, px, _ = load_gram(f, 0)
    print(f"\n{f.name}  ({gram.shape[0]}x{gram.shape[1]} px at {px:.4f} um)")
    print(f"{'target':>7} {'resampled':>11} {'eval s':>8} {'cells':>6}")
    model.eval(rescale(gram.astype(np.float32), px / TARGETS[-1], order=1,
                       preserve_range=True, anti_aliasing=True))          # warm-up, not timed
    for t in TARGETS:
        small = rescale(gram.astype(np.float32), px / t, order=1, preserve_range=True, anti_aliasing=True)
        t0 = time.time()
        masks = model.eval(small)[0]
        dt = time.time() - t0
        print(f"{t:>7.2f} {str(small.shape[0]) + ' px':>11} {dt:>8.1f} {masks.max():>6}")
