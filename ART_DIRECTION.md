# Art Direction – Pixel Transport Rivals (verbindlich)

Zielbild: eine detailreiche, isometrisch wirkende **Miniaturstadt** mit plastischen Gebäuden, feiner
Voxelstruktur, gestalteten Grundstücken und stimmungsvoller Beleuchtung. Mitteleuropäische Architektur
(Mainz am Rhein) mit einzelnen hochwertigen Villen, Rheinpromenade, begrünten Wohnvierteln, Gewerbe und Logistik.

## 1. Projektion
- Feste orthografische **Dimetrie 2:1** (klassische Pixel-Isometrie), Blick aus Richtung (+x, +y, +z).
- Weltachsen: x = Osten (Bildschirm rechts-unten), y = Süden (links-unten), z = oben.
- Projektion eines Voxelpunkts: `sx = 2·(x − y)`, `sy = (x + y) − 2·z` (Pixel).
- Sichtbar sind je Voxel: Oberseite, +y-Seite (links), +x-Seite (rechts). Tiefe (Nähe) = `x + y + z`.
- Alle Gebäude, Böden, Fahrzeuge und Figuren werden mit **demselben Renderer** (`tools/vox/`) aus Voxelmodellen
  vorberechnet – dadurch identischer Winkel, identische Lichtrichtung und identische Pixeldichte.

## 2. Raster und Maßstab
- Simulation: unverändert quadratisches Raster, 1 Feld (Tile) = 32 Simulations-Pixel.
- 1 Feld = **32 × 32 Voxel**, 1 Voxel ≈ **10 cm**. Ein Feld erscheint als Raute **128 × 64 px**.
- Simulationsposition → Bildschirm: `screen = (2·(px − py), px + py)` (`Iso.to_screen`).
- Größenverhältnisse (leicht verdichtet, damit Fahrzeuge auf einspurige Straßen passen):

| Objekt | Voxel (L × B × H) | real ≈ | Bildschirmhöhe bei Zoom 1 |
|---|---|---|---|
| Erwachsene Figur | 5 × 4 × 18 | 1,8 m | ≈ 44 px |
| Lastenrad | 18 × 7 × 14 | | |
| Kleintransporter | 48 × 20 × 24 | 5 m | |
| Transporter / Kühlwagen | 60 × 22 × 30 | 6 m | |
| Lkw (Koffer) | 80 × 24 × 36 | 8 m | |
| Sattelzug | 120 × 24 × 38 | 12 m (verdichtet) | |
| Geschoss | 28 | 2,8 m | 56 px |
| Einfamilienhaus | 2 × 2 Felder, 2 Geschosse + Dach | | |
| Villa | 4 × 4 Felder | | |
| Hochhaus | 3 × 3 Felder, bis 14 Geschosse | | |

## 3. Grundstücke
Jedes Gebäude wird **mit seinem Grundstück** modelliert (Bodenplatte 1 Voxel): Hauptgebäude, Zugang, Wege,
Einfahrt/Stellplätze, Garten oder befestigte Fläche, Einfriedung, Leuchten, Gebrauchsgegenstände
(Fahrräder, Mülltonnen, Paletten …) und eine erkennbare Lieferstelle. Die Simulations-Grundfläche (`w × h`)
ist die Kollisionsfläche; Zugang (`walk`) und Lieferpunkt (`road`) liegen außerhalb auf Gehweg bzw. Straße.
Dekoration liegt nie auf Gehweg- oder Straßenfeldern.

## 4. Palette und Materialien
Zurückhaltend, warm: Sandstein, Putz (Creme, Ocker, Altrosa, Hellgrau), Ziegelrot/Terrakotta, Schiefergrau,
Holz; sattes, abwechslungsreiches Grün; kühle Glas-, Beton- und Industrieflächen (Blaugrau, Stahl).
Firmenfarben nur als Akzent (Schilder, Tore, Fahrzeugaufbauten, Fassadenstreifen, Kleidung) über eine
separate Farbmaske. Jedes Material hat Grundfarbe + leichtes Voxelrauschen; Ziegel/Dielen/Platten erhalten
Muster aus Voxelreihen.

## 5. Licht und Schatten
- Sonne von oben-links (Richtung zur Sonne ≈ (−1, 0, +1)): Oberseiten 100 %, linke Seiten 80 %, rechte Seiten 62 %.
- Umgebungsverdeckung an Kanten und Kontaktstellen, dunkle Silhouettenkante (1 px).
- Schlagschatten: im Grundstück eingebrannt, außerhalb als eigene halbtransparente Ebene.
- Nacht: Multiplikative Abdunklung; darüber additive Lichtebene aus **Emissionsmasken** (Fenster, Eingänge,
  Laternen, Werkstatt-/Ladehofbeleuchtung, Fahrzeuglichter). Fenster leuchten unterschiedlich (Zufall pro Fenster).
  Lokale farbige Akzente (z. B. rote Leuchtreklame, Kühlhaus-Blau) sparsam.
- Wetter: Dach-/Bodenmaske (Oberseiten) für Schnee und Nässe; Regen- und Nebelpartikel bleiben unter der UI und
  verdecken keine Figuren/Symbole.

## 6. Detailgrad
- Zoom 1 (Normal): Dachziegelreihen, Fensterrahmen, Geländer, Pflanzen, Fahrzeugfenster/-räder/-leuchten, Beruf
  der Figuren (Kleidung, Helm, Weste, Werkzeug) und Firmenfarbe erkennbar.
- Zoom 2 (Nah): einzelne Ziegel, Fensterkreuze, Briefkästen, Blumentöpfe.
- Pixel werden nie gefiltert (Nearest), Zoomstufen nur ganzzahlig oder 0,5.

## 7. Tiefensortierung
Gebäude werden in senkrechte Streifen von 64 px zerlegt; jeder Streifen sortiert nach der Vorderkante seiner
Grundfläche. Figuren und Fahrzeuge sortieren nach ihrem Fußpunkt. Verdeckt ein Gebäude ausgewählte oder
arbeitende Figuren, wird es halbtransparent. Symbole, Sprechblasen und Namensschilder liegen immer oben.

## 8. Assetstruktur (`assets/iso/`)
`<name>.png` Farbe · `<name>_lit.png` Emission · `<name>_top.png` Oberseitenmaske · `<name>_mask.png`
Firmenfarbe (optional) · `<name>_shadow.png` Außenschatten (optional) · `manifest.json` mit Grundfläche,
Ankerpunkt (Bildposition der hinteren Grundstücksecke), Eingang, Lieferstelle, Höhe, Animationsdaten.

## 9. Umsetzung (Stand 25.10.2026)
- Renderer: `tools/vox/engine.py` (Voxel → Dimetrie, Schatten, Kantenabdunklung, Emissions-, Dach- und Firmenmasken).
- Modelle: `residential.py`, `commercial.py`, `industrial.py`, `buildings.py` (Villa), `facilities.py`, `vehicles.py`, `figures.py`, `props.py`, `ground.py`.
- Bau: `python tools/build_iso.py` schreibt `assets/iso/*.png` und `manifest.json` (Anker, Pivot, Größen). Ground-Atlas: Zellen 128 × 72 px, Ursprung (64, 6).
- Spiel: `Iso` rechnet Welt ↔ Bildschirm; Gebäude werden in 64-px-Streifen nach der Vorderkante ihrer Grundfläche sortiert; Fahrzeuge und Figuren sortieren über den Fußpunkt (y-Sortierung).
- Firmenfarbe: Maskenebene (`*_mask.png`), im Spiel mit der Firmenfarbe eingefärbt. Neutrale Gebäude haben die Maske eingebacken.
- Zoom ≥ 1: harte Pixel (Nearest); darunter Mipmaps (ruhiges Verkleinern).
