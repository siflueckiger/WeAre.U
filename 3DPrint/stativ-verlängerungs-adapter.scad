// --- PARAMETER (in mm) ---
$fn = 100; // Glatte Rundungen

// Gemessene Maße + Toleranz
toleranz = 0.4;
griff_od = 30.7 + toleranz;       // Aussendurchmesser Sterngriff (3.07 cm)
stufen_id = 25.4 + toleranz;      // Innendurchmesser Stufe (2.54 cm)
schraube_d = 6.0 + toleranz;      // Gewindedurchmesser (M6 / 0.6 cm)
gesamthoehe = 37.7;              // Gesamthöhe (3.77 cm)

// Zylinder-Dimensionen für das Gehäuse
zylinder_h = 45;                  // Gesamthöhe des Gehäuse-Zylinders
zylinder_d = griff_od + 8;        // Wandsatärke rundherum ca. 4mm

// Tiefen der Aussparungen (Anpassbar je nach Höhe des Sterngriffs)
griff_tiefe = 15;                 // Tiefe für den Sterngriff oben
stufen_tiefe = 8;                 // Tiefe für die innere Stufe

// --- MODELLIERUNG ---
difference() {
    // 1. Hauptzylinder (Außenform)
    cylinder(h = zylinder_h, d = zylinder_d);

    // 2. Aussparung für die Schraube (geht ganz durch)
    translate([0, 0, -1])
        cylinder(h = zylinder_h + 2, d = schraube_d);

    // 3. Aussparung für den Sterngriff (Negativform gegen Verdrehen)
    translate([0, 0, zylinder_h - griff_tiefe]) {
        // 6-Zack Sternform für verdrehsicheren Halt
        for (a = [0 : 60 : 300]) {
            rotate([0, 0, a])
                cylinder(h = griff_tiefe + 1, d = griff_od, $fn = 6);
        }
    }

    // 4. Aussparung für die innere Stufe/Einbuchtung
    translate([0, 0, zylinder_h - griff_tiefe - stufen_tiefe])
        cylinder(h = stufen_tiefe + 0.1, d = stufen_id);
}