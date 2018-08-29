// macro to generate 2D images containing pixels with the four highest 
// values of the given bit depth (defined in the bit_depth array),
// followed by a zero value pixel (eventually rescaled to 160x32)

#@ File(label="Output directory",style="directory") gen_images_output_dir

bit_depths = newArray(8, 9, 10, 11, 12, 13, 14, 15, 16);

for (i = 0; i < lengthOf(bit_depths); i++) {
    title = "" + bit_depths[i] + " bit 5px test image";
    // print(title);
    newImage(title, "16 bit", 5, 1, 1);
    for (v = 0; v < 4; v++) {
        val = pow(2, bit_depths[i]) - (1 + v);
        setPixel(v, 0, val);
        // print("pos / value: " + v + " / " + val);
    }
    setPixel(4, 0, 0);
    run("Scale...", "x=32 y=32 width=160 height=32 interpolation=None create");
    selectWindow(title);
    close();
    rename(title);
    saveAs("Tiff", gen_images_output_dir + "/" + title + ".tif");
    close();
}
