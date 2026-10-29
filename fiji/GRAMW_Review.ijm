// GRAMW_Review.ijm  -  review Cellpose ROIs one image at a time
//
// INSTALL: copy this file to  Fiji.app\scripts\Plugins\  and restart FIJI.
//          Run it from  Plugins > GRAMW Review .
//          (Remove the older toolset copy from Fiji.app\macros\toolsets\ if you installed it.)
//
// While reviewing, a small "ROI review" window stays open. You can still draw on the image
// and use the ROI Manager. When an image is done:
//   OK (or Enter)   save and go to the next image
//   Shift + OK      save and go back one image
//   Alt + OK        skip this image without saving
//   Space + OK      undo all edits on this image (reload its ROIs)
//   Esc             stop the review (current image not saved; resume later)
// Editing:
//   add a cell      draw the outline (freehand tool), press t
//   delete a cell   click its outline or label (or its name in the ROI Manager),
//                   then click "Delete" in the ROI Manager
//
// Images are only displayed, never saved. ROIs are saved to <ROI folder>\<image>_ROI.zip.
// The first time an ROI file is overwritten, the model's original is kept in
// <ROI folder>\original_model_ROIs\ . Progress is logged in <ROI folder>\review_log.csv.
// Every step is also written to <ROI folder>\review_trace.txt; if FIJI stops unexpectedly,
// the last lines of that file show where (send them when reporting a problem).

var imgDir = "";
var roiDir = "";
var origDir = "";
var logPath = "";
var files = newArray(0);
var idx = 0;
var maxC = 1;
var showCh = newArray(0);
var lutCh = newArray(0);
var contrastMode = "Auto (each image)";
var roiColor = "yellow";
var imgID = 0;
var nBefore = 0;
var fixedMin = newArray(0);
var fixedMax = newArray(0);
var winX = -1;          // image window position and zoom, remembered between images
var winY = -1;
var lastZoom = 0;
var traceFile = "";     // step-by-step trace for troubleshooting
var nBaseline = 0;      // number of images that were open before the review started


// ================================================================ main loop
requires("1.54f");                      // stops with a clear message if FIJI is too old
startReview();
while (idx < files.length) {
    openCurrent();
    msg = "Image " + (idx + 1) + " of " + files.length + "\n \n"
        + "Edit the ROIs:\n"
        + "   add:      draw the outline, then press  t\n"
        + "   delete:   click the ROI, then 'Delete' in the ROI Manager\n \n"
        + "OK (or Enter)    save + next image\n"
        + "Shift + OK         save + previous image\n"
        + "Alt + OK            skip, don't save\n"
        + "Space + OK        undo edits on this image\n"
        + "Esc                    stop (resume later)";
    waitForUser("ROI review", msg);

    action = "next";
    if (isKeyDown("alt")) action = "skip";
    else if (isKeyDown("shift")) action = "back";
    else if (isKeyDown("space")) action = "reload";
    setKeyDown("none");
    trace("button: " + action);

    if (action == "reload") {
        closeCurrent();
        continue;                       // reopen the same image with its saved ROIs
    }
    if (action != "skip") saveCurrent();
    closeCurrent();
    if (action == "back") idx = maxOf(0, idx - 1);
    else idx = idx + 1;
}
finishReview();


// ================================================================ start
function startReview() {
    Dialog.create("ROI review - folders");
    Dialog.addDirectory("Image folder (original TIFFs)", "");
    Dialog.addDirectory("ROI folder (<image>_ROI.zip)", "");
    Dialog.addCheckbox("Skip images already reviewed (resume)", true);
    Dialog.addCheckbox("Also include images that have no ROI file (start empty)", false);
    Dialog.show();
    imgDir = withSlash(Dialog.getString());
    roiDir = withSlash(Dialog.getString());
    resume = Dialog.getCheckbox();
    includeNoRoi = Dialog.getCheckbox();
    if (!File.isDirectory(imgDir)) exit("Image folder not found:\n" + imgDir);
    if (!File.isDirectory(roiDir)) exit("ROI folder not found:\n" + roiDir);
    origDir = roiDir + "original_model_ROIs" + File.separator;
    logPath = roiDir + "review_log.csv";
    traceFile = roiDir + "review_trace.txt";
    trace("START  FIJI " + getVersion() + " | Java " + getInfo("java.version") + " | " + getInfo("os.name")
          + " | screen " + screenWidth + " x " + screenHeight + " | max memory " + round(IJ.maxMemory() / 1048576) + " MB");

    // images already reviewed, from the log
    reviewed = "";
    if (resume && File.exists(logPath)) {
        lines = split(File.openAsString(logPath), "\n");
        for (i = 1; i < lines.length; i++) {
            parts = split(lines[i], ",");
            if (parts.length > 0) reviewed = reviewed + "|" + parts[0] + "|";
        }
    }

    // images to review
    all = getFileList(imgDir);
    list = newArray(0);
    nNoRoi = 0;
    nDone = 0;
    for (i = 0; i < all.length; i++) {
        name = all[i];
        low = toLowerCase(name);
        if (!(endsWith(low, ".tif") || endsWith(low, ".tiff"))) continue;
        if (!File.exists(roiPathFor(name)) && !includeNoRoi) { nNoRoi++; continue; }
        if (indexOf(reviewed, "|" + name + "|") >= 0) { nDone++; continue; }
        list = Array.concat(list, name);
    }
    if (list.length == 0)
        exit("Nothing to review.\n \n" + nDone + " already reviewed, " + nNoRoi + " without an ROI file.");
    files = list;
    trace(files.length + " images to review, " + nDone + " already reviewed, " + nNoRoi + " without ROI file");

    // channel counts, read from file headers (fast, pixels are not loaded)
    List.setCommands;
    if (List.get("Bio-Formats Macro Extensions") == "")
        exit("This macro needs FIJI with Bio-Formats.\nIn FIJI: Help > Update..., apply all updates, restart.");
    List.clear();
    run("Bio-Formats Macro Extensions");
    maxC = 1;
    cnt = newArray(11);
    for (i = 0; i < files.length; i++) {
        showProgress(i, files.length);
        Ext.setId(imgDir + files[i]);
        Ext.getSizeC(c);
        Ext.close();
        if (c > maxC) maxC = c;
        if (c <= 10) cnt[c] = cnt[c] + 1;
    }
    summary = "";
    for (c = 1; c <= 10; c++)
        if (cnt[c] > 0) summary = summary + cnt[c] + " image(s) with " + c + " channel(s)   ";

    // display choices
    luts = newArray("Green", "Magenta", "Cyan", "Red", "Blue", "Yellow", "Grays");
    Dialog.create("ROI review - display");
    Dialog.addMessage(files.length + " images to review  (" + nDone + " already reviewed, "
                      + nNoRoi + " without ROI file)\n" + summary);
    for (c = 1; c <= maxC; c++) {
        isFirst = false;
        if (c == 1) isFirst = true;
        Dialog.addCheckbox("Show channel " + c, isFirst);
        Dialog.addToSameRow();
        Dialog.addChoice("colour", luts, luts[(c - 1) % luts.length]);
    }
    Dialog.addChoice("Contrast (display only)", newArray("Auto (each image)",
                     "Auto, same for all images (set on the first)", "As saved in the file"), contrastMode);
    Dialog.addChoice("ROI colour", newArray("yellow", "cyan", "red", "white", "orange", "magenta"), roiColor);
    Dialog.show();
    showCh = newArray(maxC);
    lutCh = newArray(maxC);
    for (c = 0; c < maxC; c++) {
        showCh[c] = Dialog.getCheckbox();
        lutCh[c] = Dialog.getChoice();
    }
    contrastMode = Dialog.getChoice();
    roiColor = Dialog.getChoice();

    fixedMin = newArray(0);
    fixedMax = newArray(0);
    File.makeDirectory(origDir);
    if (!File.exists(logPath))
        File.saveString("image,cells_before,cells_after,reviewed_at\n", logPath);
    nBaseline = nImages;
    roiManager("reset");
    roiManager("Associate", "false");
    roiManager("UseNames", "false");
    setTool("freehand");
    idx = 0;
}


// ================================================================ open one image
function openCurrent() {
    name = files[idx];
    trace("opening " + (idx + 1) + "/" + files.length + ": " + name);
    open(imgDir + name);
    imgID = getImageID();
    getDimensions(w, h, nC, nZ, nT);
    trace("opened: " + w + " x " + h + " px, " + nC + " channel(s), " + nZ + " z, " + nT + " t, " + bitDepth() + "-bit");
    if (nC == 1 && nSlices > 1) {       // channels stored as plain slices
        run("Stack to Hyperstack...", "order=xyczt(default) channels=" + nSlices
            + " slices=1 frames=1 display=Composite");
        imgID = getImageID();
        getDimensions(w, h, nC, nZ, nT);
    }
    if (nC > 1) {
        if (!is("composite")) run("Make Composite", "display=Composite");
        Stack.setDisplayMode("composite");
    }

    active = "";
    for (c = 1; c <= nC; c++) {
        if (nC > 1) Stack.setChannel(c);
        if (c <= maxC) run(lutCh[c - 1]);
        applyContrast(c);
        if (c <= maxC && showCh[c - 1]) active = active + "1";
        else active = active + "0";
    }
    if (nC > 1) {
        if (indexOf(active, "1") < 0) active = "1" + substring(active, 1);
        Stack.setActiveChannels(active);
        Stack.setChannel(indexOf(active, "1") + 1);
    }

    // size and place the window. First image: fit below the FIJI bar, leaving room on the
    // right for the ROI Manager. Afterwards: reuse whatever zoom/position you last left it at.
    if (lastZoom > 0) zoom = lastZoom;
    else zoom = minOf((screenHeight - 260) / h, (screenWidth * 0.55) / w);
    run("Set... ", "zoom=" + floor(zoom * 100) + " x=" + floor(w / 2) + " y=" + floor(h / 2));
    if (winX >= 0) setLocation(winX, winY);
    else setLocation(0, 130);

    roiManager("reset");
    if (File.exists(roiPathFor(name))) roiManager("Open", roiPathFor(name));
    nBefore = roiManager("count");
    if (nBefore > 0) roiManager("Set Color", roiColor);
    roiManager("Show All with labels");
    showInfo(name);
    trace("ready: " + nBefore + " ROIs shown, zoom " + d2s(getZoom(), 2));
}

function applyContrast(c) {
    if (startsWith(contrastMode, "As saved")) return;
    if (startsWith(contrastMode, "Auto (each")) {
        run("Enhance Contrast", "saturated=0.35");      // display range only, pixels unchanged
        return;
    }
    if (fixedMin.length < c) {                         // first image: measure and remember
        run("Enhance Contrast", "saturated=0.35");
        getMinAndMax(lo, hi);
        fixedMin = Array.concat(fixedMin, lo);
        fixedMax = Array.concat(fixedMax, hi);
    } else {
        setMinAndMax(fixedMin[c - 1], fixedMax[c - 1]);
    }
}

function showInfo(name) {
    print("\\Clear");
    print("ROI REVIEW   image " + (idx + 1) + " of " + files.length);
    print(name);
    print(nBefore + " ROIs loaded");
    print(" ");
    print("Do not press the Delete key on the image (it erases pixels on screen);");
    print("delete ROIs with the ROI Manager's Delete button.");
}


// ================================================================ save / close
function saveCurrent() {
    name = files[idx];
    roiPath = roiPathFor(name);
    backup = origDir + baseName(name) + "_ROI.zip";
    if (File.exists(roiPath) && !File.exists(backup)) File.copy(roiPath, backup);

    n = roiManager("count");
    if (n > 0) {
        if (imgID != 0 && isOpen(imgID)) selectImage(imgID);
        for (i = 0; i < n; i++) {
            roiManager("select", i);
            Roi.setPosition(0);                         // ROI applies to every channel
            roiManager("update");
            roiManager("rename", "cell_" + IJ.pad(i + 1, 3));
        }
        roiManager("deselect");
        roiManager("Save", roiPath);
    } else if (File.exists(roiPath)) {
        ok = File.delete(roiPath);                      // all cells removed
    }

    getDateAndTime(year, month, dow, day, hour, minute, sec, msec);
    stamp = "" + year + "-" + IJ.pad(month + 1, 2) + "-" + IJ.pad(day, 2) + " "
            + IJ.pad(hour, 2) + ":" + IJ.pad(minute, 2);
    File.append(name + "," + nBefore + "," + n + "," + stamp, logPath);
    trace("saved: " + n + " ROIs");
}

function closeCurrent() {
    if (imgID != 0 && isOpen(imgID)) {
        selectImage(imgID);
        getLocationAndSize(wx, wy, ww, wh);             // remember where you left the window
        winX = wx;
        winY = wy;
        lastZoom = getZoom();
        setOption("Changes", false);                    // never ask to save the image
        close();
    }
    while (nImages > nBaseline) {                       // close any leftover windows from this image
        selectImage(nImages);
        setOption("Changes", false);
        close();
    }
    imgID = 0;
    roiManager("reset");
    call("java.lang.System.gc");                        // ask Java to free memory now
    trace("closed");
}

function finishReview() {
    trace("FINISHED");
    roiManager("reset");
    print("\\Clear");
    print("ROI review finished: " + files.length + " images.");
    print("Log: " + logPath);
    showMessage("ROI review", "All images reviewed.\n \nLog: " + logPath);
}


// ================================================================ helpers
function withSlash(p) {
    if (p == "") return p;
    if (!endsWith(p, "/") && !endsWith(p, "\\")) p = p + File.separator;
    return p;
}

function baseName(name) {
    dot = lastIndexOf(name, ".");
    if (dot > 0) return substring(name, 0, dot);
    return name;
}

function roiPathFor(name) {
    return roiDir + baseName(name) + "_ROI.zip";
}

function trace(msg) {
    if (traceFile == "") return;
    getDateAndTime(year, month, dow, day, hour, minute, sec, msec);
    File.append("" + IJ.pad(hour, 2) + ":" + IJ.pad(minute, 2) + ":" + IJ.pad(sec, 2) + "  " + msg
                + "   [memory " + IJ.freeMemory() + "]", traceFile);
}
