# Quick start: GRAM-W cell segmentation and quantification

This guide gets you from "never used it" to measured cells. Allow about 30 minutes for installation
(once per computer) and 10 minutes for your first test run.

---

## 1. What the pipeline does

```
 multichannel TIFFs
        |
  [1] Segment GRAMW            Cellpose AI outlines every cell in the GRAM-W channel
        |                      -> <image>_ROI.zip  (one ROI per cell)
  [2] GRAMW Review             you check every image, delete bad/abnormal cells, draw missed ones
        |                      -> corrected <image>_ROI.zip
  [3] Split Selected Channels  (optional) saves single channels, e.g. LAMP1, to make masks
        |   + your own thresholding in FIJI
        |                      -> C3-<image>.tif masks (white = structure, black = background)
  [4] GRAMW Quantify           measures each cell (whole cell, or inside the mask particles)
                               -> measurements\*.csv  (one row per cell, ready for Prism)
```

### What each module is for

| Module | Where it runs | What it is for | When you need it |
|---|---|---|---|
| `segmentation/Segment_GRAMW.ijm` | FIJI (Plugins menu) | Dialog to start segmentation on a folder of images | Every experiment, step 1 |
| `segmentation/segment_folder.py` | Python (started by the macro above) | The actual segmentation: runs Cellpose model GRAMW_v4, removes edge cells and debris, writes ROI files | Never opened directly; must be installed |
| `fiji/GRAMW_Review.ijm` | FIJI | Shows each image with its outlines; OK saves and moves on; resumes where you stopped | Every experiment, step 2 |
| `fiji/Split_Selected_Channels.ijm` | FIJI | Saves chosen channels of every image into `C1\`, `C2\`, ... folders | When you want masks (step 3) |
| `fiji/GRAMW_Quantify.ijm` | FIJI | Measures intensities per cell (and per particle), writes CSV tables and a settings file | Every experiment, step 4 |
| `segmentation/tools/scan_speed.py` | Python | Finds the fastest accurate settings for a new camera/image size | Only for new image formats |
| `segmentation/tools/diagnose_speed.py` | Python | Checks why segmentation is slow on a computer | Only if a computer is very slow |
| `training/*.ipynb` | Google Colab / Kaggle | Training and testing new versions of the model | Only for model development |
| `docs/teaching/` | - | Line-by-line explanations of every code file | If you want to understand or change the code |

**You only need Python for step 1.** Steps 2-4 are plain FIJI macros. If someone else segments
your images, you can skip the Python installation.

---

## 2. Installation

### 2a. FIJI part (everyone)

1. Install or update FIJI: **Help > Update...**, apply all updates, restart. (The review macro needs
   FIJI 1.54f or newer and stops with a message if it is older.)
2. **Edit > Options > Memory & Threads**: set *Maximum memory* to about half of the computer's RAM
   (e.g. 8000 MB on a 16 GB laptop). Restart FIJI. Too little memory makes FIJI freeze.
3. Copy these files into `Fiji.app\scripts\Plugins\`:
   - `fiji\GRAMW_Review.ijm`
   - `fiji\Split_Selected_Channels.ijm`
   - `fiji\GRAMW_Quantify.ijm`
   - `segmentation\Segment_GRAMW.ijm` (only if you will segment on this computer)
4. Restart FIJI. They now appear in the **Plugins** menu (underscores shown as spaces).

### 2b. Segmentation part (only on computers that run step 1)

Short version (details and troubleshooting: [INSTALL_segmentation.md](INSTALL_segmentation.md)):

1. Install **Miniforge3** for Windows, choosing **"Just Me"** (no admin rights needed).
2. In **Miniforge Prompt**:
   ```
   conda create -n cellpose python=3.11 -y
   conda activate cellpose
   python -c "import sys; print(sys.executable)"
   python -m pip install torch --index-url https://download.pytorch.org/whl/cpu
   python -m pip install "cellpose>=4,<5" roifile tifffile scikit-image
   ```
   Write down the path printed by the third line - it must contain `envs\cellpose`.
3. Create a folder, e.g. `C:\Users\<you>\Desktop\cellpose_tool\`, containing:
   - `segment_folder.py` (from `segmentation\`)
   - `GRAMW_v4` (model file, from this repository's **Releases** page)
4. Open `Fiji.app\scripts\Plugins\Segment_GRAMW.ijm` in a text editor and edit the three paths at
   the top (double backslashes `\\`): your Python path from step 2, the script, the model.
5. Restart FIJI and run a test (section 4).

---

## 3. Before you start an experiment

**Image requirements**
- Multichannel TIFFs, **GRAM-W in channel 1** (or tell the macro which channel).
- **Pixel size saved in the file** (check: Image > Properties shows e.g. 0.11 micron). Images
  without it are skipped. To fix: set it in Image > Properties and save.
- One field of view per file, 2D (z-stacks are max-projected for segmentation; the quantification
  measures 2D images only).

**Recommended folder layout per experiment**
```
MyExperiment\
    images\                     original multichannel TIFFs (never modified by the pipeline)
    images_ROIs\                step 1 + 2: <image>_ROI.zip, segmentation_log.csv, review_log.csv
    images\C3\                  step 3: C3-<image>.tif (split channel)
    masks_LAMP1\                step 3: your thresholded masks, named C3-<image>.tif
    images\measurements\        step 4: CSV tables + settings file
```

**Golden rules**
- **Do not rename images** after segmentation: everything is matched by file name
  (`<image>_ROI.zip`, `C3-<image>.tif`).
- **Review before quantifying.** The model also outlines abnormal/dead cells on purpose; you remove
  them in step 2.
- **Never tick "Overwrite" on a folder you have already reviewed** - it replaces your corrections.

---

## 4. Running the pipeline

### Step 1 - Segment (Plugins > Segment GRAMW)

- *Image folder*: your `images\` folder. *ROI output folder*: leave blank (creates `images_ROIs\`).
- *GRAM-W channel*: 1. First time: tick *Benchmark only* to test 3 images.
- A console window shows progress. The first lines must show `version 1.0` and
  `weights torch.float32`. Typical speed on a lab PC/laptop: ~5 s per SR image, ~15-20 s per non-SR
  image. Press Enter to close the window at the end.
- You can start reviewing while segmentation is still running.

### Step 2 - Review (Plugins > GRAMW Review)

- Choose `images\` and `images_ROIs\`; choose channels/colours to display.
- For each image:

| To do this | Do this |
|---|---|
| Add a missed cell | draw its outline (freehand tool), press **t** |
| Delete a cell (abnormal, debris, wrong) | click its outline/number, then **Delete** in the ROI Manager |
| Save and go to the next image | click **OK** (or Enter) in the "ROI review" window |
| Go back one image | hold **Shift** + click OK |
| Skip without saving | hold **Alt** + click OK |
| Undo all edits on this image | hold **Space** + click OK |
| Stop (resume later) | **Esc** |

- Do **not** press the keyboard Delete key on the image (it erases pixels on screen).
- The model's original outlines are kept in `images_ROIs\original_model_ROIs\`.

### Step 3 - Masks (optional)

1. **Plugins > Split Selected Channels**: tick the channel you need (e.g. 3 for LAMP1). Files appear
   in `images\C3\` as `C3-<image>.tif`.
2. Process and threshold them in FIJI as you normally do (e.g. background subtraction, filter,
   threshold, *Convert to Mask*), and save the masks **with the same names** into a mask folder.
   Any non-zero pixel counts as mask.

### Step 4 - Quantify (Plugins > GRAMW Quantify)

- Folders: `images\`, your mask folder (or blank for whole-cell only), `images_ROIs\`.
- Tick the channels to measure and set the value to subtract from each (default 100; 0 = none).
- Method (default with masks: *Within mask + per-particle table*), particle size (default 9 pixels
  minimum), exclusion of particles touching the cell outline (default on).
- First time: tick **DEBUG** to step through one image and check every stage visually.

**Output columns (per cell)**

| Column | Meaning |
|---|---|
| Image, Channel, Cell | identification |
| Cell_Area_px / _um2 | cell area |
| Particle_Count | mask particles counted in the cell |
| Mask_Area_px / _um2, Mask_Fraction | total particle area, fraction of the cell |
| Mean_Particle_Area_px / _um2 | average particle size |
| Mean | area-weighted mean intensity = sum(area x mean) / sum(area) |
| Min, Max | lowest / highest pixel in the particles |
| Total_Intensity | sum(particle area x particle mean) = Mask_Area_um2 x Mean |

Whole-cell mode has Area, Mean, Min, Max and Total_Intensity of the whole cell. The settings file
next to the tables records every choice - keep it with your data.

---

## 5. If something goes wrong

| Problem | First thing to check |
|---|---|
| "Python / Script / Model not found" | the three paths at the top of `Segment_GRAMW.ijm` |
| Segmentation takes minutes per image | first lines of the console must say `torch.float32`; see INSTALL_segmentation.md, T6 |
| Image "SKIPPED - no pixel size" | set the pixel size in Image > Properties and save |
| "already exists, skipped" | ROI files are protected; only use Overwrite on unreviewed folders |
| Review: FIJI freezes after some images | raise FIJI's memory (section 2a); send `review_trace.txt` |
| Review: "requires ImageJ 1.54f" | Help > Update... |
| Quantify: image skipped "no matching mask" | mask must be named `<image>.tif` or `C<n>-<image>.tif` |
| Python errors during installation | INSTALL_segmentation.md, troubleshooting T1-T4 |

**Asking for help:** open an *Issue* in this repository (or message the maintainer) and attach the
relevant log: `segmentation_log.csv` (step 1), `review_trace.txt` (step 2), the `settings_*.txt` file
(step 4), plus a screenshot of any error message with its line number.
