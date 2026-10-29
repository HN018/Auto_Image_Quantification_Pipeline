// Segment_GRAMW.ijm
// Runs the Cellpose GRAM-W segmentation (segment_folder.py) on a folder of images
// and writes <image>_ROI.zip files (and segmentation_log.csv) into a chosen ROI folder.
//
// ---- EDIT THESE THREE PATHS ONCE (use double backslashes \\) ----
PYTHON = "C:\\Users\\YOURNAME\\AppData\\Local\\miniforge3\\envs\\cellpose\\python.exe";
SCRIPT = "C:\\Users\\YOURNAME\\Desktop\\cellpose_tool\\segment_folder.py";
MODEL  = "C:\\Users\\YOURNAME\\Desktop\\cellpose_tool\\GRAMW_v4";
// -----------------------------------------------------------------

paths = newArray(PYTHON, SCRIPT, MODEL);
labels = newArray("Python", "Script", "Model");
for (i = 0; i < paths.length; i++) {
    if (!File.exists(paths[i]))
        exit(labels[i] + " not found:\n" + paths[i] + "\n \nEdit the paths at the top of this macro.");
}

Dialog.create("Cellpose GRAM-W segmentation");
Dialog.addDirectory("Image folder", "");
Dialog.addDirectory("ROI output folder (blank = new folder <image folder>_ROIs)", "");
Dialog.addNumber("GRAM-W channel (FIJI numbering)", 1);
Dialog.addCheckbox("Benchmark only (first 3 images)", false);
Dialog.addCheckbox("Overwrite existing _ROI.zip files", false);
Dialog.addCheckbox("Show progress window", true);
Dialog.show();
folder  = Dialog.getString();
outDir  = Dialog.getString();
channel = Dialog.getNumber() - 1;          // Python counts from 0
bench   = Dialog.getCheckbox();
over    = Dialog.getCheckbox();
showWin = Dialog.getCheckbox();

// a trailing backslash would break the quoting of the Windows command line
folder = stripSlash(folder);
outDir = stripSlash(outDir);
if (!File.isDirectory(folder))
    exit("Image folder not found:\n" + folder);
if (outDir == "")
    outDir = folder + "_ROIs";
if (!File.isDirectory(outDir)) {
    File.makeDirectory(outDir);
    if (!File.isDirectory(outDir))
        exit("Could not create the ROI folder:\n" + outDir);
}
if (over)
    showMessageWithCancel("Overwrite?", "Existing _ROI.zip files in the ROI folder will be REPLACED,\nincluding ones you may already have reviewed.\n \nContinue?");

args = newArray(PYTHON, SCRIPT, "--input", folder, "--output", outDir, "--model", MODEL, "--channel", "" + channel);
if (bench) args = Array.concat(args, "--benchmark");
if (over)  args = Array.concat(args, "--overwrite");

print("\\Clear");
print("Cellpose segmentation started");
print("  images: " + folder);
print("  ROIs:   " + outDir);
if (showWin) {
    // separate console window with live progress; the macro waits until it is closed
    args = Array.concat(args, "--pause");
    cmd = Array.concat(newArray("cmd", "/c", "start", "\"Cellpose\"", "/wait"), args);
} else {
    cmd = args;   // runs hidden; output appears in the Log when finished
}

if (cmd.length == 10) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9]);
else if (cmd.length == 11) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9], cmd[10]);
else if (cmd.length == 12) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9], cmd[10], cmd[11]);
else if (cmd.length == 13) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9], cmd[10], cmd[11], cmd[12]);
else if (cmd.length == 14) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9], cmd[10], cmd[11], cmd[12], cmd[13]);
else if (cmd.length == 15) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9], cmd[10], cmd[11], cmd[12], cmd[13], cmd[14]);
else if (cmd.length == 16) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9], cmd[10], cmd[11], cmd[12], cmd[13], cmd[14], cmd[15]);
else if (cmd.length == 17) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9], cmd[10], cmd[11], cmd[12], cmd[13], cmd[14], cmd[15], cmd[16]);
else if (cmd.length == 18) out = exec(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9], cmd[10], cmd[11], cmd[12], cmd[13], cmd[14], cmd[15], cmd[16], cmd[17]);
else exit("Unexpected number of arguments: " + cmd.length);

if (!showWin) print(out);
print("Finished. Details: " + outDir + File.separator + "segmentation_log.csv");

function stripSlash(p) {
    while (endsWith(p, "\\") || endsWith(p, "/"))
        p = substring(p, 0, lengthOf(p) - 1);
    return p;
}
