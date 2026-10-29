class_name CityGoods
extends RefCounted
## Warenkatalog der Stadtverwaltung (Auftrag 5, Abschnitt 3). Erweiterbar: neue Gruppen und Artikel in GROUPS eintragen.
##
## Je Artikel: Gruppe, Einheit, Klasse (verbrauch | lager | geraet), Lagerbereich, Preis, Zielbestand, Meldebestand, Mindestbestand, Lagerkapazitaet,
## erwarteter Verbrauch je Tag, Lieferzeit (Tage, bei Import +IMPORT_LEAD), Kritikalitaet (1 niedrig .. 3 hoch). Abgeleitet aus dem Zielbestand,
## sofern der Artikel nichts anderes vorgibt. Artikel mit gleicher ID wie ein Material des privaten Grosshaendlers (Trader.MATERIALS) kauft die Stadt dort
## ein, alle anderen im Ausland (Import) oder bei Unternehmen, die sich als Lieferant anbieten.

const IMPORT_LEAD := 3
const IMPORT_FACTOR := 0.95        # Importpreis gegenueber dem Katalogpreis
## Lagerbereiche des Zentrallagers: Kapazitaet in Einheiten (je Artikel mit Einheit). Getrennt wegen unterschiedlicher Lagerung.
const ZONES := {
	"schuettgut": {"label": "Schüttgut (Freilager)", "cap": 6000},
	"regal": {"label": "Palettenregale", "cap": 20000},
	"lebensmittel": {"label": "Lebensmittel (gekühlt)", "cap": 500},
	"kraftstoff": {"label": "Tanklager", "cap": 20000},
	"geraete": {"label": "Geräte- und Fahrzeughalle", "cap": 120},
}
## Gruppe: {label, zone, class, crit, items: [[id, Name, Einheit, Preis, Zielbestand, {Abweichungen}]]}
const GROUPS := {
	"strassenunterbau": {"label": "Straßenunterbau", "zone": "schuettgut", "class": "verbrauch", "crit": 3, "items": [
		["sand", "Sand", "t", 14.0, 500], ["kies", "Kies", "t", 18.0, 500], ["schotter", "Schotter", "t", 24.0, 600], ["tragschicht", "Tragschichtmaterial", "t", 28.0, 400]]},
	"strassenoberflaechen": {"label": "Straßenoberflächen", "zone": "schuettgut", "class": "verbrauch", "crit": 3, "items": [
		["asphalt", "Asphaltmischung", "t", 85.0, 300], ["bitumen", "Bitumenprodukte", "t", 140.0, 80], ["pflaster", "Pflastersteine", "t", 60.0, 200],
		["bordstein", "Bordsteine", "Stk", 22.0, 400], ["betonfertigteil", "Betonfertigteile", "Stk", 75.0, 200]]},
	"verkehrsfuehrung": {"label": "Verkehrsführung", "zone": "regal", "class": "verbrauch", "crit": 2, "items": [
		["verkehrsschild", "Verkehrsschilder", "Stk", 55.0, 120], ["schilderpfosten", "Schilderpfosten", "Stk", 28.0, 120], ["markierfarbe", "Fahrbahnmarkierungsfarbe", "Eimer", 48.0, 80],
		["absperrgitter", "Absperrgitter", "Stk", 35.0, 150, {"class": "geraet"}], ["leitkegel", "Leitkegel", "Stk", 9.0, 300, {"class": "geraet"}],
		["baustellenleuchte", "Baustellenleuchten", "Stk", 26.0, 100, {"class": "geraet"}]]},
	"elektro": {"label": "Beleuchtung und Elektrotechnik", "zone": "regal", "class": "verbrauch", "crit": 2, "items": [
		["strassenleuchte", "Straßenleuchten", "Stk", 420.0, 40], ["leuchtmittel", "Leuchtmittel", "Stk", 18.0, 300], ["kabel", "Kabel", "m", 3.2, 2000],
		["verteilerkasten", "Verteilerkästen", "Stk", 260.0, 20], ["steuerung", "Steuerungskomponenten", "Stk", 190.0, 30, {"crit": 3}]]},
	"leitungen": {"label": "Leitungen und Entwässerung", "zone": "regal", "class": "verbrauch", "crit": 3, "items": [
		["rohr", "Rohre", "m", 11.0, 1200], ["dichtung", "Dichtungen", "Stk", 4.0, 600], ["armatur", "Armaturen", "Stk", 48.0, 120],
		["pumpe", "Pumpen", "Stk", 380.0, 12, {"class": "lager"}], ["filter", "Filter", "Stk", 36.0, 80], ["kanaldeckel", "Kanalabdeckungen", "Stk", 95.0, 60]]},
	"gebaeude": {"label": "Gebäudereparaturen", "zone": "regal", "class": "verbrauch", "crit": 2, "items": [
		["holz", "Holz", "m³", 18.0, 120], ["ziegel", "Ziegel", "Stk", 12.0, 600], ["dachmaterial", "Dachmaterial", "m²", 22.0, 300], ["glas", "Glas", "m²", 35.0, 100],
		["daemmung", "Dämmmaterial", "m²", 9.0, 400], ["farbe", "Farben", "Eimer", 21.0, 150], ["verbindung", "Verbindungsmaterial", "Pack", 6.0, 400]]},
	"gruenpflege": {"label": "Grünpflege", "zone": "schuettgut", "class": "verbrauch", "crit": 1, "items": [
		["erde", "Erde", "t", 16.0, 200], ["kompost", "Kompost", "t", 20.0, 120], ["saatgut", "Saatgut", "kg", 8.0, 300], ["pflanzen", "Pflanzen", "Stk", 4.5, 500],
		["jungbaum", "Jungbäume", "Stk", 65.0, 60], ["bewaesserung", "Bewässerungsmaterial", "Set", 30.0, 60], ["gartengeraet", "Gartengeräte", "Stk", 45.0, 40, {"class": "geraet", "zone": "geraete"}]]},
	"winterdienst": {"label": "Winterdienst", "zone": "schuettgut", "class": "verbrauch", "crit": 2, "items": [
		["streusalz", "Streumittel", "t", 70.0, 250, {"use": 0.2}], ["splitt", "Splitt", "t", 30.0, 250, {"use": 0.2}],
		["winterdienstteil", "Ersatzteile Winterdienstgeräte", "Stk", 140.0, 20, {"zone": "regal", "class": "lager"}]]},
	"reinigung": {"label": "Reinigung und Abfall", "zone": "regal", "class": "verbrauch", "crit": 1, "items": [
		["muellbehaelter", "Müllbehälter", "Stk", 48.0, 150, {"class": "lager"}], ["muellsack", "Säcke", "Pack", 6.0, 600], ["besen", "Besen", "Stk", 7.0, 80, {"class": "geraet"}],
		["reinigungsgeraet", "Reinigungsgeräte", "Stk", 190.0, 12, {"class": "geraet", "zone": "geraete"}], ["hygiene", "Reinigungs- und Hygieneartikel", "Pack", 12.0, 400]]},
	"verwaltung": {"label": "Verwaltung und öffentliche Gebäude", "zone": "regal", "class": "verbrauch", "crit": 1, "items": [
		["papier", "Papier", "Pal", 90.0, 30], ["buero", "Büromaterial", "Pack", 14.0, 200], ["computer", "Computer", "Stk", 640.0, 20, {"class": "lager"}],
		["moebel", "Möbel", "Stk", 180.0, 40, {"class": "lager"}], ["lampe", "Beleuchtung (Gebäude)", "Stk", 32.0, 120], ["gebaeudeteil", "Ersatzteile Gebäudetechnik", "Stk", 55.0, 80]]},
	"schule": {"label": "Schulen und Kindergärten", "zone": "regal", "class": "verbrauch", "crit": 2, "items": [
		["buch", "Bücher", "Stk", 16.0, 400, {"class": "lager"}], ["lernmaterial", "Lernmaterial", "Set", 22.0, 200], ["spielgeraet", "Spielgeräte", "Stk", 120.0, 25, {"class": "lager"}],
		["schulmoebel", "Schulmöbel", "Stk", 110.0, 60, {"class": "lager"}], ["sportmaterial", "Sportmaterial", "Set", 70.0, 40, {"class": "lager"}],
		["verpflegung", "Verpflegung", "Port", 3.2, 400, {"zone": "lebensmittel", "class": "verbrauch", "crit": 3, "use": 40.0, "shelf": 6}]]},
	"einsatz": {"label": "Einsatzdienste", "zone": "regal", "class": "verbrauch", "crit": 3, "items": [
		["schutzkleidung", "Schutzkleidung", "Satz", 130.0, 60, {"class": "lager"}], ["funkgeraet", "Funkgeräte", "Stk", 280.0, 20, {"class": "lager"}],
		["schlauch", "Schläuche", "m", 14.0, 400, {"class": "lager"}], ["erstehilfe", "Erste-Hilfe-Material", "Set", 24.0, 200], ["sanitaet", "Sanitätsverbrauchsmaterial", "Pack", 18.0, 300]]},
	"fuhrpark": {"label": "Fuhrpark und Werkstatt", "zone": "regal", "class": "verbrauch", "crit": 2, "items": [
		["reifen", "Reifen", "Stk", 140.0, 60], ["fahrzeugfilter", "Fahrzeugfilter", "Stk", 22.0, 120], ["batterie", "Batterien", "Stk", 110.0, 30], ["schmiermittel", "Schmiermittel", "l", 7.0, 500],
		["werkzeug", "Werkzeuge", "Stk", 60.0, 40, {"class": "geraet"}], ["fahrzeugteil", "Fahrzeugersatzteile", "Stk", 85.0, 80]]},
	"betriebsmittel": {"label": "Betriebsmittel", "zone": "kraftstoff", "class": "verbrauch", "crit": 3, "items": [
		["diesel", "Diesel", "l", 1.7, 8000, {"use": 220.0}], ["benzin", "Benzin", "l", 1.8, 3000, {"use": 80.0}], ["adblue", "Harnstofflösung", "l", 0.9, 1500, {"use": 30.0}]]},
	"geraete": {"label": "Maschinen und wiederverwendbare Geräte", "zone": "geraete", "class": "geraet", "crit": 2, "items": [
		["gabelstapler", "Gabelstapler", "Stk", 14000.0, 3, {"use": 0.0}], ["hubwagen", "Hubwagen", "Stk", 380.0, 8, {"use": 0.0}], ["kompaktor", "Kompaktoren", "Stk", 5200.0, 2, {"use": 0.0}],
		["baugeraet", "Baustellengeräte", "Stk", 2400.0, 6, {"use": 0.0}], ["arbeitsmaschine", "Kommunale Arbeitsmaschinen", "Stk", 31000.0, 2, {"use": 0.0}]]},
}

static var _cache := {}


## Alle Artikel als Dictionary id -> Definition (abgeleitete Werte sind eingetragen).
static func items() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	for gid in GROUPS:
		var g: Dictionary = GROUPS[gid]
		for row in g["items"]:
			var extra: Dictionary = row[5] if row.size() > 5 else {}
			var target := int(row[4])
			var d := {"id": row[0], "name": row[1], "unit": row[2], "price": float(row[3]), "target": target, "group": gid, "group_label": g["label"],
				"zone": extra.get("zone", g["zone"]), "class": extra.get("class", g["class"]), "crit": int(extra.get("crit", g["crit"])),
				"lead": int(extra.get("lead", 3)), "shelf": int(extra.get("shelf", 0))}
			var geraet: bool = d["class"] == "geraet"
			d["use"] = float(extra.get("use", 0.0 if geraet else maxf(0.05, float(target) / 90.0)))   # erwarteter Verbrauch je Tag
			d["reorder"] = maxi(1, int(round(float(target) * 0.5)))
			d["min"] = maxi(0, int(round(float(target) * 0.25)))
			d["cap"] = maxi(target, int(round(float(target) * 2.0)))
			_cache[row[0]] = d
	return _cache


static func get_item(id: String) -> Dictionary:
	return items().get(id, {})


static func exists(id: String) -> bool:
	return items().has(id)


## Verfuegbare Anbieter fuer den Artikel: private Grosshaendler (T0, falls dort gefuehrt) und Import (X0). Unternehmen kommen ueber Angebote hinzu.
static func base_suppliers(id: String) -> Array:
	var out: Array = []
	if Trader.MATERIALS.has(id):
		out.append("T0")
	out.append("X0")
	return out


static func volume_of(item: String, qty: int) -> int:
	return qty
