# Installing the Cellpose ROI prediction (Windows, CPU, no admin rights)

This guide sets up step 1 of the pipeline: FIJI runs `segment_folder.py`, which uses the
fine-tuned Cellpose model **GRAMW_v4** to outline every cell in the EGFP-GRAM-W channel and
saves one ImageJ ROI set per image (`<image>_ROI.zip`).

Everything installs into your own user folder, so **no administrator rights are needed** and
**no GPU is needed**. Set-up takes about 20-30 minutes, once per computer.

---

## 0. What you need

| | |
|---|---|
| Windows 10 or 11 | tested on a lab PC (6 CPU threads) and a laptop (10 threads) |
| FIJI | any recent version |
| ~3 GB free disk space | Python environment (~2 GB) + model file (~1.2 GB) |
| Internet access during installation | to download Python packages |
| The model file `GRAMW_v4` | from this repository's **Releases** page (it is too large for the code folders) |

Expected speed on a CPU with the default settings (1200 x 1200 px images):
about **5 s per SR image** and **15-20 s per non-SR image**.

---

## 1. Install Miniforge (Python distribution)

1. Download the Windows installer of **Miniforge3** from its GitHub releases page
   (`Miniforge3-Windows-x86_64.exe`).
2. Run it and choose **"Just Me"** (this is what makes it work without admin rights).
   Keep the default location, normally `C:\Users\<you>\AppData\Local\miniforge3`.
3. When finished, open **Miniforge Prompt** from the Start menu. All commands below are typed there.

> Already have Anaconda or another Miniforge? You can keep it, but read the
> troubleshooting section if commands start using the wrong Python.

---

## 2. Create a separate Python environment

An environment is an isolated Python installation just for this tool, so it cannot interfere
with anything else on the computer.

```
conda create -n cellpose python=3.11 -y
conda activate cellpose
python -c "import sys; print(sys.executable, sys.version)"
```

**Check the last line.** It must print a path that contains `envs\cellpose` and a version
starting with `3.11`, for example:

```
C:\Users\<you>\AppData\Local\miniforge3\envs\cellpose\python.exe 3.11.x ...
```

Write this path down: it is the **Python path** you will put into the FIJI macro in step 5.
If the path does **not** contain `envs\cellpose`, stop and see *Troubleshooting* (T1-T3).

---

## 3. Install the packages

Still in Miniforge Prompt, with the environment active. Use `python -m pip` (not plain `pip`),
which guarantees the packages go into this environment's Python:

```
python -m pip install torch --index-url https://download.pytorch.org/whl/cpu
python -m pip install "cellpose>=4,<5" roifile tifffile scikit-image
```

- The first line installs the **CPU-only** version of PyTorch (~200 MB instead of ~2.5 GB).
- `cellpose>=4,<5` means "any 4.x version": the code was written and validated for Cellpose 4.

Check that everything is there:

```
python -c "import sys, importlib.util as u; print(sys.executable); print('cellpose:', 'OK' if u.find_spec('cellpose') else 'MISSING'); print('torch:', 'OK' if u.find_spec('torch') else 'MISSING')"
```

Both lines must say **OK**.

---

## 4. Create the tool folder

Make a folder, for example `C:\Users\<you>\Desktop\cellpose_tool\`, and put in it:

```
cellpose_tool\
    segment_folder.py      (from segmentation\ in this repository)
    GRAMW_v4               (model file from the Releases page - no file extension)
    tools\                 (optional: scan_speed.py, diagnose_speed.py)
```

Keep **only one copy** of `segment_folder.py` on each computer, so you always know which version
FIJI runs. Every run prints the script version in its first line (currently `1.0 (2026-10-24)`).

---

## 5. Install the FIJI macro

1. Copy `segmentation\Segment_GRAMW.ijm` into `Fiji.app\scripts\Plugins\`.
2. Open it in a text editor (or in FIJI: Plugins > New > Macro, File > Open) and edit the three
   paths at the top. Use **double backslashes**:

```
PYTHON = "C:\\Users\\<you>\\AppData\\Local\\miniforge3\\envs\\cellpose\\python.exe";
SCRIPT = "C:\\Users\\<you>\\Desktop\\cellpose_tool\\segment_folder.py";
MODEL  = "C:\\Users\\<you>\\Desktop\\cellpose_tool\\GRAMW_v4";
```

   `PYTHON` is the path you wrote down in step 2.
3. Restart FIJI. The macro appears as **Plugins > Segment GRAMW**.

**Optional check from inside FIJI** (Plugins > New > Macro, paste, Run):

```javascript
PYTHON = "C:\\Users\\<you>\\AppData\\Local\\miniforge3\\envs\\cellpose\\python.exe";
if (!File.exists(PYTHON)) exit("Python not found:\n" + PYTHON);
out = exec(PYTHON, "-c", "import sys, importlib.util as u; print(sys.executable); print('cellpose:', 'OK' if u.find_spec('cellpose') else 'MISSING'); print('torch:', 'OK' if u.find_spec('torch') else 'MISSING')");
print(out);
```

The Log window should show the Python path and `cellpose: OK`, `torch: OK`.

---

## 6. First run (benchmark)

1. Put 3-5 test images in a folder (multichannel TIFFs, GRAM-W as channel 1, with pixel size
   saved in the file - check in FIJI under Image > Properties).
2. Run **Plugins > Segment GRAMW**:
   - **Image folder**: your test folder
   - **ROI output folder**: leave blank (creates `<image folder>_ROIs`) or choose one
   - **GRAM-W channel**: 1 (FIJI numbering)
   - tick **Benchmark only (first 3 images)**
3. A console window shows progress. The first lines should read:

```
segment_folder.py version 1.0 (2026-10-24)
images: ...
ROIs + log: ...
segmenting at 0.35 um/pixel | min area SR 200 um2, non-SR 200 um2
model loaded in ... s | weights torch.float32
```

   followed by one line per image (`N cells, xx.x s`). Press Enter to close the window.
4. Open an image in FIJI and drag its `_ROI.zip` onto FIJI to check the outlines.

The first run also creates `segmentation_log.csv` in the ROI folder (cells found, seconds per
image, pixel size, notes such as removed small objects or skipped images).

---

## Settings reference

All settings have validated defaults in `segment_folder.py`; the FIJI macro passes only the
folders, the model and the channel. To change a default, edit its `default=` line near the top of
the script **and raise `VERSION`**, so results from different settings stay distinguishable.

| Option | Default | Meaning |
|---|---|---|
| `--channel` | 0 | GRAM-W channel, 0-based (FIJI channel 1 = 0). Set from the macro dialog. |
| `--target` | 0.35 | pixel size (um) the image is resampled to before Cellpose |
| `--edge` | 0.8 | cells closer than this (um) to the image border are removed |
| `--min-area-sr` | 200 | objects smaller than this (um^2) are removed in SR images |
| `--min-area-nonsr` | 200 | same for non-SR images |
| `--sr-max-pixel` | 0.09 | images with a pixel size below this (um) count as SR |
| `--threads` | all cores | CPU threads |
| `--overwrite` | off | replace existing `_ROI.zip` files (otherwise they are skipped) |
| `--benchmark` | off | only the first 3 images |

Command-line use (Miniforge Prompt, environment active):

```
python segment_folder.py --input "D:\data\exp1" --output "D:\data\exp1_ROIs" --model "C:\Users\<you>\Desktop\cellpose_tool\GRAMW_v4"
```

**Why these values**
- **0.35 um/pixel**: on the validation images it gave the same accuracy as 0.26 um/pixel
  (normal cells, AP@0.5 = 0.96) while needing 1 Cellpose tile for SR and 4 for non-SR 1200 x 1200
  images, i.e. 2.5-3x faster on CPU. 0.52 um/pixel was rejected because outlines became blocky.
- **float32**: the model is loaded in 32-bit precision. bfloat16 was ~28x slower on CPUs.
- **200 um^2**: removes fragments and debris; the smallest real cells seen were ~250 um^2 (SR)
  and ~300 um^2 (non-SR).

**Different image sizes or binning**: the speed steps above assume 1200 x 1200 images. For
another camera size run `tools\scan_speed.py` on one image of the new type (it prints the time
per image at several pixel sizes) and choose the finest pixel size on the fast step.

---

## Troubleshooting

**T1. `python` runs the wrong Python** (e.g. `anaconda3\python.exe` or version 3.8)
The `(cellpose)` label in the prompt does not prove the environment is used. Always check with
`python -c "import sys; print(sys.executable)"`. Use the environment's Python by its **full path**
(`...\envs\cellpose\python.exe -m pip install ...`); this always works, with or without activation.

**T2. `conda create` fails with a permission error**, or `conda env list` shows base in
`C:\ProgramData\miniforge3`
That is an all-users installation you cannot write to. Create the environment in your own folder:
```
conda create -p C:\Users\<you>\envs\cellpose python=3.11 -y
```
The Python path is then `C:\Users\<you>\envs\cellpose\python.exe`.

**T3. `conda create` fails with `Could not find 'share/conda-launchers/cli-64.exe'`**
A problem in some recent conda versions. Try, in order:
```
conda install -n base -c conda-forge --override-channels --force-reinstall conda-launchers -y
mamba create -p C:\Users\<you>\envs\cellpose -c conda-forge python=3.11 -y
```
If both fail, skip conda: install **Python 3.11 from python.org** (untick "Use admin privileges"),
then
```
py -3.11 -m venv C:\Users\<you>\envs\cellpose311
C:\Users\<you>\envs\cellpose311\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cpu
C:\Users\<you>\envs\cellpose311\Scripts\python.exe -m pip install "cellpose>=4,<5" roifile tifffile scikit-image
```
Note the `\Scripts\` folder in venv paths.

**T4. `pip` error `Invalid version: '4.0.0-unsupported'`**
pip is running inside an old Anaconda base environment (see T1). Use the environment's
`python -m pip` instead.

**T5. "Model file not found"**
The `MODEL` path in the macro is wrong (e.g. Desktop vs. user folder). The script stops instead
of silently using Cellpose's default model.

**T6. Very slow (minutes per image)**
Check that the run prints `weights torch.float32`. Run `tools\diagnose_speed.py <image> <model>`
to compare float32 and bfloat16 on your CPU. On laptops, keep the charger connected and use the
high-performance power mode.

**T7. Images "SKIPPED - no pixel size in file"**
Set the calibration in FIJI (Image > Properties: unit `micron`, pixel width/height, e.g. 0.11)
and save, then run again.

**T8. Images "skipped (ROI file exists)"**
Existing ROI sets are protected (they may already be reviewed). Tick *Overwrite* in the macro
only for folders that have not been reviewed yet.

**T9. `UserWarning: Sparse invariant checks are implicitly disabled`**
Harmless message from PyTorch; ignore it.

---

## About the model

**GRAMW_v4** is Cellpose-SAM fine-tuned on 43 annotated images of EGFP-GRAM-W cells (SR and
non-SR, several treatments), with every cell outlined, including cells at the image edge and
abnormal cells (tagged `abn_`). It therefore finds all cells; abnormal cells are removed during
the review step. Validation on 14 held-out images, normal cells, at 0.35 um/pixel:
AP@0.5 = 0.96, AP@0.9 = 0.88 (SR: 1.00 / 1.00; non-SR: 0.93 / 0.79).
These validation images also guided the choice of settings, so report scores on fresh images
for publication.

Training notebooks (Google Colab and Kaggle) are in `training\`.
