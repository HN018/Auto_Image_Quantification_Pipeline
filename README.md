# GRAM-W cell segmentation and quantification pipeline

Automated cell outline ROIs for fluorescence microscopy images, user review in FIJI, and batch per-cell quantification.
Built for EGFP-GRAM-W expressing cell lines and designed to run on ordinary Windows lab computers (CPU only, no administrator rights needed).

A fine-tuned [Cellpose](https://github.com/MouseLand/cellpose) model (**GRAMW_v4**) finds every cell
in the GRAM-W channel; FIJI macros let you correct the outlines quickly and then measure intensities
per cell, whole-cell or inside mask particles (e.g. LAMP1-positive lysosomes), with results written
as CSV tables ready for Prism.

> **Need help with installation?** Start with **[QUICKSTART.md](QUICKSTART.md)** - installation instruction, what each
> module does, and how to run an experiment.

---

## Workflow

```
 multichannel TIFFs (GRAM-W + other channels, pixel size saved in the file)
        |
  [1] Segment GRAMW              Cellpose GRAMW_v4 outlines every cell 
        |                        -> <image>_ROI.zip, segmentation_log.csv
  [2] GRAMW Review               check each image; delete abnormal/wrong cells, draw missed ones
        |                        -> corrected <image>_ROI.zip, review_log.csv
  [3] Split Selected Channels    (optional) single channels for making masks,
        |  + thresholding in FIJI  e.g. LAMP1 -> C3-<image>.tif binary masks
        |
  [4] GRAMW Quantify             per-cell (and per-particle) measurements
                                 -> measurements\*.csv + settings file
```

## Modules

| Module | Runs in | Purpose |
|---|---|---|
| [`segmentation/Segment_GRAMW.ijm`](segmentation/Segment_GRAMW.ijm) | FIJI | Dialog that starts segmentation of a folder and shows progress |
| [`segmentation/segment_folder.py`](segmentation/segment_folder.py) | Python | Segmentation engine: Cellpose model, edge-cell and debris removal, ImageJ ROI export |
| [`fiji/GRAMW_Review.ijm`](fiji/GRAMW_Review.ijm) | FIJI | Image-by-image review and correction of ROIs, with resume, backups and a troubleshooting trace |
| [`fiji/Split_Selected_Channels.ijm`](fiji/Split_Selected_Channels.ijm) | FIJI | Saves selected channels of all images into `C1\`, `C2\`, ... |
| [`fiji/GRAMW_Quantify.ijm`](fiji/GRAMW_Quantify.ijm) | FIJI | Whole-cell, in-mask and per-particle quantification with a debug mode |
| [`segmentation/tools/scan_speed.py`](segmentation/tools/scan_speed.py) | Python | Measures speed vs. pixel size to choose settings for new image formats |
| [`segmentation/tools/diagnose_speed.py`](segmentation/tools/diagnose_speed.py) | Python | Diagnoses slow segmentation on a computer |
| [`training/cellpose_GRAMW_colab_v4.ipynb`](training/cellpose_GRAMW_colab_v4.ipynb) | Google Colab | Builds training data, trains and evaluates models |
| [`training/cellpose_GRAMW_kaggle_v4.ipynb`](training/cellpose_GRAMW_kaggle_v4.ipynb) | Kaggle | GPU training and evaluation |

Only step 1 needs Python; steps 2-4 are FIJI macros that anyone can install in a minute.

---

## Installation

**FIJI macros (everyone):** update FIJI (Help > Update...), set Edit > Options > Memory & Threads to
about half of the computer's RAM, copy the `.ijm` files into `Fiji.app\scripts\Plugins\`, restart.

**Segmentation (computers that run step 1):** Miniforge ("Just Me"), a `cellpose` Python 3.11
environment with CPU PyTorch and Cellpose 4.x, the script and the model file, and three paths edited
in `Segment_GRAMW.ijm`. Step-by-step instructions and troubleshooting:
**[INSTALL_segmentation.md](INSTALL_segmentation.md)**.

**Model file:** `GRAMW_v4` (~1.2 GB) is attached to the **Releases** page of this repository (it is too
large for the code folders).

### Requirements

| | |
|---|---|
| Operating system | Windows 10/11 (macros also work in FIJI on macOS/Linux) |
| FIJI | 1.54f or newer, with Bio-Formats (standard in FIJI) |
| Python (step 1 only) | 3.11 with `cellpose>=4,<5`, `torch` (CPU build), `roifile`, `tifffile`, `scikit-image` |
| Hardware | any recent CPU; no GPU needed; ~3 GB disk for the Python environment and model |
| Images | 2D multichannel TIFFs, GRAM-W channel known (default channel 1), pixel size saved in the file |

---

## Input and output conventions

Everything is matched by file name, so **do not rename images after segmentation**.

| File | Produced by | Name |
|---|---|---|
| Cell outlines | steps 1-2 | `<ROI folder>\<image>_ROI.zip` (ROIs `cell_001`, `cell_002`, ...) |
| Original model outlines | step 2 | `<ROI folder>\original_model_ROIs\<image>_ROI.zip` |
| Split channels | step 3 | `<image folder>\C<n>\C<n>-<image>.tif` |
| Masks | you (step 3) | `<image>.tif` or `C<n>-<image>.tif` in a mask folder; non-zero = mask |
| Measurements | step 4 | `<image folder>\measurements\C<n>_<method>_per_cell_<date_time>.csv` (+ `_per_particle_`) |
| Logs | steps 1, 2, 4 | `segmentation_log.csv`, `review_log.csv`, `review_trace.txt`, `settings_<date_time>.txt` |

### Measurements (per cell, mask methods)

| Column | Meaning |
|---|---|
| `Cell_Area_px`, `Cell_Area_um2` | cell area |
| `Particle_Count` | mask particles in the cell (size filter in mask pixels; particles touching the outline optionally excluded) |
| `Mask_Area_px`, `Mask_Area_um2`, `Mask_Fraction` | total particle area; fraction of the cell |
| `Mean_Particle_Area_px`, `Mean_Particle_Area_um2` | average particle size |
| `Mean` | area-weighted mean intensity: sum(particle area x particle mean) / sum(particle area) |
| `Min`, `Max` | lowest / highest pixel in the counted particles |
| `Total_Intensity` | sum(particle area x particle mean) = `Mask_Area_um2` x `Mean` |

Whole-cell mode reports `Area_px`, `Area_um2`, `Mean`, `Min`, `Max`, `Total_Intensity` of the whole
cell. A constant background value (default 100) is subtracted per channel before measuring
(Process > Math > Subtract). Every run writes a settings file describing all choices and calculations.

---

## Segmentation model and performance

**GRAMW_v4** is Cellpose-SAM fine-tuned on 43 manually annotated images of EGFP-GRAM-W cells (SR and
non-SR acquisitions, several treatments). Every cell was outlined - including cells at the image edge
and abnormal cells (tagged `abn_`) - so the model finds all cells.

Segmentation settings (`segment_folder.py` version 1.0): images resampled to 0.35 um/pixel, float32
inference on CPU, cells within 0.8 um of the image border removed, objects smaller than 200 um^2
removed.

**Accuracy** on 14 held-out validation images (normal cells, full resolution, edge cells removed):

| | AP@0.5 | AP@0.9 |
|---|---|---|
| All images | 0.96 | 0.88 |
| SR images | 1.00 | 1.00 |
| Non-SR images | 0.93 | 0.79 |

AP (average precision) = TP / (TP + FP + FN); a cell counts as found if its outline overlaps the
manual outline with IoU >= 0.5 (or >= 0.9 for near-identical outlines). The validation images also
guided the choice of settings, so publication figures should be based on a fresh test set.

**Speed** (1200 x 1200 px images, CPU): ~5 s per SR image and ~17-22 s per non-SR image on a 6-thread
lab PC and a 10-thread laptop.

---

## Repository layout

```
README.md                 this file
QUICKSTART.md             installation and use, for lab members
INSTALL_segmentation.md   detailed Python set-up and troubleshooting
CHANGELOG.md              changes per version
segmentation/
    segment_folder.py
    Segment_GRAMW.ijm
    requirements.txt
    tools/scan_speed.py
    tools/diagnose_speed.py
fiji/
    GRAMW_Review.ijm
    Split_Selected_Channels.ijm
    GRAMW_Quantify.ijm
training/
    cellpose_GRAMW_colab_v4.ipynb
    cellpose_GRAMW_kaggle_v4.ipynb
.github/ISSUE_TEMPLATE/   problem report template
```

## Getting help

Open an **Issue** using the *Problem report* template and attach the relevant log: the console output
and `segmentation_log.csv` (step 1), the last lines of `review_trace.txt` (step 2), or the
`settings_*.txt` file (step 4), plus a screenshot of any error message with its line number.
Common problems and fixes are listed in [QUICKSTART.md](QUICKSTART.md#5-if-something-goes-wrong)
and [INSTALL_segmentation.md](INSTALL_segmentation.md#troubleshooting).

## Acknowledgements and citation

Segmentation uses [Cellpose](https://github.com/MouseLand/cellpose) (Cellpose 4, Cellpose-SAM model).
Please cite the Cellpose publications listed in the Cellpose repository when you publish results
obtained with this pipeline, and cite this repository (a DOI will be added here when a release is
archived at publication).

## Maintainer

Haoning Yang, Lee Kong Chian School of Medicine, Nanyang Technological University, Singapore.
