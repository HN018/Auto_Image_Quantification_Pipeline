"""
Where does the segmentation time go on this PC?

Run in Miniforge Prompt (cellpose environment active), from the folder that contains
segment_folder.py:
  python diagnose_speed.py "C:\\path\\to\\one_image.tif" "C:\\path\\to\\GRAMW_v4"
"""
import sys
import time
import platform
from pathlib import Path

import numpy as np
import torch
from skimage.transform import rescale
from cellpose import models
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))   # find segment_folder.py one folder up
sys.path.insert(0, str(Path(__file__).resolve().parent))          # ...or in the same folder
from segment_folder import load_gram

img_path, model_path = Path(sys.argv[1]), sys.argv[2]
target = float(sys.argv[3]) if len(sys.argv) > 3 else 0.52

print(f"python {platform.python_version()} | torch {torch.__version__} | {torch.get_num_threads()} threads")
try:
    print("CPU instruction set used by torch:", torch.backends.cpu.get_cpu_capability())
except Exception:
    print("CPU instruction set: (not reported by this torch version)")

gram, px, note = load_gram(img_path, 0)
small = rescale(gram.astype(np.float32), px / target, order=1, preserve_range=True, anti_aliasing=True)
print(f"image {gram.shape} at {px:.4f} um/px -> {small.shape} at {target} um/px {note}")

for bf16 in (True, False):
    try:
        m = models.CellposeModel(gpu=False, pretrained_model=model_path, use_bfloat16=bf16)
        label = f"use_bfloat16={bf16}"
    except TypeError:
        if not bf16:
            break
        m = models.CellposeModel(gpu=False, pretrained_model=model_path)
        label = "default (this Cellpose has no use_bfloat16 option)"
    dtype = next(m.net.parameters()).dtype
    times = []
    for _ in range(2):                      # 2nd run excludes one-off warm-up
        t = time.time()
        masks = m.eval(small)[0]
        times.append(time.time() - t)
    print(f"{label:52s} weights {str(dtype):15s} eval: {times[0]:.1f} s, then {times[1]:.1f} s, {masks.max()} cells")
    del m
