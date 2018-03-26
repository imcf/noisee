// @Boolean(label="NoiSee - run Fluorescein SNR analysis",value="true") run_macro
// @File(label="Dark image",description="dark field image") darkimage
// @File(label="Fluorescein image",description="fluorescein image") fluoimage
// @Boolean(label="Save results as PDF",description="generate a PDF with images and plots",value="true") save_pdf
// @Integer(label="Log level",description="higher number means more messages",min=0,max=2,style="scroll bar") LOGLEVEL


//////////// NoiSee ///////////////////////////////////////////////////////
// SNR evaluation macro, written by Kai Schleicher, Niko Ehrenfeuchter, IMCF Basel
// licence: GPLv3


/// TODOs:
//  - create a summary image with results to be included in PDF


/// Naming conventions
//  - "img_"  - image IDs of 2D images
//  - "rgb_"  - image IDs of 2D RGB images


if (run_macro == false)
    exit("Please select the 'run analysis' option to execute the macro!");



////////////////// function definitions ///////////////////////////////

function duplicateImage(id_orig, new_name, single){
    // duplicate an image (given by ID), give it a new name and return the new ID
    selectImage(id_orig);
    run("Select None");  // clear selection to avoid messing up the duplication
    if (single == true) {
        run("Duplicate...", "use");  // duplicate single slice only
    } else {
        run("Duplicate...", "duplicate");  // duplicate the entire stack
    }
    rename(new_name);
    return getImageID();
}

function duplicateAndClose(id_orig) {
    // helper function for re-ordering images when creating a PDF
    // the PDF exporter places images one per page in the order when they were created, so the only
    // way to change that order is to duplicate an existing image into a new one, closing the old...
    selectImage(id_orig);
    new_id = duplicateImage(id_orig, getTitle(), false);
    closeImage(id_orig);
    return new_id;
}

function closeImage(image_id) {
    if (isOpen(image_id) == false)
        return;
    selectImage(image_id);
    close();
}

function makeHistogram(image_id, lut_name, logarithmic) {
    // applies a given LUT to the image specified with image_id, and creates a
    // new image containing the histogram of the given one, optionally enabling
    // the "logarithmic" view
    selectImage(image_id);
    orig_title = getTitle();
    logi("makeHistogram(" + orig_title + ", " + lut_name + ")");
    run("Select None");
    logd("applying LUT " + lut_name);
    run(lut_name);  // WARNING: applying a LUT changes the selected image!!
    selectImage(image_id);
    if (logarithmic == true)
        setKeyDown("shift");
    run("Histogram");
    setKeyDown("none");
    // we have to rename the histogram as by default it will discard everything
    // after the first space from the original title, so:
    rename("Histogram of " + orig_title);
    return getImageID();
}

function dressImage(image_id, lut_name, enhance) {
    // applies a given LUT to an image, applies the "Enhance contrast" command to it if the
    // "enhance" parameter is non-negative, adds a calibration bar (non-overlay)
    // returns the ID of the new image, closing the old one
    selectImage(image_id);
    logi("dressImage(" + getTitle() + ", " + lut_name + ", " + enhance + ")");
    run("Select None");
    logd("applying LUT " + lut_name);
    run(lut_name);  // WARNING: applying a LUT changes the selected image!!
    selectImage(image_id);
    if (enhance >= 0) {
        logd("enhancing contrast (saturated=" + enhance + ")");
        run("Enhance Contrast", "saturated=" + enhance);
    }
    // sometimes calibration bar doesn't work depending on when / where the image window appears on
    // the screen, so make sure the right window is selected / active:
    selectImage(image_id);
    logd("adding calibration bar");
    title = getTitle();
    run("Calibration Bar...","location=[Upper Right] fill=None " +
        "label=White number=5 decimal=0 font=12 zoom=3.3 bold");
    new_id = getImageID();
    rename(title);
    closeImage(image_id);
    return new_id;
}

function arrangeImages(ids, y_coord) {
    // try to place the image windows given in the "ids" array horizontally on the screen,
    // arranging them in equal distance and adjusting the zoom level if necessary
    selectImage(ids[0]);
    getLocationAndSize(_, _, window_width, window_height);
    px_width = getWidth();
    px_height = getHeight();
    border_x = window_width - px_width;
    border_y = window_height - px_height;
    // try varius zoom levels until the windows fit on the screen and calculate the spacing:
    for (s=0; s<4; s++) {
        zoom = 1 - 0.25 * s;
        width = px_width * zoom + border_x;
        height = px_height * zoom + border_y;
        total_width = ids.length * width;
        logd("width " + width + " (zoom " + zoom + ", total width " + total_width + ")");
        remaining = screenWidth - total_width;
        if (remaining > 0) {
            spacing = remaining / (ids.length + 1);
            logd("zoom / width / spacing: " + zoom + " / " + width + " / " + spacing);
            break;
        } else {
            continue;
        }
        // if we reach this point we can't seem to calculate a zoom factor, so we give up without
        // placing / relocating the image windows (doesn't make sense):
        return;
    }

    // now place the images:
    for (i=0; i<ids.length; i++) {
        selectImage(ids[i]);
        x_coord = width * i + spacing * (i+1);
        logd("placing image at " + x_coord + " / " + y_coord);
        setLocation(x_coord, y_coord, width, height);
    }
}

function stripOmeSuffix(orig) {
    if (endsWith(orig, ".ome")) {
        index = lastIndexOf(orig, ".ome");
        orig = substring(orig, 0, index);
    }
    return orig;
}

function log_formatter(message) {
    print('image "' + getTitle() + "'' [type=" + bitDepth() + "] [id=" + getImageID() + "]: " +
        message);
}

function logi(message) {
    if (LOGLEVEL < 1)
        return;
    log_formatter(message);
}

function logd(message) {
    if (LOGLEVEL < 2)
        return;
    log_formatter(message);
}


//////////////// set the user environment /////////////////////////////////////////////////////

// results will potentially be screwed up if other images are open, so close all:
if (nImages > 0) {
    run("Close All");
}

print("\\Clear");  // clear the Log window
print("============================================");
print("NoiSee is published in Ferrand, Schleicher & Biehlmaier et al. 2017");
print("============================================");
print("running on ImageJ version " + getVersion);

run("Options...", "pad");  // pad edges when eroding
setOption("black background", true);  // set "Black Background" in "Binary Options"
// roiManager("reset");   // results are only correct if no previous ROI exists
run("Clear Results");  // empty the results table
run("Appearance...", "  menu=0 16-bit=Automatic");  // disable inverting LUT
run("Colors...", "foreground=white background=black selection=red");
run("Input/Output...", "file=.txt");  // set saving format to .txt files


process_fluo();


//////////////// fluorescein method ////////////////////////////////////////////////////////////////
function process_fluo() {
    setBatchMode(true);
    ////////// open the image stack and prepare processing ////////// ////////// //////////
    bfopts  = " color_mode=Default";
    bfopts += " view=Hyperstack";
    bfopts += " stack_order=XYCZT";
    run("Bio-Formats Importer", "open=[" + darkimage + "]" + bfopts);
    img_bg = getImageID();
    bg_fname = File.getName(darkimage);        // filename only
    bg_fname_nosuffix = stripOmeSuffix(File.nameWithoutExtension);  // filename without extension

    run("Bio-Formats Importer", "open=[" + fluoimage + "]" + bfopts);
    img_fluo = getImageID();
    fluo_fname = File.getName(fluoimage);        // filename only
    fluo_fname_nosuffix = stripOmeSuffix(File.nameWithoutExtension);  // filename without extension    

    fpath = File.getParent(fluoimage);           // path only
    respath = fpath + "/" + fluo_fname_nosuffix + "_NoiSee-results";  // path for additional results
    File.makeDirectory(respath);

    print("processing images in location: [" + fpath + "]");
    print("  - dark image:  [" + bg_fname + "]");
    print("  - fluorescein image:  [" + fluo_fname + "]");
    logd("\n\nfull paths of images (dark + fluorescein):\n" +
        darkimage + "\n \n" +
        fluoimage + "\n ");
    print("path for saving results: [" + respath + "]");
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////


    ////////// get stats, calculate normalized image, calculate snr + sbr ////////// //////////
    selectImage(img_bg);
    getStatistics(_, mean_bg, _, _, std_bg);
    print("darkimage stats:   mean=" + mean_bg + "   std=" + std_bg);

    img_sig = duplicateImage(img_fluo, "absolute signal (fluorescein - background)", true);
    run("Subtract...", "value=" + mean_bg);
    getStatistics(_, mean_sig, _, _, std_sig);
    print("absolute signal image stats:   mean=" + mean_sig + "   std=" + std_sig);
    
    snr = mean_sig / std_sig;
    sbr = mean_sig / mean_bg;
    print("snr (signal-to-noise): " + snr);
    print("sbr (signal-to-background): " + sbr);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////


    ///////////  write summary of results and settings into a new table //////////// //////////
    title = "NoiSee Results Summary";
    titleb = "[" + title + "]";
    if (isOpen(title))
        print(titleb, "\\Clear");
    else
        run("Table...", "name=" + titleb + " width=320 height=340");
    print(titleb, "\\Headings:Label\tValue");
    print(titleb, "Signal mean\t" + mean_sig);
    print(titleb, "Signal StdDev (noise)\t" + std_sig);
    print(titleb, "SNR\t" + snr);
    print(titleb, "Background mean\t" + mean_bg);
    print(titleb, "SBR\t" + sbr);
    print(titleb, "Background StdDev\t" + std_bg);
    print(titleb, "\t");
    print(titleb, "dark image\t" + bg_fname);
    print(titleb, "fluorescein image\t" + fluo_fname);
    selectWindow(title);
    saveAs("Results", respath + "/" + "NoiSee-summary.txt");
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////


    ///////////  decorate images, add calibration bars //////////// ////////// ////////// //////////
    rgb_hist = makeHistogram(img_sig, "physics", true);
    rgb_sig  = dressImage(img_sig,  "physics", 0.35);
    rgb_fluo = dressImage(img_fluo, "Glow",      -1);
    rgb_dark = dressImage(img_bg,   "Glow",      -1);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////


    ////////// arrange the windows and create a PDF of images and plots ////////// //////////
    rgb_sig = duplicateAndClose(rgb_sig);
    rgb_hist = duplicateAndClose(rgb_hist);
    setBatchMode("exit and display");   // exit batch mode and show images
    // wait(100);  // give the OS some time to display all image windows


    if (save_pdf) {
        fname_pdf = respath + "/" + "NoiSee-report.pdf";
        print("Creating PDF from images: " + fname_pdf);
        run("PDF ... ", "show show scale save one save=[" + fname_pdf + "]");
    }

    image_ids = newArray(rgb_sig, rgb_fluo);
    arrangeImages(image_ids, screenHeight * 0.1);
    image_ids = newArray(rgb_dark, rgb_hist);
    arrangeImages(image_ids, screenHeight * 0.55);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////
}
