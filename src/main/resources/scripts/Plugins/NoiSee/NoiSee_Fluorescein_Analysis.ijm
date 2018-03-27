// @String(label="NoiSee - Fluorescein SNR analysis", choices={"Note: all currently open images will be closed!"}, style="listBox", description="Hit 'Cancel' otherwise!") warn_msg
// @File(label="Dark image",description="dark field image") darkimage
// @File(label="Fluorescein image",description="fluorescein image") fluoimage
// @Boolean(label="Save results as PDF",description="generate a PDF with images and plots",value="true") save_pdf
// @Integer(label="Log level",description="higher number means more messages",min=0,max=2,style="scroll bar") LOGLEVEL
// @Boolean(label="Save log messages",description="save contents of the 'Log' window in a text file",value="false") save_log


//////////// NoiSee Fluorescein Analysis ///////////////////////////////////////////////////////
// SNR evaluation macro, written by Kai Schleicher, Niko Ehrenfeuchter, IMCF Basel
// licence: GPLv3


/// TODOs:

/// Naming conventions
//  - "img_"  - image IDs of 2D images
//  - "rgb_"  - image IDs of 2D RGB images


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

function dressImage(image_id, lut_name, enhance, desc) {
    // applies a given LUT to an image, applies the "Enhance contrast" command to it if the
    // "enhance" parameter is non-negative, adds a calibration bar (non-overlay) and optionally
    // adds a text description below the image
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
    if (desc != "")
        addTextToImage(new_id,  false, "Center", 22, desc);
    closeImage(image_id);
    return new_id;
}

function createTable(title, pairs, fname) {
    // create a new 2-column table with the given title, using the key-value tuples from the array
    // given in "pairs" to fill the cells, saving it as to the text file "fname"
    titleb = "[" + title + "]";
    if (isOpen(title))
        print(titleb, "\\Clear");
    else
        run("Table...", "name=" + titleb + " width=320 height=340");

    print(titleb, "\\Headings:Key\tValue");
    for (i = 0; i < pairs.length; i = i + 2) {
        print(titleb, pairs[i] + "\t" + pairs[i+1]);
    }
    selectWindow(title);
    if (fname != "")
        saveAs("Results", fname);
}

function createTableImage(title, pairs) {
    // create an image with a 2-column table from the given array of pairs
    // returns the ID of the new image
    newImage("tmp_table_col1", "RGB white", 1, 1, 1);
    img_col1 = getImageID();
    newImage("tmp_table_col2", "RGB white", 1, 1, 1);
    img_col2 = getImageID();

    for (i = 0; i < pairs.length; i = i + 2) {
        addTextToImage(img_col1, false, "Left", 28, pairs[i]);
        addTextToImage(img_col2, false, "Left", 28, pairs[i+1]);
    }
    selectImage(img_col2);
    col2h = getHeight();
    col2w = getWidth() + 28;
    run("Canvas Size...", "width=" + col2w + " height=" + col2h + " position=Top-Right");
    run("Combine...", "stack1=tmp_table_col1 stack2=tmp_table_col2");
    img_table = getImageID();
    rename(title);

    addTextToImage(img_table, true, "Center", 18, "");
    addTextToImage(img_table, true, "Center", 36, title);

    return img_table;
}

function addTextToImage(image_id, above, justify, font_size, text) {
    selectImage(image_id);
    logd("addTextToImage(" + getTitle() + ", ''" + text + "'')");
    run("Select None");

    curw = getWidth();
    neww = curw;
    curh = getHeight();
    newh = curh + font_size + 2;
    setFont("SansSerif", font_size);
    textw = getStringWidth(text);
    if (textw > curw)
        neww = textw;

    if (above == true) {
        canvpos = "Bottom-" + justify;
        textpos = font_size + 2;
    } else {
        canvpos = "Top-" + justify;
        textpos = newh;
    }

    setForegroundColor(30, 30, 30);
    setBackgroundColor(255, 255, 255);
    run("Canvas Size...", "width=" + neww + " height=" + newh + " position=" + canvpos);
    drawString(text, 0, textpos);
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
        getLocationAndSize(_, _, window_width, window_height);
        if (window_width != width) {
            delta = (width - window_width) / 2;
            setLocation(x_coord + delta, y_coord, width, height);
        }
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
print("NoiSee is published in Ferrand, Schleicher & Biehlmaier et al. 2018");
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


    ///////////  decorate images, add calibration bars //////////// ////////// ////////// //////////
    rgb_hist = makeHistogram(img_sig, "physics", true);
    addTextToImage(rgb_hist, false, "Center", 12, "Histogram of absolute signal.");
    rgb_sig  = dressImage(img_sig,  "physics", 0.35, "Absolute signal (fluorescein - background).");
    rgb_fluo = dressImage(img_fluo, "Glow",      -1, "Fluorescein image (original data).");
    rgb_dark = dressImage(img_bg,   "Glow",      -1, "Dark image (original data).");
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////


    ///////////  write summary of results and settings into a new table //////////// //////////
    title = "NoiSee Results Summary";

    pairs = newArray();
    pairs = Array.concat(pairs, "Signal mean", mean_sig);
    pairs = Array.concat(pairs, "Signal StdDev (noise)", std_sig);
    pairs = Array.concat(pairs, "SNR", snr);
    pairs = Array.concat(pairs, "Background mean", mean_bg);
    pairs = Array.concat(pairs, "SBR", sbr);
    pairs = Array.concat(pairs, "Background StdDev", std_bg);
    pairs = Array.concat(pairs, "", "");
    pairs = Array.concat(pairs, "-- Input --", "");
    pairs = Array.concat(pairs, "dark image", bg_fname);
    pairs = Array.concat(pairs, "fluorescein image", fluo_fname);

    createTable(title, pairs, respath + "/" + "NoiSee-summary.txt");
    img_summary = createTableImage(title, pairs);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////


    ////////// adjust order of the images and create a PDF ////////// ////////// //////////

    // the PDF exporter of ImageJ simply concatenates all open images in ascending order,
    // starting with the oldest one first, therefore we need to duplicate all images into
    // new ones (closing the old ones) in the order which is desired in the resulting PDF:
    rgb_fluo = duplicateAndClose(rgb_fluo);
    rgb_dark = duplicateAndClose(rgb_dark);
    rgb_sig  = duplicateAndClose(rgb_sig);
    rgb_hist = duplicateAndClose(rgb_hist);

    img_summary = duplicateAndClose(img_summary);

    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////


    ////////// save the log, create PDF and arrange the windows on the screen ////////// //////////
    if (save_log) {
        selectWindow("Log");
        saveAs("Text", respath + "/Log.txt");
    }

    setBatchMode("exit and display");   // exit batch mode and show images
    // wait(100);  // give the OS some time to display all image windows


    if (save_pdf) {
        fname_pdf = respath + "/" + "NoiSee-report.pdf";
        print("Creating PDF from images: " + fname_pdf);
        run("PDF ... ", "show show scale save one save=[" + fname_pdf + "]");
    }
    closeImage(img_summary);

    image_ids = newArray(rgb_sig, rgb_fluo, rgb_dark, rgb_hist);
    arrangeImages(image_ids, screenHeight * 0.2);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////
}
