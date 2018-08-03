// macro to generate a 1D image containing pixel values ranging
// from zero to the maximum possible value of the numbers given
// in the bit_depth array - for every bit depth specified there
// two pixels are added, one being (max - 1) and the second
// being the max value itself

bit_depths = newArray(0, 8, 9, 10, 11, 12, 14, 16);


range = newArray(lengthOf(bit_depths) * 2);
for (i = 0; i < lengthOf(bit_depths); i++) {
	range[i*2] = pow(2, bit_depths[i]) - 2;
	range[i*2+1] = pow(2, bit_depths[i]) - 1;
}
range[0] = 0;

Array.print(range);

title = "" + bit_depths[lengthOf(bit_depths)-1] + " bit test image";

newImage(title, "16 bit", lengthOf(range) - 1, 1, 1);
for (i = 1; i < lengthOf(range); i++) {
	setPixel(i-1, 0, range[i]);	
}
run("Set... ", "zoom=3200");
run("glasbey_on_dark");
