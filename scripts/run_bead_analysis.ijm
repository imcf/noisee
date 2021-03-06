// example macro demonstrating how to launch the NoiSee bead analysis with
// predefined parameters / inputs:

opts =  "";
opts += "msg_title=[none],";
opts += "msg_note_close=[none],";
opts += "beadsimage=[/data/noisee/beads.ome.tif],";
opts += "beads_diameter=[12],";
opts += "beads_noisetolerance=[50],";
opts += "make_kymographs=[true],";
opts += "save_measurements=[true],";
opts += "save_pdf=[true],";
opts += "keep_roiimages=[true]";

run("NoiSee Bead Analysis", opts);

print("Noisee options: " + opts);
