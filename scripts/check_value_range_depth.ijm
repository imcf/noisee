// macro code to check a 16-bit image for its actual value range bit depth and
// to test for saturation within that range

// define the value range bit depths to test for:
possible_depths = newArray(8, 10, 11, 12, 14, 16);

// code below expects array to be sorted, so make sure this is true:
Array.sort(possible_depths);

getStatistics(_, _, _, max, _, _);
print("maximum value in image: " + max);

saturated = false;
actual_depth = 16;
// traverse the possible depths array backwards:
for (i = lengthOf(possible_depths) - 1; i > 0; i--) {
	sat = pow(2, possible_depths[i]) - 1;
	print("checking for " + possible_depths[i] + " bit value range (0-" + sat + ")");
	
	if (max == sat) {
		saturated = true;
		actual_depth = possible_depths[i];
		print("saturated " + actual_depth + "-bit image detected!");
	} else {
		next_lower = pow(2, possible_depths[i-1]);
		// print("checking against next lower range limit: " + next_lower);
		if (max < sat && max >= next_lower) {
			actual_depth = possible_depths[i];
			print("non-saturated " + actual_depth + "-bit image detected!");
		}
	}	
}

print("\nRESULT");
print(" - value range depth = " + actual_depth);
print(" - saturated = " + saturated);
