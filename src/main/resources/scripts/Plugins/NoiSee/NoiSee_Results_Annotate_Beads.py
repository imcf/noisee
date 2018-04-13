############ NoiSee Results - Annotate Bead Measurements
## Signal-to-Noise-Ratio evaluation suite
## written by Kai Schleicher, Niko Ehrenfeuchter, IMCF Basel
## licence: GPLv3


#@ String(visibility=MESSAGE, label="NoiSee Results  -", value="Annotate Bead Measurements", persist=false) msg_title
#@ File(label="NoiSee Beads Results Directory",style="directory") noisee_beads_resdir
#@ String(label="Microscope Name", description="e.g. 'LSM700'") noisee_beads_mic_name
#@ Date(label="Acquisition Date",required=false) noisee_beads_date
#@ String(label="Objective", description="e.g. 63x, 40x-Water") noisee_beads_objective 
#@ String(label="Detector", description="e.g. PMT2, HyD3, GaAsP1") noisee_beads_detector
#@ Float(label="Laser Power (in percent)") noisee_beads_lpp
#@ Float(label="Laser Power (in µW)", description="e.g. '0,92'") noisee_beads_lpuw
#@ Integer(label="Gain") noisee_beads_gain
#@ Integer(label="Pixel Dwell") noisee_beads_dwell

#@ LogService log


import sys
import datetime
import os
import os.path

# we usually need the string, not the java File object:
resdir = noisee_beads_resdir.getPath()

if not os.path.isdir(resdir):
    sys.exit("Results directory not existing: " + resdir)

outfname = resdir + "/metadata.txt"
if os.path.exists(outfname):
    tstamp = datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S")
    try:
        preserve = resdir + "/metadata_pre-" + tstamp + ".txt"
        log.info("Preserving existing metadata as: %s" % preserve)
        os.rename(outfname, preserve)
    except Exception as err:
        sys.exit("Unable to preserve existing metadata file: %s" % err)


meta = {
    'microscope': noisee_beads_mic_name,
    'objective': noisee_beads_objective,
    'detector': noisee_beads_detector,
    'laserpower_pct': noisee_beads_lpp,
    'laserpower_uW': noisee_beads_lpuw,
    'gain': noisee_beads_gain,
    'dwell': noisee_beads_dwell
}


if noisee_beads_date is None:
    meta['date'] = datetime.datetime.now().strftime("%Y-%m-%d")
    log.info("No date given, using today: %s" % meta['date'])
else:
    meta['date'] = "%s-%02d-%02d" % (noisee_beads_date.year + 1900,
                                     noisee_beads_date.month + 1,
                                     noisee_beads_date.date)

try:
    log.info("Saving metadata file: %s" %outfname)
    with open(outfname, "w") as outfile:
        for key, val in meta.items():
            formatted = "%s:%s" % (key, val)
            log.info("    %s" % formatted)
            outfile.write("%s\n" % formatted)
    log.info("Done.")
except Exception as err:
    sys.exit("Error saving metadata: %s" % err)
