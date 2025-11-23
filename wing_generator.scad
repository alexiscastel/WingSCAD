// Wing generator from planform with twist, dihedral, and chordwise offset
// Thickness comes from airfoil profile; x_offset_mm lets you shift each
// section forward/backward (control sweep, LE/TE alignment).

$fn = 64;

function deg2rad(a) = a * PI / 180;

// --- Airfoils: include your generated SCAD data files ---
include <ag04.scad>;  // defines ag04_coords
include <ag08.scad>;  // defines ag08_coords

FOIL_AG04 = 0;
FOIL_AG08 = 1;

function get_foil(id) =
    id == FOIL_AG04 ? ag04_coords :
    id == FOIL_AG08 ? ag08_coords :
    ag04_coords; // default

// Scale normalized airfoil coordinates (chord = 1) to chord_mm
function scale_airfoil(foil, chord_mm) =
    [ for (p = foil) [ p[0] * chord_mm, p[1] * chord_mm ] ];

// 2D airfoil polygon (temporary in XY: X=chord, Y=thickness)
module airfoil2d(foil, chord_mm=100) {
    polygon(points = scale_airfoil(foil, chord_mm));
}

// --------------------------------------------------------------------
// Thin 3D slice of an airfoil at a given spanwise station.
//
// y_mm        : spanwise location
// twist_deg   : twist about spanwise (Y) axis
// x_offset_mm : chordwise offset of the whole profile (controls sweep)
// slice_thickness : skin thickness along span (mm)
// --------------------------------------------------------------------
module airfoil_section(foil, chord_mm=100,
                       y_mm=0, twist_deg=0, x_offset_mm=0,
                       slice_thickness=0.6) {
    // Place the section at its spanwise and chordwise offsets
    translate([x_offset_mm, y_mm, 0]) {
        // Twist around Y axis through x=0 (then shifted by x_offset_mm)
        rotate([0, twist_deg, 0]) {
            // Orient the 2D airfoil so that:
            //   X = chord, Y = span (extrude), Z = thickness
            rotate([-90, 0, 0]) {
                linear_extrude(height = slice_thickness, center = true)
                    airfoil2d(foil, chord_mm);
            }
        }
    }
}

// Connect two stations into a solid panel
module wing_panel(foil_root, foil_tip,
                  root_chord_mm, tip_chord_mm,
                  root_y_mm, tip_y_mm,
                  root_twist_deg=0, tip_twist_deg=0,
                  root_x_offset_mm=0, tip_x_offset_mm=0,
                  slice_thickness=0.6) {
    hull() {
        airfoil_section(foil_root, root_chord_mm,
                        root_y_mm, root_twist_deg, root_x_offset_mm,
                        slice_thickness);

        airfoil_section(foil_tip,  tip_chord_mm,
                        tip_y_mm,  tip_twist_deg,  tip_x_offset_mm,
                        slice_thickness);
    }
}

// station = [ y_mm, chord_mm, twist_deg, x_offset_mm, foil_id ]
module wing_from_stations(stations, slice_thickness=0.6) {
    for (i = [0 : len(stations)-2]) {
        station_root = stations[i];
        station_tip  = stations[i+1];

        y_root      = station_root[0];
        chord_r     = station_root[1];
        twist_r     = station_root[2];
        x_off_r     = station_root[3];
        foil_id_r   = station_root[4];

        y_tip       = station_tip[0];
        chord_t     = station_tip[1];
        twist_t     = station_tip[2];
        x_off_t     = station_tip[3];
        foil_id_t   = station_tip[4];

        foil_root   = get_foil(foil_id_r);
        foil_tip    = get_foil(foil_id_t);

        wing_panel(foil_root, foil_tip,
                   chord_r, chord_t,
                   y_root, y_tip,
                   twist_r, twist_t,
                   x_off_r, x_off_t,
                   slice_thickness);
    }
}

// -----------------------------------------------------------------
// Example stations
// station = [ y_mm, chord_mm, twist_deg, x_offset_mm, foil_id ]
//
// Here we keep the TRAILING EDGE straight at x = 160 mm:
//   root: chord = 160, LE at x = 0,  TE at x = 160
//   tip : chord =  40, LE at x = 120, TE at x = 160
// so x_offset_tip = 160 - 40 = 120
// -----------------------------------------------------------------

my_stations = [
    //  y_mm, chord_mm, twist_deg, x_offset_mm, foil_id
    [   0,     160,       0,        0,         FOIL_AG04 ],  // root
    [ 425,     140,       0,       12.5,         FOIL_AG04 ],  // mid (example)
    [ 600,      40,       0,      80,         FOIL_AG08 ],  // tip
];

// Flat half-wing
module base_wing(slice_thickness=0.6)
    wing_from_stations(my_stations, slice_thickness);

// Right wing: apply dihedral as rotation about X
module right_wing(dihedral_deg=6, slice_thickness=0.6)
    rotate([dihedral_deg, 0, 0])
        base_wing(slice_thickness);

// Left wing: mirror in Y after same dihedral
module left_wing(dihedral_deg=6, slice_thickness=0.6)
    mirror([0, 1, 0])
        rotate([dihedral_deg, 0, 0])
            base_wing(slice_thickness);

// Draw both halves
// Combine both halves and add angle of attack (AoA)
module full_wing(dihedral_deg = 6, aoa_deg = 0, slice_thickness = 0.6) {
    // AoA: rotation about Y (span) axis
    rotate([0, aoa_deg, 0]) {
        right_wing(dihedral_deg, slice_thickness);
        left_wing(dihedral_deg, slice_thickness);
    }
}

// Call this instead of right_wing()/left_wing()
full_wing(dihedral_deg = 6, aoa_deg = 5, slice_thickness = 0.6);
