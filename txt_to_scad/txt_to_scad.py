#!/usr/bin/env python3
import sys

def txt_to_scad(infile, varname, outfile):
    pts = []
    with open(infile) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '...' in line:
                # skip blanks, comments, and the "..." line
                continue
            parts = line.replace(',', ' ').split()
            if len(parts) < 2:
                continue
            x, y = map(float, parts[:2])
            pts.append(f"    [{x:.6f}, {y:.6f}]")

    with open(outfile, 'w') as f:
        f.write(f"// Auto-generated from {infile}\n")
        f.write(f"{varname} = [\n")
        f.write(",\n".join(pts))
        f.write("\n];\n")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: txt_to_scad.py input.txt varname output.scad")
        sys.exit(1)
    txt_to_scad(sys.argv[1], sys.argv[2], sys.argv[3])

