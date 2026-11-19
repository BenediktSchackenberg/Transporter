"""Rebuild the 240 deterministic, individually priced city building designs.

Run from the repository root: python tools/generate_design_catalog.py
The voxel models are generated separately by python tools/build_iso.py designs.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STYLES = [
    ("hafenort", "Hafen", "Backstein, dunkle Dächer und kleine Höfe"),
    ("buchtenstadt", "Bucht", "helle Fassaden, Glas und Terrassen"),
    ("gartenstadt", "Garten", "warme Fassaden, Gärten und Solardächer"),
    ("hangstadt", "Hang", "Naturstein, Stufen und robuste Dächer"),
    ("flussstadt", "Fluss", "Putz, Balkone und begrünte Uferhöfe"),
    ("marktort", "Markt", "Ziegel, Schaufenster und belebte Vorplätze"),
]
HOMES = [
    ("einfamilienhaus", "Haus", 110, 1),
    ("doppelhaus", "Doppelhaus", 82, 2),
    ("mehrfamilienhaus", "Wohnhaus", 67, 3),
    ("stadtvilla", "Villa", 165, 1),
    ("hochhaus", "Stadtturm", 58, 4),
]
FIRMS = [
    ("supermarkt", "Markthalle", "lebensmittel"),
    ("baeckerei_laden", "Backhaus", "baeckerei"),
    ("getraenkemarkt", "Getränkehaus", "getraenke"),
    ("drogerie_laden", "Drogerie", "drogerie"),
    ("moebelhaus", "Möbelhaus", "moebel"),
    ("technik_fachmarkt", "Technikhaus", "technik"),
    ("restaurant_neu", "Gasthaus", "restaurant"),
    ("buerogebaeude", "Kontor", "buero"),
    ("lager_werkstatt", "Gewerbehof", "werkstatt"),
    ("wohn_gewerbehaus", "Stadtpassage", "misch"),
]
HOME_AMENITIES = [
    ("Klassik", ["Balkon", "Fahrradraum"], 55, 1.00, 1.00),
    ("Garten", ["Garten", "Spielplatz", "Fahrradraum"], 67, 1.14, 0.94),
    ("Solar", ["Solarstrom", "Dämmung", "Wassersparen", "Balkon"], 74, 1.25, 0.72),
    ("Komfort", ["Aufzug", "Terrasse", "Dämmung", "Internet"], 86, 1.44, 0.78),
]
FIRM_AMENITIES = [
    ("Basis", ["Lager", "Lieferzugang"], 1.00, 1.00, 1.00),
    ("Plus", ["Internet", "Solarstrom", "Barrierefreiheit", "Schaufenster"], 1.28, 1.12, 0.80),
]


def build():
    designs = []
    for family, (base, label, area, units) in enumerate(HOMES):
        for style_index, (style, style_label, description) in enumerate(STYLES):
            for variant, (quality, amenities, comfort, price, energy) in enumerate(HOME_AMENITIES):
                n = family * 24 + style_index * 4 + variant + 1
                designs.append({
                    "id": f"design_w_{n:03d}", "category": "wohnen", "base": base,
                    "style": style, "label": f"{style_label}-{label} {quality}",
                    "appearance": description, "amenities": amenities,
                    "area": area + (variant * 4) + (style_index % 3) * 3,
                    "units_per_floor": units, "comfort": comfort + (style_index % 3) * 2,
                    "cost_factor": round(price * (1.0 + family * 0.04 + style_index * 0.012), 3),
                    "energy_factor": energy, "appeal": round(0.85 + comfort / 350.0, 3),
                    "water_factor": [1.0, 1.15, 0.86, 1.08][variant],
                    "maintenance_month": 95 + family * 35 + variant * 28,
                    "sprite": f"design_w_{n:03d}", "variant": variant,
                })
    for family, (base, label, function) in enumerate(FIRMS):
        for style_index, (style, style_label, description) in enumerate(STYLES):
            for variant, (quality, amenities, price, appeal, energy) in enumerate(FIRM_AMENITIES):
                n = family * 12 + style_index * 2 + variant + 1
                designs.append({
                    "id": f"design_g_{n:03d}", "category": "gewerbe", "base": base,
                    "style": style, "label": f"{style_label}-{label} {quality}",
                    "appearance": description, "amenities": amenities, "function": function,
                    "comfort": 45 + variant * 20 + style_index % 3 * 2,
                    "cost_factor": round(price * (1.0 + family * 0.035 + style_index * 0.012), 3),
                    "energy_factor": energy, "appeal": round(appeal + (style_index % 3) * 0.025, 3),
                    "water_factor": 1.0 if variant == 0 else 0.84,
                    "capacity_factor": round(1.0 + variant * 0.12, 3),
                    "maintenance_month": 180 + family * 30 + variant * 75,
                    "sprite": f"design_g_{n:03d}", "variant": variant,
                })
    return designs


if __name__ == "__main__":
    path = ROOT / "config" / "building_designs.json"
    path.write_text(json.dumps({"version": 1, "designs": build()}, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(f"{path}: {len(build())} designs")
