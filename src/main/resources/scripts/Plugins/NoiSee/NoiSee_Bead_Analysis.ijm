//////////// NoiSee Beads Analysis ///////////////////////////////////////////////////////
// Signal-to-Noise-Ratio evaluation suite
// written by Kai Schleicher, Niko Ehrenfeuchter, IMCF Basel
// licence: GPLv3


/// TODOs:
//  - consider using lacan's LibInstaller: https://github.com/lacan/LibInstaller

/// Naming conventions
//  - "imgs_" - image IDs of stacks
//  - "img_"  - image IDs of 2D images
//  - "rgb_"  - image IDs of 2D RGB images
//  - "roi_"  - index number of a ROI manager entry


//////// Script Parameters, see https://imagej.net/Script_Parameters for details
#@ String(visibility=MESSAGE, label="NoiSee  -",value="Beads SNR analysis",persist=false) msg_title
#@ File(label="Beads time-series image",description="2D time-lapse acquisition of fluorescent beads") beadsimage
#@ Integer(label="Beads diameter (in pixels)",description="approximate bead diameter (in pixels)",value=15) beads_diameter
#@ Integer(label="Find Maxima noise tolerance",description="typical values: [PMT=50] [HyD (photon counting)=10] [Camera=500]",value=50) beads_noisetolerance
#@ Boolean(label="Create Kymographs",description="visual indicator for drift and bleaching",value="true") make_kymographs
#@ Boolean(label="Save additional measurements",description="store 'StdDev', 'SNR', 'Mean' and 'bleaching' measurements",value="false") save_measurements
#@ Boolean(label="Save results as PDF",description="generate a PDF with images and plots",value="true") save_pdf
#@ Boolean(label="Keep ROI images open",description="if disabled ROI visualizations will only be added to PDF",value="false") keep_roiimages
#@ String(visibility=MESSAGE,label="Note:",value="all currently open images will be closed",persist=false) msg_note_close


// valid log levels: 0 (quiet), 1 (info messages), 2 (debug messages)
LOGLEVEL=0;

// save contents of the 'Log' window in a text file:
save_log=false;


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

function plotResult(Title, XLabel, YLabel, col) {
    // create a high-res plot of the values in column "col" of the results table
    // using the given title and labels
    // returns the ID of the newly created plot image
    if (nResults == 0) {
        print("Unable to create plot [" + Title + "], results table empty!");
        return;
    }
    print("Creating plot [" + Title + "] for " + nResults + " results.");
    Yvalues=newArray(nResults);
    Ymin = getResult(col, 0);
    Ymax = Ymin;
    
    // store Y-values in an array, get min and max:
    for (i=0; i < nResults; i++) {
        Yvalues[i] = getResult(col, i);
        Ymax = maxOf(Ymax, Yvalues[i]);
        Ymin = minOf(Ymin, Yvalues[i]);
    }
    // make sure not to over-emphasize data that has only little variance by
    // setting the plot limits to min/max +/- 10:
    Ymin = round(Ymin - 10.5);
    Ymax = round(Ymax + 10.5);
    print("Plot Y-axis range: " + Ymin + " - " + Ymax);


    temp_plot_name = "NoiSee temporary plot window";
    Plot.create(temp_plot_name, XLabel, YLabel);
    Plot.setLimits(0, nResults, Ymin, Ymax);
    Plot.setLineWidth(2);
    Plot.setColor("#6688dd");
    Plot.add("line",Yvalues);
    Plot.setColor("red");
    Plot.add("circles", Yvalues);
    Plot.show();
    Plot.makeHighResolution("plot of " + col, 2);
    closeImage(temp_plot_name);
    selectWindow("plot of " + col);
    plot_id = getImageID();
    addTextToImage(plot_id, true, "Center", 48, Title);
    addTextToImage(plot_id, true, "Center", 24, "");
    return plot_id;
}

function erode(image_id, num_iterations) {
    // run the "erode" operation multiple times on an image / stack
    selectImage(image_id);
    logd("Eroding current image by " + num_iterations + " iterations...");
    for (i=0; i < num_iterations; i++) {
        run("Erode", "stack");
    }
}

function binaryToSelection(image_id, roi_name, savepath) {
    // create a selection from a binary image, add it to the ROI Manager with the given name and
    // return the ID of the newly created ROI
    selectImage(image_id);
    if (is("binary") == false)
        exit("Image " + getTitle() + " is not binary, not creating a selection!");
    // "Create Selection" requires a threshold to be set, see the source code in
    // https://imagej.nih.gov/ij/developer/source/ij/plugin/filter/ThresholdToSelection.java.html
    // particularly for method selected(x, y) as the documentation is not very clear about this!
    setThreshold(255, 255);
    run("Create Selection");
    return selectionToROI(roi_name, savepath);
}

function selectionToROI(roi_name, savepath) {
    // add an existing selection as a new ROI with the given name and return the ID
    roiManager("Add");
    roi_id = roiManager("count") - 1;  // ROIs are appended, hence "count" == newest ID + 1
    roiManager("Select", roi_id);
    roiManager("Rename", roi_name);
    roiManager("Show None");  // clean up display behavior of the ROI manager
    if (savepath != "")
        roiManager("save selected", savepath + "/roi-" + roi_name + ".zip");
    return roi_id;
}

function pickResults(count) {
    // generate a list of index numbers creating a (more or less) equally spaced subset of the
    // current results
    if (nResults < count) {
        setBatchMode("exit and display");   // exit batch mode and show images
        exit("less than " + count + " results found, check your image!");
    }
    indexes = newArray(count);
    halfstep = nResults / (count * 2);
    for (i=0; i<count; i++) {
        row = round((i*2+1) * halfstep);
        indexes[i] = row;
    }
    return indexes;
}

function createCenterLines(image_id, res, len, namepfx) {
    // create line selections of length "2*len" for the center of mass of a given subset of the
    // current results ("res" is an array with the index numbers of results to be used)
    roiManager("Set Color", "magenta");
    run("Select None");
    roiManager("reset");  // make sure the ROI Manager only contains our newly created line ROIs
    selectImage(image_id);
    for (i=0; i<res.length; i++) {
        index = res[i];
        cx = getResult("XM", index - 1);
        cy = getResult("YM", index - 1);
        logd("draw line for result " + index + " (c-o-m: " + cx + " / " + cy + ")");
        makeLine(cx - len, cy, cx + len, cy);
        roiManager("add");
        roiManager("select", roiManager("count") - 1);
        roiManager("rename", namepfx + index);
    }
    roiManager("Show all without labels");
    roiManager("Set Line Width", 3);
}

function lineKymograph(image_id) {
    // expects a number of "line" ROIs in the ROI Manager, creates a Kymograph (stack or orthogonal
    // profile) for each of them, returning the newly created image IDs as an array
    num_rois = roiManager("count");
    ortho_imgs = newArray(num_rois);
    for (i=0; i<num_rois; i++) {
        selectImage(image_id);
        roiManager("select", i);
        roi_name = call("ij.plugin.frame.RoiManager.getName", i);
        run("Reslice [/]...", "output=1.000 slice_count=1");
        ortho_imgs[i] = getImageID();
        rename("kymograph-" + roi_name);
    }
    return ortho_imgs;
}

function makeKymographMontage(imgs_beadmask, imgs_beads, diameter, basepath) {
    // calculate the expected bead area to set the size parameter for "Analyze Particles" below:
    beads_area = pow(diameter / 2, 2) * 3.14;
    lo = beads_area * 0.6;  // lower limit
    hi = beads_area * 1.4;  // upper limit
    logi("range of expected beads areas: " + lo + " - " + hi);

    img_tmp = duplicateImage(imgs_beadmask, "beadmask-T0", true);
    run("Set Measurements...", "area center");  // center-of-mass gives us the bead location
    run("Analyze Particles...", "size=" + lo + "-" + hi+ " display clear add");
    resetThreshold();
    closeImage(img_tmp);
    saveAs("Results", basepath + "/individual-beads.txt");
    logi("found " + nResults + " individual beads (excluding clustered / clumped ones)");

    indexes = pickResults(4);  // select a subset of four beads from the results
    imgs_tmp = duplicateImage(imgs_beads, "tmp-stack", false);
    createCenterLines(imgs_tmp, indexes, diameter, "bead-");
    lineKymograph(imgs_tmp);
    closeImage(imgs_tmp);
    run("Images to Stack", "name=[kymograph-stack] title=[kymograph-] use");
    imgs_tmp = getImageID();
    run("Scale...", "x=16 y=16 z=1.0 depth=4 interpolation=None process create");
    imgs_tmp2 = getImageID();
    closeImage(imgs_tmp);
    run("Make Montage...", "columns=2 rows=2 scale=1 border=40 font=16 label use");
    closeImage(imgs_tmp2);
    rename("Kymographs Montage");
    run("cool");
    return getImageID();
}

function findROI(roi_name) {
    // scan for an ROI with the given name and return its ID
    // WARNING: will terminate the macro if no ROI with the name exists!
    for (roi_id=0; roi_id<roiManager("count"); roi_id++) {
        cur_name = call("ij.plugin.frame.RoiManager.getName", roi_id);
        if (cur_name == roi_name)
            return roi_id;
    }
    exit("ERROR: ROI with name '" + roi_name + "' doesn't exist!");
}

function makeFilledROIImage(image_id, roi_name, inverse) {
    roi_id = findROI(roi_name);
    new_id = duplicateImage(image_id, "ROI - " + roi_name, true);
    logd("creating filled ROI image for [" + getTitle() + "] and ROI [" + roi_name + "]");
    run("RGB Color");
    setForegroundColor(255, 57, 0);
    roiManager("Select", roi_id);
    if (inverse == true) {
        run("Make Inverse");
    }
    // roiManager("Fill");  // WARNING: this command doesn't respect the "make inverse" from above!
    run("Fill", "slice");
    return new_id;
}

function drawROIsOnImage(image_id, namepfx, color) {
    // use a given image (or stack) to create an RGB image where all ROIs starting with the given
    // prefix are rendered in the specified color
    // returns the ID of the new RGB image
    tmp_id = duplicateImage(image_id, "tmp_image", true);
    run("RGB Color");
    // scan the ROI manager for the given prefix and assemble an array with corresponding IDs:
    num_rois = roiManager("count");
    roi_ids = newArray();
    for (i=0; i<num_rois; i++) {
        roiManager("select", i);
        roi_name = call("ij.plugin.frame.RoiManager.getName", i);
        if (startsWith(roi_name, namepfx)) {
            roi_ids = Array.concat(roi_ids, i);
        }
    }
    // Array.print(roi_ids);

    // now select the IDs, combine them and flatten them into the new image:
    roiManager("Select", roi_ids);
    roiManager("Combine");
    roiManager("Add", "00ff00", 0);
    // the new ROI-ID equals "num_rois":
    roiManager("Select", num_rois);
    roiManager("Set Fill Color", color);
    run("Flatten");
    new_id = getImageID();
    rename("Kymographs Selections");
    roiManager("Delete");
    closeImage(tmp_id);
    return new_id;
}

function measureSelection(image_id, title, basepath, multi, savetxt) {
    // measure (using the existing ROIs) on a given image and save the results
    // in a text file at the given path if requested

    selectImage(image_id);
    run("Restore Selection");
    run("Clear Results");
    if (multi) {
        roiManager("Multi Measure");  // measure on all slices of a stack
    } else {
        // run("Measure");  // is there any difference to roiManager("Measure") ??
        roiManager("Measure");
    }

    if (savetxt == false)
        return;

    File.makeDirectory(basepath);
    if (File.isDirectory(basepath) == false)
        exit("ERROR creating directory [" + basepath + "], stopping.");

    saveAs("Results", basepath + "/" + title + ".txt");
}

function flattenOverlay(image_id) {
    selectImage(image_id);
    title = getTitle();
    run("Flatten");
    new_id = getImageID();
    closeImage(image_id);
    selectImage(new_id);
    rename(title);
    return new_id;
}

function closeImage(image_id) {
    if (isOpen(image_id) == false)
        return;
    selectImage(image_id);
    close();
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

function detectValueRange() {
    // detect the *actual* value range bit depth of a 16-bit image, i.e. if the
    // image contains pixels in a range from 5 to 3978 the value range depth is
    // 12 bits (possible values from 0 to 4095)

    // define the value range bit depths to test for (8 to 16):
    possible_depths = Array.getSequence(17);
    possible_depths = Array.slice(possible_depths, 8, 17);

    Stack.getStatistics(_, _, _, max, _, _);
    logi("maximum pixel value in stack: " + max);

    saturated = false;
    actual_depth = 16;
    // traverse the possible depths array backwards:
    for (i = lengthOf(possible_depths) - 1; i > 0; i--) {
        sat = pow(2, possible_depths[i]) - 1;
        logd("checking " + possible_depths[i] + " bit range (0-" + sat + ")");

        if (max == sat) {
            saturated = true;
            actual_depth = possible_depths[i];
            logd("saturated " + actual_depth + "-bit image detected!");
        } else {
            next_lower = pow(2, possible_depths[i-1]);
            if (max < sat && max >= next_lower) {
                actual_depth = possible_depths[i];
                logd("non-saturated " + actual_depth + "-bit image detected!");
            }
        }
    }

    msg_sat = "(not saturated)";
    if (saturated)
        msg_sat = "(SATURATED!)";
    logd("\ndetected value range: " + actual_depth + " bit " + msg_sat);

    res = newArray(actual_depth, saturated);
    return res;
}

function mapTo8bitPreservingSaturation(effectiveBits) {
    // convert an image with 12 or 16 bit effective value range depth to 8 bit
    // preserving saturation in the sense that only saturated pixels (65535 for
    // 16 bits and 4095 for 12 bits) are mapped to the 8 bit saturation value
    // (255), avoiding the usual binning that would happen if simply the display
    // range was adjusted to the min/max values of the image (resulting in
    // over-saturation of wrongly mapped pixels)
    if (effectiveBits == 16) {
        run("Divide...", "value=257.50 stack");
    } else if (effectiveBits == 12) {
        run("Divide...", "value=16.09 stack");
    } else {
        print("Unsupported VALUE range detected: " + effectiveBits + " bits");
        print("Input image needs to have a value range of 8, 12 or 16 bits!");
        exit_show();
    }
    run("8-bit");
}

function clear_workspace() {
    /*
     * Ensure a clean workspace, i.e.
     *   - no open image windows
     *   - an empty Log window
     *   - no ROIs
     *   - no results
     */

    // clear the Log window
    print("\\Clear");

    // close all open images
    if (nImages > 0) {
        run("Close All");
    }

    // make sure the ROI manager is empty
    roiManager("reset");

    // empty the results table
    run("Clear Results");
}

function reset_ij_options() {
    /*
     * Make sure to set all relevant ImageJ options to a useful state for being
     * able to provide consistent results independent of what has been
     * configured or done by the user before.
     *
     * IMPORTANT: the order of the commands is highly relevant, on changes
     *            careful tests need to be done to ensure correct behavior.
     */

    // disable inverting LUT
    run("Appearance...", "  menu=0 16-bit=Automatic");

    // set foreground color to be white, background black
    run("Colors...", "foreground=white background=black selection=red");

    // pad edges when eroding a binary image
    run("Options...", "pad");

    // set saving format to .txt files
    run("Input/Output...", "file=.txt");


    // ============= WARNING WARNING WARNING =============//
    // the commands below this marker *MUST NOT* be moved
    // upwards as they seem to be overridden by some of the
    // "run(...)" calls otherwise, turning them useless!

    // set "Black Background" in "Binary Options"
    setOption("black background", true);
}

function exit_show() {
    setBatchMode("exit and display");
    exit();
}

function log_formatter(message) {
    print('image "' + getTitle() + "'' [type=" + bitDepth() + "] [id=" +
        getImageID() + "]: " + message);
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

clear_workspace();
reset_ij_options();

print("============================================");
print("NoiSee is published in Ferrand, Schleicher & Biehlmaier et al. 2018");
print("============================================");
print("running on ImageJ version " + getVersion);


process_beads();






//////////////// bead method //////////////////////////////////////////////////////////////////
function process_beads() {
    setBatchMode(true);
    ////////// open the image stack and prepare processing ////////// ////////// //////////
    bfopts  = " color_mode=Default";
    bfopts += " view=Hyperstack";
    bfopts += " stack_order=XYCZT";
    run("Bio-Formats Importer", "open=[" + beadsimage + "]" + bfopts);
    imgs_orig = getImageID();
    fpath = File.getParent(beadsimage);      // path only
    fname = File.getName(beadsimage);        // filename only
    fname_nosuffix = stripOmeSuffix(File.nameWithoutExtension);  // filename without extension
    respath = fpath + "/" + fname_nosuffix + "_NoiSee-Bead-Analysis";  // path for additional results
    File.makeDirectory(respath);
    print("processing image: " + fname + "  (location: [" + fpath + "])");

    // check if image dimensions meet our expectations (z=1, t>1)
    getDimensions(_, _, _, slices, frames);
    if (slices > 1 || frames == 1) {
        print("Input data needs to be a time-lapse with a single slice only!");
        print("Found " + slices + " slices, expected 1!");
        print("Found " + frames + " frames, expected > 1!");
        exit_show();
    }

    // neither floating point nor RGB images make sense for this, so check:
    if (bitDepth() != 8 && bitDepth() != 16) {
        print("Only images with a bit depth of 8 or 16 are supported!");
        exit_show();
    }

    if (bitDepth() == 16) {
        print("16 bit image type detected, converting to 8 bit...");
        valueRange = detectValueRange();
        mapTo8bitPreservingSaturation(valueRange[0]);
    }

    // remove the scaling so all units (measurements, coordinates, ...) are pixel-based:
    run("Set Scale...", "pixel=1 unit=pixel");
    // make sure to reset any color LUT:
    run("Grays");

    getDimensions(width, height, channels, slices, frames);
    area_full = width * height;
    logi("dimensions: " + width + " x " + height + " (" + area_full + ")");
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// find beads and create a mask (binary image) ////////// ////////// //////////
    imgs_beadmask = duplicateImage(imgs_orig, "beadmask", false);
    run("Convert to Mask", "method=IsoData background=Dark calculate black");
    roi_beads = binaryToSelection(imgs_beadmask, "beads", respath);
    // now the background is 0 and beads are 255
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// create kymographs for a number of beads ////////// ////////// //////////
    if (make_kymographs) {
        rgb_kymo = makeKymographMontage(imgs_beadmask, imgs_orig, beads_diameter, respath);
        addTextToImage(rgb_kymo, false, "Center", 22,
            "Kymographs of selected beads. Each of them should be well-aligned from top to bottom.");
        addTextToImage(rgb_kymo, false, "Center", 14, "Bleaching or variations in excitation " +
            "power can be identified from changes in the intensities,");
        addTextToImage(rgb_kymo, false, "Center", 14, "drifts in X result in a // or \\\\ shape " +
            "of the Kymograph, drifts in Y will show as /\\ or \\/ shape.");
    }
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// identify background and create a background-subtracted image  ////////// //////////
    imgs_bg = duplicateImage(imgs_beadmask, "background", false);
    run("Invert", "stack");  // we want the background, not the beads...
    erode(imgs_bg, 3);  // erode the bead mask by 3 pixels to segment only real background
    
    /// transfer selection to original image, measure mean and standard-deviation:
    roi_bg = binaryToSelection(imgs_bg, "background", respath);
    selectImage(imgs_orig);
    run("Restore Selection");
    getStatistics(area_bg, mean_bg, _, _, std_bg);
    areapct_full_bg = area_bg / area_full * 100;
    print("background stats:   mean=" + mean_bg + "   std=" + std_bg + "   (" +
        areapct_full_bg + "% of full area)");
    
    /// create the background-subtracted image
    imgs_bgsub = duplicateImage(imgs_orig, "background-subtracted", false);
    run("Subtract...", "value=" + mean_bg);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// calculate StdDev, Mean and SNR images ////////// ////////// ////////// //////////
    selectImage(imgs_bgsub);
    run("Z Project...", "projection=[Standard Deviation]");
    img_std = getImageID();
    rename("Standard Deviation (StdDev)");
    
    selectImage(imgs_bgsub);
    run("Z Project...", "projection=[Average Intensity]");
    img_avg = getImageID();
    rename("Average Intensity (Mean)");
    
    // calculate the SNR as an image:
    imageCalculator("Divide create 32-bit", img_avg, img_std);
    img_snr = getImageID();
    rename("Mean divided by StdDev (SNR)");
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// find saturated beads and exclude them ////////// ////////// ////////// //////////
    /// TODO: discuss whether looking for saturation at this point makes sense,
    ///       or if this should be done on the original image (before the
    ///       background is subtracted and the time-series is averaged)
    img_satmask = duplicateImage(img_avg, "saturation-mask", false);
    
    run("8-bit");  // make sure the approach also works if input is not 8-bit
    setThreshold(0, 253);
    run("Convert to Mask", "method=Default background=Default");
    // check if any close-to-saturation pixels exist at all:
    getStatistics(_, _, min_satmask);
    avg_has_saturated_pixels = true;
    if (min_satmask == 255) {
        print("No saturated pixels found in Average Intensity image, no need to exclude beads.");
        avg_has_saturated_pixels = false;
    } else {
        print("Average Intensity image has saturated pixels, using a mask to exclude those beads!");
        // erode by half of the given bead diameter, adding 30% safety margin:
        erode(img_satmask, round((beads_diameter/2)*1.3));

        roi_satmask = binaryToSelection(img_satmask, "saturation_mask", respath);
        run("Divide...", "value=255 stack");   // create a binary mask with 1 and 0
        setMinAndMax(0, 1);
        // now apply the mask to the mean/average image:
        imageCalculator("Multiply", img_avg, img_satmask);
    }
    closeImage(img_satmask);   // the saturation mask is not required any more
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// find local maxima to determine locations for SNR evaluation ////////// //////////
    // prepare measurements:
    run("Set Measurements...", "min redirect=None decimal=2");

    /// Find Maxima - noise parameter: Maxima are ignored if they do not stand out from the
    ///   surroundings by more than this value (calibrated units for calibrated images). In other
    ///   words, a threshold is set at the maximum value minus noise tolerance and the contiguous
    ///   area around the maximum above the threshold is analyzed. For accepting a maximum, this
    ///   area must not contain any point with a value higher at than the maximum. Only one maximum
    ///   within this area is accepted.
    selectImage(img_avg);
    run("Find Maxima...", "noise=" + beads_noisetolerance + " output=[Point Selection]");
    roi_peaks = selectionToROI("peaks_from_mean", respath);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// measure (evaulate) using the above determined points ////////// ////////// //////////
    // DISCUSS: should this be normalized (bit depth) to allow comparing different sensors?
    measureSelection(img_std, "StdDev", respath, false, save_measurements);
    measureSelection(img_snr, "SNR", respath, false, save_measurements);
    getStatistics(_, mean_snr, _, _, std_snr);  // mean and std from the SNR
    print("SNR stats:   mean=" + mean_snr + "   std=" + std_snr);

    measureSelection(img_avg, "mean", respath, false, save_measurements);
    getStatistics(_, mean_sig, _, _, std_sig);  // mean and std from the signal
    print("signal stats:   mean=" + mean_sig + "   std=" + std_sig);

    mean_sbr = mean_sig / mean_bg;  // calculate signal-to-background (SBR)
    print("SBR (signal-to-background): " + mean_sbr);

    // NOTE about error-propagation: all components contributing to the SBR contain an error and
    // thus the SBR standard-deviation should be taken into consideration when further analyzing /
    // using the mean SBR value!

    nBeads = nResults;
    print("number of beads detected / measured: " + nBeads);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// measure bleaching ////////// ////////// ////////// ////////// ////////// //////////
    // prepare measurements: area/mean/stddev to allow calculating the SEM = StdDev / sqrt(npixels)
    run("Set Measurements...", "area mean standard redirect=None decimal=2");

    imgs_bleach = duplicateImage(imgs_beadmask, "bleaching", false);

    // erode the mask a bit to compensate for a possible xy-drift:
    erode(imgs_bleach, 3);

    // NOTE: if a scatter plot of stddev vs. time reveals an increasing trend this might indicate
    // an xy-drift. try dilating the bead mask more in that case, if that does not help the
    // time-series should be stabilized (e.g. using stackreg) before analyzing (make sure NOT to
    // have sub-pixel correction as this will change the SNR!!)
    
    roi_bleach = binaryToSelection(imgs_bleach, "bead_intensity_vs_time", respath);
    closeImage(imgs_bleach);  // we have the regions in the ROI manager, no need to keep the image

    measureSelection(imgs_orig, "bead_intensity_vs_time", respath, true, save_measurements);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    /////////// create images showing detected ROIs //////////// ////////// ////////// //////////
    rgb_roi_bg = makeFilledROIImage(imgs_orig, "background", false);
    addTextToImage(rgb_roi_bg, false, "Center", 22,
        "Red is representing the area detected as background.");
    if (avg_has_saturated_pixels) {
            rgb_roi_satmask = makeFilledROIImage(imgs_orig, "saturation_mask", true);
            addTextToImage(rgb_roi_satmask, false, "Center", 22,
                "Red areas contain saturation and are being ignored.");
    } else {
        rgb_roi_satmask = duplicateImage(imgs_orig, "ROI - saturation_mask", true);
        addTextToImage(rgb_roi_satmask, false, "Center", 22,
            "No saturated pixels found, no need to exclude any beads from analysis.");
        run("RGB Color");
    }
    rgb_roi_intensity = makeFilledROIImage(imgs_orig, "bead_intensity_vs_time", false);
    addTextToImage(rgb_roi_intensity, false, "Center", 22,
        "Red pixels used for Mean / StdDev plots over time.");

    if (make_kymographs) {
        rgb_kymo_lines = drawROIsOnImage(imgs_orig, "bead-", "green");
        addTextToImage(rgb_kymo_lines, false, "Center", 22,
            "Green lines showing selections used to create Kymographs.");
    }
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ///////////  decorate images, add calibration bars //////////// ////////// ////////// //////////
    rgb_t0  = dressImage(imgs_orig, "Glow",      -1, "First timepoint (T0) of the original data.");
    rgb_avg = dressImage(img_avg,   "Fire",      -1, "Average projection of the background-subtracted data.");
    rgb_std = dressImage(img_std,   "Fire",      -1, "StdDev projection of the background-subtracted data.");
    rgb_snr = dressImage(img_snr,   "physics", 0.35, "Signal-To-Noise ratio for all pixels.");

    // adjust name for original image (now showing the first time point):
    addTextToImage(rgb_t0,  false, "Center", 12, "Original file name:");
    addTextToImage(rgb_t0,  false, "Center", 12, fname);
    rename("Original Data");

    // clean up image windows:
    closeImage(imgs_bgsub);
    closeImage(imgs_bg);
    closeImage(imgs_beadmask);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// create plots from bleaching measurements ////////// ////////// ////////// //////////
    // linear decay = z-drift, exponential decay = bleaching
    col_mean = "Mean(bead_intensity_vs_time)";
    plot_mean = plotResult("Mean bead intensity over time", "Frame", "bead intensity mean", col_mean);
    addTextToImage(plot_mean, false, "Center", 22,
        "A linear decay is an indicator for a z-drift, an exponential decay for bleaching.");
    addTextToImage(plot_mean, false, "Center", 96, "");

    // linear increase = xy-drift
    // this reveals only drift that is relvant for the regions that measure bleaching or z-drift.
    // could in general be used to reveal xy-drift as it also interferes with SNR
    col_std = "StdDev(bead_intensity_vs_time)";
    plot_std = plotResult("Standard deviation of bead intensity over time", "Frame",
        "bead intensity StdDev", col_std);
    addTextToImage(plot_std, false, "Center", 22,
        "Evolution of noise over time.");

    run("Combine...", "stack1=[plot of " + col_mean + "] stack2=[plot of " + col_std + "] combine");
    rename("Plots of intensity vs. time");
    rgb_plots = getImageID();
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ///////////  write summary of results and settings into a new table //////////// //////////
    title = "NoiSee Results Summary";

    pairs = newArray();
    pairs = Array.concat(pairs, "SNR mean", mean_snr);
    pairs = Array.concat(pairs, "SNR StdDev", std_snr);
    pairs = Array.concat(pairs, "SBR mean", mean_sbr);
    pairs = Array.concat(pairs, "Signal mean", mean_sig);
    pairs = Array.concat(pairs, "Signal StdDev (noise)", std_sig);
    pairs = Array.concat(pairs, "Background mean", mean_bg);
    pairs = Array.concat(pairs, "Background StdDev", std_bg);
    pairs = Array.concat(pairs, "Background area", area_bg);
    pairs = Array.concat(pairs, "Background area %", areapct_full_bg);
    pairs = Array.concat(pairs, "Number of beads", nBeads);
    pairs = Array.concat(pairs, "", "");
    pairs = Array.concat(pairs, "-- Settings --", "");
    pairs = Array.concat(pairs, "Beads diameter", beads_diameter);
    pairs = Array.concat(pairs, "Noise tolerance", beads_noisetolerance);
    pairs = Array.concat(pairs, "", "");
    pairs = Array.concat(pairs, "-- Input --", "");
    pairs = Array.concat(pairs, "Filename", fname);

    createTable(title, pairs, respath + "/" + "NoiSee-summary.txt");
    img_summary = createTableImage(title, pairs);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////



    ////////// adjust order of the images and create a PDF ////////// ////////// //////////

    // the PDF exporter of ImageJ simply concatenates all open images in ascending order,
    // starting with the oldest one first, therefore we need to duplicate all images into
    // new ones (closing the old ones) in the order which is desired in the resulting PDF:
    rgb_t0  = duplicateAndClose(rgb_t0);
    rgb_avg = duplicateAndClose(rgb_avg);
    rgb_std = duplicateAndClose(rgb_std);
    rgb_snr = duplicateAndClose(rgb_snr);
    if (make_kymographs){
        rgb_kymo = duplicateAndClose(rgb_kymo);
        rgb_kymo_lines = duplicateAndClose(rgb_kymo_lines);
    }
    rgb_roi_bg = duplicateAndClose(rgb_roi_bg);
    rgb_roi_satmask = duplicateAndClose(rgb_roi_satmask);
    rgb_roi_intensity = duplicateAndClose(rgb_roi_intensity);

    rgb_plots = duplicateAndClose(rgb_plots);
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

    row_upper = newArray(rgb_t0, rgb_avg, rgb_plots);
    row_lower = newArray(rgb_std, rgb_snr);

    if (make_kymographs) {
         row_lower = Array.concat(row_lower, rgb_kymo);
    }

    if (keep_roiimages) {
        row_upper = Array.concat(row_upper, rgb_roi_intensity, rgb_roi_bg);
        if (make_kymographs) {
            row_lower = Array.concat(row_lower, rgb_kymo_lines);
        }
        row_lower = Array.concat(row_lower, rgb_roi_satmask);
    } else {
        closeImage(rgb_kymo_lines);
        closeImage(rgb_roi_bg);
        closeImage(rgb_roi_satmask);
        closeImage(rgb_roi_intensity);
    }

    arrangeImages(row_upper, screenHeight * 0.1);
    arrangeImages(row_lower, screenHeight * 0.5);
    ////////// ////////// ////////// ////////// ////////// ////////// ////////// //////////
}
