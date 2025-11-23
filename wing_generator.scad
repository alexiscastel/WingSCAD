// Wing generator from planform with twist, dihedral, and chordwise offset
// Thickness comes from airfoil profile; x_offset_mm lets you shift each
// section forward/backward (control sweep, LE/TE alignment).

$fn = 64;

function deg2rad(a) = a * PI / 180;
function clamp01(v) = v < 0 ? 0 : (v > 1 ? 1 : v);
function lerp(a, b, t) = a + (b - a) * t;

// --- Airfoils: include your generated SCAD data files ---
include <ag04.scad>;  // defines ag04_coords
include <ag08.scad>;  // defines ag08_coords

FOIL_AG04 = 0;
FOIL_AG08 = 1;

function get_foil(id) =
    id == FOIL_AG04 ? ag04_coords :
    id == FOIL_AG08 ? ag08_coords :
    ag04_coords; // default

function is_foil_profile(value) =
    is_list(value) && len(value) > 0 &&
    is_list(value[0]) && len(value[0]) == 2;

function resolve_foil(ref) =
    is_foil_profile(ref) ? ref : get_foil(ref);

function blend_airfoil(foil_a, foil_b, blend_t) =
    let(
        mix = clamp01(blend_t),
        count = min(len(foil_a), len(foil_b))
    )
    count <= 0 ? [] : [
        for (i = [0 : count - 1])
            [
                lerp(foil_a[i][0], foil_b[i][0], mix),
                lerp(foil_a[i][1], foil_b[i][1], mix)
            ]
    ];

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
            mirror([0, 0, 1])  // keep positive thickness pointing upward
                rotate([-90, 0, 0])
                    linear_extrude(height = slice_thickness, center = true)
                        airfoil2d(foil, chord_mm);
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

        foil_root   = resolve_foil(foil_id_r);
        foil_tip    = resolve_foil(foil_id_t);

        wing_panel(foil_root, foil_tip,
                   chord_r, chord_t,
                   y_root, y_tip,
                   twist_r, twist_t,
                   x_off_r, x_off_t,
                   slice_thickness);
    }
}

// -----------------------------------------------------------------
// Elliptical planform helper utilities
// -----------------------------------------------------------------
function elliptical_planform_chord(y_mm, span_mm,
                                   root_chord_mm, tip_chord_mm=0) =
    let(
        safe_span = span_mm <= 0 ? 1 : span_mm,
        span_ratio = clamp01(y_mm / safe_span),
        ellipse_factor = sqrt(max(0, 1 - span_ratio * span_ratio))
    )
    tip_chord_mm + (root_chord_mm - tip_chord_mm) * ellipse_factor;

function span_positions(span_mm, station_count, max_segment_mm=0) =
    let(
        safe_station_count = station_count < 2 ? 2 : station_count,
        uniform_positions = [
            for (i = [0 : safe_station_count - 1])
                span_mm * i / (safe_station_count - 1)
        ],
        refined_positions = max_segment_mm <= 0 ? uniform_positions :
            let(
                partial = [
                    for (idx = [0 : len(uniform_positions) - 2])
                        let(
                            y0 = uniform_positions[idx],
                            y1 = uniform_positions[idx + 1],
                            gap = y1 - y0,
                            segments = gap <= 0 ? 1 : ceil(gap / max_segment_mm),
                            step = gap / segments
                        )
                        for (s = [0 : segments - 1])
                            y0 + step * s
                ]
            )
            concat(partial, [uniform_positions[len(uniform_positions) - 1]])
    )
    refined_positions;

function elliptical_planform_stations(span_mm,
                                      root_chord_mm,
                                      tip_chord_mm=5,
                                      station_count=9,
                                      root_twist_deg=0,
                                      tip_twist_deg=0,
                                      root_x_offset_mm=0,
                                      tip_x_offset_mm=0,
                                      align_trailing_edge=true,
                                      sweep_per_mm=0,
                                      foil_root_id=FOIL_AG04,
                                      foil_tip_id=FOIL_AG08,
                                      foil_transition_t=1,
                                      foil_blend_width_t=0.15,
                                      max_span_section_mm=0) =
    let(
        safe_station_count = station_count < 2 ? 2 : station_count,
        te_target = root_x_offset_mm + root_chord_mm,
        transition = clamp01(foil_transition_t),
        blend_width = max(foil_blend_width_t, 0),
        blend_end = clamp01(transition + blend_width),
        root_foil = get_foil(foil_root_id),
        tip_foil = get_foil(foil_tip_id),
        y_positions = span_positions(span_mm, safe_station_count,
                                     max_span_section_mm),
        safe_span = span_mm <= 0 ? 1 : span_mm
    )
    [
        for (i = [0 : len(y_positions) - 1])
            let(
                y = y_positions[i],
                t = clamp01(y / safe_span),
                chord = elliptical_planform_chord(y, span_mm,
                                                  root_chord_mm, tip_chord_mm),
                twist = lerp(root_twist_deg, tip_twist_deg, t),
                foil_mix =
                    blend_end <= transition
                        ? (t >= transition ? 1 : 0)
                        : clamp01((t - transition) / (blend_end - transition)),
                station_foil =
                    blend_end <= transition
                        ? (t >= transition ? tip_foil : root_foil)
                        : blend_airfoil(root_foil, tip_foil, foil_mix),
                sweep_offset = sweep_per_mm * y,
                base_offset = align_trailing_edge
                              ? te_target - chord
                              : lerp(root_x_offset_mm, tip_x_offset_mm, t),
                x_offset = base_offset + sweep_offset
            )
            [ y, chord, twist, x_offset, station_foil ]
    ];

// -----------------------------------------------------------------
// Example stations
// station = [ y_mm, chord_mm, twist_deg, x_offset_mm, foil_id ]
//
// Here we keep the TRAILING EDGE straight at x = 160 mm:
//   root: chord = 160, LE at x = 0,  TE at x = 160
//   tip : chord =  40, LE at x = 120, TE at x = 160
// so x_offset_tip = 160 - 40 = 120
// -----------------------------------------------------------------

elliptical_span_mm = 600;
elliptical_root_chord_mm = 160;
elliptical_tip_chord_mm = 40;
elliptical_station_count = 13;   // includes root + tip
elliptical_root_twist_deg = 0;
elliptical_tip_twist_deg = -2;
elliptical_root_x_offset_mm = 0;
elliptical_tip_x_offset_mm = 120;
elliptical_align_trailing_edge = true;
elliptical_sweep_per_mm = 0;     // positive = more sweep toward tip
elliptical_foil_root = FOIL_AG04;
elliptical_foil_tip = FOIL_AG08;
elliptical_foil_transition = 0.6;  // start blending near 60% span
elliptical_foil_blend_width = 0.25; // blend smoothly toward tip
elliptical_max_span_section_mm = 20; // refine near tip by limiting panel length

elliptical_stations =
    elliptical_planform_stations(
        elliptical_span_mm,
        elliptical_root_chord_mm,
        elliptical_tip_chord_mm,
        elliptical_station_count,
        elliptical_root_twist_deg,
        elliptical_tip_twist_deg,
        elliptical_root_x_offset_mm,
        elliptical_tip_x_offset_mm,
        elliptical_align_trailing_edge,
        elliptical_sweep_per_mm,
        elliptical_foil_root,
        elliptical_foil_tip,
        elliptical_foil_transition,
        elliptical_foil_blend_width,
        elliptical_max_span_section_mm
    );

manual_stations = [
    //  y_mm, chord_mm, twist_deg, x_offset_mm, foil_id
    [   0,     160,       0,        0,         FOIL_AG04 ],  // root
    [ 425,     140,       0,       12.5,       FOIL_AG04 ],  // mid (example)
    [ 600,      40,       0,      120,         FOIL_AG08 ],  // tip
];

use_elliptical_planform = true;
my_stations = use_elliptical_planform ? elliptical_stations : manual_stations;

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
