// Split_Selected_Channels.ijm
// Splits every multichannel TIFF in a folder and saves only the channels you choose.
// Channel n of "image.tif" is saved as  <image folder>\Cn\Cn-image.tif
// (same "Cn-" prefix as ImageJ's Split Channels, so the quantification macro can match it).
// Original images are not changed. Calibration (pixel size) is kept.
//
// INSTALL: copy to  Fiji.app\scripts\Plugins\  , restart FIJI, run  Plugins > Split Selected Channels

// ---------------------------------------------------------------- 1. folder
Dialog.create("Split channels - folder");
Dialog.addDirectory("Image folder", "");
Dialog.show();
dir = Dialog.getString();
if (!endsWith(dir, "/") && !endsWith(dir, "\\")) dir = dir + File.separator;
if (!File.isDirectory(dir)) exit("Folder not found:\n" + dir);

all = getFileList(dir);
files = newArray(0);
for (i = 0; i < all.length; i++) {
    low = toLowerCase(all[i]);
    if (endsWith(low, ".tif") || endsWith(low, ".tiff")) files = Array.concat(files, all[i]);
}
if (files.length == 0) exit("No TIFF images found in:\n" + dir);

// ---------------------------------------------------------------- 2. channel counts (file headers only)
run("Bio-Formats Macro Extensions");
fileC = newArray(files.length);
maxC = 1;
cnt = newArray(11);
for (i = 0; i < files.length; i++) {
    showProgress(i, files.length);
    Ext.setId(dir + files[i]);
    Ext.getSizeC(c);
    Ext.close();
    fileC[i] = c;
    if (c > maxC) maxC = c;
    if (c <= 10) cnt[c] = cnt[c] + 1;
}
summary = "";
for (c = 1; c <= 10; c++)
    if (cnt[c] > 0) summary = summary + cnt[c] + " image(s) with " + c + " channel(s)   ";

// ---------------------------------------------------------------- 3. choose channels
Dialog.create("Split channels - choose");
Dialog.addMessage(files.length + " images found\n" + summary);
Dialog.addMessage("Save these channels (each into its own folder C1, C2, ... inside the image folder):");
for (c = 1; c <= maxC; c++) Dialog.addCheckbox("Channel " + c, false);
Dialog.addCheckbox("Overwrite files that already exist", false);
Dialog.show();
doCh = newArray(maxC);
nCh = 0;
for (c = 0; c < maxC; c++) {
    doCh[c] = Dialog.getCheckbox();
    if (doCh[c]) nCh++;
}
overwrite = Dialog.getCheckbox();
if (nCh == 0) exit("No channel selected.");
for (c = 1; c <= maxC; c++)
    if (doCh[c - 1]) File.makeDirectory(dir + "C" + c);

// ---------------------------------------------------------------- 4. split and save
setBatchMode(true);
print("\\Clear");
print("Split Selected Channels: " + dir);
nSaved = 0;
nExisting = 0;
nMissing = 0;
for (k = 0; k < files.length; k++) {
    name = files[k];
    showProgress(k, files.length);
    showStatus("Splitting " + (k + 1) + "/" + files.length + ": " + name);
    print("[" + (k + 1) + "/" + files.length + "] " + name);

    open(dir + name);
    id = getImageID();
    getDimensions(w, h, nC, nZ, nT);
    chAsSlices = false;                      // channels stored as a plain stack
    if (nC == 1 && nSlices > 1 && fileC[k] == nSlices) {
        chAsSlices = true;
        nC = nSlices;
    }

    for (c = 1; c <= maxC; c++) {
        if (!doCh[c - 1]) continue;
        out = dir + "C" + c + File.separator + "C" + c + "-" + name;
        if (File.exists(out) && !overwrite) {
            print("   C" + c + ": already exists, skipped");
            nExisting++;
            continue;
        }
        if (c > nC) {
            print("   C" + c + ": image has only " + nC + " channel(s)");
            nMissing++;
            continue;
        }
        selectImage(id);
        run("Select None");
        if (chAsSlices) run("Duplicate...", "title=split_tmp duplicate range=" + c + "-" + c);
        else if (nC > 1) run("Duplicate...", "title=split_tmp duplicate channels=" + c);
        else run("Duplicate...", "title=split_tmp duplicate");
        saveAs("Tiff", out);
        close();
        nSaved++;
    }
    selectImage(id);
    close();
}
setBatchMode(false);

msg = "Saved " + nSaved + " channel image(s).";
if (nExisting > 0) msg = msg + "\n" + nExisting + " already existed and were skipped (tick Overwrite to replace).";
if (nMissing > 0) msg = msg + "\n" + nMissing + " requested channel(s) were missing from some images (see Log).";
print(msg);
showMessage("Split channels", msg + "\n \nOutput folders: " + dir + "C1, C2, ...");
