// GRAMW_Quantify.ijm  -  per-cell quantification with ROIs and (optional) masks
//
// INSTALL: copy to  Fiji.app\scripts\Plugins\  , restart FIJI, run  Plugins > GRAMW Quantify
//
// Inputs
//   original images : multichannel TIFFs
//   mask folder     : optional. Binary masks (0 = background, non-zero = mask), same size as the
//                     images, named <image>.tif or C<n>-<image>.tif (ImageJ "Split Channels" prefix)
//   ROI folder      : <image>_ROI.zip  (one ROI per cell)
// Background
//   per channel, a fixed value is subtracted from the 16-bit image (Process > Math > Subtract);
//   0 = no subtraction. Values below 0 become 0, as with the ImageJ command.
// Methods (default: Within mask + per-particle table when a mask folder is given)
//   Whole cell                         : Area, Mean, Min, Max of each cell ROI
//   Within mask (per cell)             : mask particles inside each cell (size filter in mask pixels,
//                                        optional exclusion of particles touching the cell outline);
//                                        cell Mean = sum(particle area x particle mean) / sum(particle area); Total_Intensity = Mask_Area_um2 x Mean
//   Within mask + per-particle table   : as above, plus one row per particle
// Output, in <original images>\measurements\ :
//   C<n>_<method>_per_cell_<date_time>.csv
//   C<n>_<method>_per_particle_<date_time>.csv   (per-particle option only)
//   settings_<date_time>.txt                      (all settings, skipped images, notes)
//   In DEBUG mode all file names start with DEBUG_.

var dp = 3;
var debugMode = false;
var skipCells = false;
var notes = "";
var origID = 0;
var maskID = 0;

// ======================================================================= 1. folders
Dialog.create("Quantify - folders");
Dialog.addDirectory("Original images (multichannel TIFFs)", "");
Dialog.addDirectory("Mask folder (optional - leave blank for whole-cell only)", "");
Dialog.addDirectory("ROI folder (<image>_ROI.zip)", "");
Dialog.show();
imgDir  = withSlash(Dialog.getString());
maskDir = withSlash(Dialog.getString());
roiDir  = withSlash(Dialog.getString());
if (!File.isDirectory(imgDir)) exit("Image folder not found:\n" + imgDir);
if (!File.isDirectory(roiDir)) exit("ROI folder not found:\n" + roiDir);
useMask = false;
if (maskDir != "") {
    if (!File.isDirectory(maskDir)) exit("Mask folder not found:\n" + maskDir);
    useMask = true;
}

// ======================================================================= 2. match files
maskFiles = newArray(0);
if (useMask) {
    ml = getFileList(maskDir);
    for (i = 0; i < ml.length; i++)
        if (isTiff(ml[i])) maskFiles = Array.concat(maskFiles, ml[i]);
}
all = getFileList(imgDir);
names = newArray(0);
masksFor = newArray(0);
skipped = "";
for (i = 0; i < all.length; i++) {
    n = all[i];
    if (!isTiff(n)) continue;
    if (!File.exists(roiDir + baseName(n) + "_ROI.zip")) { skipped = skipped + n + "\tno ROI file\n"; continue; }
    m = "-";
    if (useMask) {
        m = findMask(n, maskFiles);
        if (m == "") { skipped = skipped + n + "\tno matching mask\n"; continue; }
        if (m == "AMBIGUOUS") { skipped = skipped + n + "\tmore than one matching mask\n"; continue; }
    }
    names = Array.concat(names, n);
    masksFor = Array.concat(masksFor, m);
}
if (names.length == 0) exit("No images to measure.\n \nSkipped:\n" + skipped);

// channel counts from the file headers (fast)
run("Bio-Formats Macro Extensions");
maxC = 1;
cnt = newArray(11);
for (i = 0; i < names.length; i++) {
    showProgress(i, names.length);
    Ext.setId(imgDir + names[i]);
    Ext.getSizeC(c);
    Ext.close();
    if (c > maxC) maxC = c;
    if (c <= 10) cnt[c] = cnt[c] + 1;
}
summary = "";
for (c = 1; c <= 10; c++)
    if (cnt[c] > 0) summary = summary + cnt[c] + " image(s) with " + c + " channel(s)   ";
nSkip = lengthOf(skipped) - lengthOf(replace(skipped, "\n", ""));

// ======================================================================= 3. settings
if (useMask) methods = newArray("Whole cell", "Within mask (per cell)", "Within mask + per-particle table");
else methods = newArray("Whole cell");

Dialog.create("Quantify - settings");
Dialog.addMessage(names.length + " images matched (" + nSkip + " skipped, listed in the settings file)\n" + summary);
Dialog.addMessage("Channels to quantify, and the value subtracted from each (0 = none):");
for (c = 1; c <= maxC; c++) {
    Dialog.addCheckbox("Channel " + c, false);
    Dialog.addToSameRow();
    Dialog.addNumber("subtract", 100);
}
Dialog.addChoice("Method", methods, methods[methods.length - 1]);   // default: last option (per-particle table if a mask folder was given)
if (useMask) {
    Dialog.addNumber("Min particle size (mask pixels)", 9);
    Dialog.addString("Max particle size (mask pixels)", "Infinity");
    Dialog.addCheckbox("Exclude particles touching the cell outline", true);
}
Dialog.addNumber("Decimal places", 3);
Dialog.addMessage(" ");
Dialog.addCheckbox("DEBUG: step through one image, pausing at every step", false);
Dialog.addChoice("Debug image", names, names[0]);
Dialog.show();

doCh = newArray(maxC);
bgV = newArray(maxC);
for (c = 0; c < maxC; c++) doCh[c] = Dialog.getCheckbox();
excludeEdge = false;
if (useMask) excludeEdge = Dialog.getCheckbox();
debugMode = Dialog.getCheckbox();
for (c = 0; c < maxC; c++) bgV[c] = Dialog.getNumber();
minSize = 0;
maxSize = "Infinity";
if (useMask) minSize = Dialog.getNumber();
dp = Dialog.getNumber();
method = Dialog.getChoice();
debugImage = Dialog.getChoice();
if (useMask) maxSize = Dialog.getString();

nCh = 0;
for (c = 0; c < maxC; c++) if (doCh[c]) nCh++;
if (nCh == 0) exit("No channel selected.");

mode = "wholecell";
methodTag = "WholeCell";
perParticle = false;
if (startsWith(method, "Within mask")) { mode = "mask"; methodTag = "InMask"; }
if (endsWith(method, "table")) perParticle = true;

if (debugMode) {                                   // only the chosen image
    for (k = 0; k < names.length; k++)
        if (names[k] == debugImage) dbgMask = masksFor[k];
    names = newArray(debugImage);
    masksFor = newArray(dbgMask);
}

// ======================================================================= 4. output files
stamp = timeStamp();
prefix = "";
if (debugMode) prefix = "DEBUG_";
outDir = imgDir + "measurements" + File.separator;
File.makeDirectory(outDir);
cellCsv = newArray(maxC);
partCsv = newArray(maxC);
if (mode == "wholecell") cellHdr = "Image,Channel,Cell,Area_px,Area_um2,Mean,Min,Max,Total_Intensity";
else cellHdr = "Image,Channel,Cell,Cell_Area_px,Cell_Area_um2,Particle_Count,Mask_Area_px,Mask_Area_um2,"
             + "Mask_Fraction,Mean_Particle_Area_px,Mean_Particle_Area_um2,Mean,Min,Max,Total_Intensity";
partHdr = "Image,Channel,Cell,Particle,Area_px,Area_um2,Mean,Min,Max,Total_Intensity";
for (c = 1; c <= maxC; c++) {
    if (!doCh[c - 1]) continue;
    cellCsv[c - 1] = outDir + prefix + "C" + c + "_" + methodTag + "_per_cell_" + stamp + ".csv";
    File.saveString(cellHdr + "\n", cellCsv[c - 1]);
    if (perParticle) {
        partCsv[c - 1] = outDir + prefix + "C" + c + "_" + methodTag + "_per_particle_" + stamp + ".csv";
        File.saveString(partHdr + "\n", partCsv[c - 1]);
    }
}

// ======================================================================= 5. measure
if (!debugMode) setBatchMode(true);
roiManager("reset");
run("Set Measurements...", "area mean min redirect=None decimal=" + dp);
paOpts = "size=" + minSize + "-" + maxSize + " pixel display clear";
if (excludeEdge) paOpts = paOpts + " exclude";
if (debugMode) paOpts = paOpts + " show=Overlay";
else paOpts = paOpts + " show=Nothing";
nDone = 0;

for (k = 0; k < names.length; k++) {
    n = names[k];
    showProgress(k, names.length);
    showStatus("Quantify " + (k + 1) + "/" + names.length + ": " + n);
    print("[" + (k + 1) + "/" + names.length + "] " + n);

    // ---- original image and cell ROIs
    open(imgDir + n);
    origID = getImageID();
    getDimensions(w, h, nC, nZ, nT);
    chAsSlices = false;
    if (nC == 1 && nSlices > 1) {
        chAsSlices = true;
        nC = nSlices;
    } else if (nZ > 1 || nT > 1) {
        skipped = skipped + n + "\thas z-slices or time points (2D images only)\n";
        cleanup();
        continue;
    }
    getPixelSize(unit, pw, ph);
    pxArea = pw * ph;
    calOK = false;
    if (unit == "micron" || unit == "microns" || unit == "um" || unit == fromCharCode(181) + "m") calOK = true;
    if (!calOK) notes = notes + n + ": no micron calibration (unit '" + unit + "'), um2 columns are NaN\n";

    roiManager("reset");
    roiManager("Open", roiDir + baseName(n) + "_ROI.zip");
    nCells = roiManager("count");
    if (debugMode) {
        fitWindow(0);
        roiManager("Show All with labels");
        waitForUser("Step 1 - original image",
            n + "\n \n" + nC + " channel(s), " + w + " x " + h + " px, pixel size " + d2s(pw, 4) + " " + unit
            + "\n" + nCells + " cell ROIs loaded from " + baseName(n) + "_ROI.zip"
            + "\n \nCheck that the ROIs sit on the cells.");
    }

    // ---- mask: clean binary 0/255 with the original's pixel size
    if (mode == "mask") {
        open(maskDir + masksFor[k]);
        maskID = getImageID();
        if (getWidth() != w || getHeight() != h) {
            skipped = skipped + n + "\tmask size differs from image\n";
            cleanup();
            continue;
        }
        run("Properties...", "unit=" + unit + " pixel_width=" + pw + " pixel_height=" + ph);
        bd = bitDepth();
        if (bd == 8) setThreshold(1, 255);
        else if (bd == 16) setThreshold(1, 65535);
        else setThreshold(0.000001, 1e30);
        run("Convert to Mask");
        if (is("Inverting LUT")) run("Invert LUT");          // display only; mask pixels are 255
        rename("maskbin");
        if (debugMode) {
            fitWindow(1);
            roiManager("Show All with labels");
            getStatistics(a, mMean);
            waitForUser("Step 2 - mask",
                masksFor[k] + "\n \nBinarised: white = mask (" + d2s(mMean / 255 * 100, 2) + "% of the image)."
                + "\n \nCheck that white matches the structures you thresholded.");
        }
    }

    // ---- each selected channel
    for (c = 1; c <= maxC; c++) {
        if (!doCh[c - 1]) continue;
        if (c > nC) { notes = notes + n + ": has no channel " + c + "\n"; continue; }
        selectImage(origID);
        run("Select None");
        if (chAsSlices) run("Duplicate...", "title=signal_q duplicate range=" + c + "-" + c);
        else if (nC > 1) run("Duplicate...", "title=signal_q duplicate channels=" + c);
        else run("Duplicate...", "title=signal_q");
        sigID = getImageID();
        if (bgV[c - 1] > 0) run("Subtract...", "value=" + bgV[c - 1]);
        if (debugMode) {
            fitWindow(0);
            resetMinAndMax();
            run("Enhance Contrast", "saturated=0.35");
            roiManager("Show All with labels");
            getStatistics(a, sMean, sMin, sMax);
            waitForUser("Step 3 - channel " + c,
                "Channel " + c + " duplicated (" + bitDepth() + "-bit), minus " + bgV[c - 1]
                + "\nPixel values now " + sMin + " to " + sMax + "  (image mean " + d2s(sMean, 1) + ")"
                + "\n \nNext: each cell is measured and shown one by one.");
        }

        skipCells = false;
        for (i = 0; i < nCells; i++) {
            selectImage(sigID);
            roiManager("select", i);
            cellName = Roi.getName;
            if (cellName == "") cellName = "cell_" + IJ.pad(i + 1, 3);
            List.setMeasurements;
            cellArea = List.getValue("Area");
            cellPx = round(cellArea / pxArea);
            lead = "" + q(n) + "," + c + "," + q(cellName);     // "" first: tells FIJI this is text

            if (mode == "wholecell") {
                File.append(lead + "," + cellPx + "," + um2(cellArea, calOK) + "," + fmt(List.getValue("Mean"))
                            + "," + fmt(List.getValue("Min")) + "," + fmt(List.getValue("Max")) + "," + um2(cellArea * List.getValue("Mean"), calOK), cellCsv[c - 1]);
                pauseCell("Step 4 - cell " + (i + 1) + " of " + nCells,
                    cellName + "\n \nArea " + cellPx + " px (" + um2(cellArea, calOK) + " um2)"
                    + "\nMean " + fmt(List.getValue("Mean")) + "   Min " + fmt(List.getValue("Min"))
                    + "   Max " + fmt(List.getValue("Max")) + "\nTotal intensity " + um2(cellArea * List.getValue("Mean"), calOK));
                continue;
            }

            // particles of the mask inside this cell; intensities read from the signal image
            selectImage("maskbin");
            if (debugMode) run("Remove Overlay");
            roiManager("select", i);
            setThreshold(255, 255);
            run("Set Measurements...", "area mean min redirect=signal_q decimal=" + dp);
            run("Analyze Particles...", paOpts);
            run("Set Measurements...", "area mean min redirect=None decimal=" + dp);

            np = nResults;
            sumA = 0; sumAM = 0;
            pMin = NaN; pMax = NaN;
            for (r = 0; r < np; r++) {
                a = getResult("Area", r);
                m = getResult("Mean", r);
                mn = getResult("Min", r);
                mx = getResult("Max", r);
                sumA = sumA + a;
                sumAM = sumAM + a * m;
                if (r == 0 || mn < pMin) pMin = mn;
                if (r == 0 || mx > pMax) pMax = mx;
                if (perParticle)
                    File.append(lead + "," + (r + 1) + "," + round(a / pxArea) + "," + um2(a, calOK)
                                + "," + fmt(m) + "," + fmt(mn) + "," + fmt(mx) + "," + um2(a * m, calOK), partCsv[c - 1]);
            }
            run("Clear Results");

            maskPx = round(sumA / pxArea);
            wMean = NaN;
            meanPA = NaN;
            if (np > 0 && sumA > 0) {
                wMean = sumAM / sumA;                            // area-weighted mean
                meanPA = sumA / np;
            }
            meanPApx = NaN;
            if (np > 0) meanPApx = maskPx / np;
            File.append(lead + "," + cellPx + "," + um2(cellArea, calOK) + "," + np + "," + maskPx + ","
                        + um2(sumA, calOK) + "," + fmt(sumA / cellArea) + "," + fmt(meanPApx) + ","
                        + um2(meanPA, calOK) + "," + fmt(wMean) + "," + fmt(pMin) + "," + fmt(pMax) + "," + um2(sumAM, calOK), cellCsv[c - 1]);

            if (debugMode && !skipCells) {
                fitWindow(1);
                roiManager("select", i);
            }
            pauseCell("Step 4 - cell " + (i + 1) + " of " + nCells,
                cellName + "   (mask window: outlines = particles counted)"
                + "\n \nCell area " + cellPx + " px (" + um2(cellArea, calOK) + " um2)"
                + "\nParticles counted: " + np + "   mask area " + maskPx + " px ("
                + um2(sumA, calOK) + " um2), " + fmt(sumA / cellArea * 100) + "% of the cell"
                + "\nWeighted mean " + fmt(wMean) + "   Min " + fmt(pMin) + "   Max " + fmt(pMax) + "   Total intensity " + um2(sumAM, calOK));
        }
        selectImage(sigID);
        close();
    }
    if (debugMode) waitForUser("Done", "Results written to:\n" + outDir + "\n \nfiles starting with " + prefix + "C");
    cleanup();
    nDone++;
}
if (!debugMode) setBatchMode(false);

// ======================================================================= 6. settings file
s = "GRAMW_Quantify  " + stamp + "\n";
if (debugMode) s = s + "DEBUG run (one image)\n";
s = s + "\nOriginal images: " + imgDir + "\nROI folder: " + roiDir + "\n";
if (useMask) s = s + "Mask folder: " + maskDir + "\n";
s = s + "Method: " + method + "\n";
if (mode == "mask") {
    s = s + "Particle size: " + minSize + " - " + maxSize + " mask pixels (measured inside the cell)\n";
    s = s + "Exclude particles touching the cell outline: " + excludeEdge + "\n";
}
s = s + "Channels (value subtracted with Process > Math > Subtract):\n";
for (c = 1; c <= maxC; c++)
    if (doCh[c - 1]) s = s + "  C" + c + ": minus " + bgV[c - 1] + "\n";
s = s + "Decimal places: " + dp + "\n\n";
s = s + "How the numbers are calculated\n";
s = s + "- Subtraction is done on the original bit depth; values below 0 become 0.\n";
s = s + "- Areas: _px = pixel counts; _um2 = calibrated from each image's pixel size.\n";
s = s + "- Mask methods, per cell: Mean = sum(particle area x particle mean) / sum(particle area);\n";
s = s + "  Min/Max = lowest/highest pixel over the counted particles; Mask_Fraction = mask area / cell area.\n  Total_Intensity = area in um2 x Mean (per cell: Mask_Area_um2 x Mean = sum of particle area x mean; whole cell: Area_um2 x Mean).\n";
s = s + "- Particles are clipped to the cell outline; cells without particles: count 0, intensities NaN.\n";
s = s + "- Masks are binarised (non-zero = mask) and given the pixel size of their original image.\n\n";
s = s + "Measured " + nDone + " of " + names.length + " image(s).\n\n";
s = s + "Skipped images:\n" + skipped + "\nOther notes:\n" + notes;
File.saveString(s, outDir + prefix + "settings_" + stamp + ".txt");
roiManager("reset");
print("Done. Results in " + outDir);
if (!debugMode) showMessage("Quantify", "Done: " + nDone + " images measured.\n \nResults and settings in:\n" + outDir);


// ======================================================================= helpers
function pauseCell(title, msg) {
    if (!debugMode || skipCells) return;
    waitForUser(title, msg + "\n \nOK = next cell        Shift + OK = stop pausing for this channel");
    if (isKeyDown("shift")) {
        skipCells = true;
        setKeyDown("none");
    }
}

function fitWindow(slot) {          // debugMode display: slot 0 = left half, slot 1 = right half
    zoom = minOf((screenHeight - 260) / getHeight(), (screenWidth * 0.45) / getWidth());
    run("Set... ", "zoom=" + floor(zoom * 100) + " x=" + floor(getWidth() / 2) + " y=" + floor(getHeight() / 2));
    setLocation(slot * floor(screenWidth / 2), 130);
}

function um2(v, ok) {
    if (!ok) return "NaN";
    return "" + fmt(v);                 // "" first: tells FIJI the result is text
}

function fmt(v) {
    if (isNaN(v)) return "NaN";
    return d2s(v, dp);
}

function q(t) {
    return "\"" + t + "\"";
}

function cleanup() {                 // closes only the images this macro opened
    if (isOpen("signal_q")) close("signal_q");
    if (maskID != 0 && isOpen(maskID)) { selectImage(maskID); close(); }
    if (origID != 0 && isOpen(origID)) { selectImage(origID); close(); }
    maskID = 0;
    origID = 0;
    roiManager("reset");
    run("Clear Results");
}

function findMask(n, list) {
    b = baseName(n);
    found = "";
    count = 0;
    for (i = 0; i < list.length; i++) {
        mb = baseName(list[i]);
        hit = false;
        if (mb == b) hit = true;
        if (matches(mb, "C[0-9]+-\\Q" + b + "\\E")) hit = true;
        if (hit) { found = list[i]; count++; }
    }
    if (count > 1) return "AMBIGUOUS";
    return found;
}

function isTiff(name) {
    low = toLowerCase(name);
    if (endsWith(low, ".tif") || endsWith(low, ".tiff")) return true;
    return false;
}

function baseName(name) {
    dot = lastIndexOf(name, ".");
    if (dot > 0) return substring(name, 0, dot);
    return name;
}

function withSlash(p) {
    if (p == "") return p;
    if (!endsWith(p, "/") && !endsWith(p, "\\")) p = p + File.separator;
    return p;
}

function timeStamp() {
    getDateAndTime(year, month, dow, day, hour, minute, sec, msec);
    return "" + year + IJ.pad(month + 1, 2) + IJ.pad(day, 2) + "_" + IJ.pad(hour, 2) + IJ.pad(minute, 2);
}
