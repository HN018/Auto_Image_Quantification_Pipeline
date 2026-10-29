# Changelog

All notable changes to the pipeline. Raise the version when settings or outputs change, and note it here.

## v1.0 - 2026-10

### Segmentation
- `segment_folder.py` version 1.0 (2026-10-24): model GRAMW_v4 (Cellpose-SAM fine-tuned on 43 images,
  all cells outlined incl. abnormal ones), segmentation at 0.35 um/pixel, float32 on CPU, cells within
  0.8 um of the border removed, objects < 200 um^2 removed (SR and non-SR), ROI output folder selectable.
- `Segment_GRAMW.ijm`: FIJI launcher with progress window.

### FIJI macros
- `GRAMW_Review.ijm`: OK / Shift / Alt / Space + OK workflow, resume from `review_log.csv`, backup of
  model ROIs, ROI renumbering and channel-position reset; FIJI version and Bio-Formats checks;
  `review_trace.txt` troubleshooting trace; leftover windows closed and memory freed after each image.
- `Split_Selected_Channels.ijm`: saves selected channels to `C<n>\C<n>-<image>.tif`.
- `GRAMW_Quantify.ijm`: whole-cell / in-mask / per-particle measurement; constant background
  subtraction per channel; particle size filter in mask pixels; optional exclusion of particles
  touching the cell outline; area-weighted cell mean; areas in px and um^2; Total_Intensity column;
  debug mode; time-stamped outputs and settings file.
