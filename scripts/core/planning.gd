class_name Planning
extends RefCounted
## Bauplanungsregelwerk (Auftrag 7, Etappe 2): Gebaeudedefinitionen, Regeln je Zone und die Vorpruefung eines Vorhabens.
## Alle Werte sind kalibrierbare Spielwerte. Die Vorpruefung (`assess`) nutzen Bauherren vor dem Antrag, die Verwaltung bei der Pruefung
## und die KI zur Orientierung; sie liefert nur benannte Feststellungen, keine Meinung.

## Gebaeudedefinition: Sprite-Typ (CityGenerator.TYPES), Grundflaeche in Feldern, Geschosse, Einheiten je Geschoss, Kosten und Bauzeit
const DEFS := {
	"einfamilienhaus": {"label": "Einfamilienhaus", "sprite": "house", "w": 5, "h": 4, "floors": [1, 2], "units": 1, "use": "wohnen",
		"cost_cell": 1300.0, "days_cell": 1.6, "parking": 1, "zones": ["wohnen", "mischgebiet"]},
	"doppelhaus": {"label": "Doppelhaus", "sprite": "semi", "w": 4, "h": 2, "floors": [1, 2], "units": 2, "use": "wohnen",
		"cost_cell": 1250.0, "days_cell": 1.8, "parking": 2, "zones": ["wohnen", "mischgebiet"]},
	"mehrfamilienhaus": {"label": "Mehrfamilienhaus", "sprite": "apartment", "w": 6, "h": 5, "floors": [2, 4], "units": 3, "use": "wohnen",
		"cost_cell": 1100.0, "days_cell": 1.2, "parking": 4, "zones": ["wohnen", "mischgebiet"]},
	"wohn_gewerbehaus": {"label": "Wohn- und Geschäftshaus", "sprite": "apartment", "w": 6, "h": 4, "floors": [2, 5], "units": 2, "use": "misch",
		"cost_cell": 1250.0, "days_cell": 1.3, "parking": 4, "zones": ["mischgebiet"], "commercial_units": 1},
	"buerogebaeude": {"label": "Bürogebäude", "sprite": "office", "w": 5, "h": 4, "floors": [1, 5], "units": 2, "use": "gewerbe",
		"cost_cell": 1200.0, "days_cell": 1.2, "parking": 4, "zones": ["mischgebiet", "gewerbe", "oeffentlich"]},
	"lager_werkstatt": {"label": "Lager oder Werkstatt", "sprite": "warehouse", "w": 6, "h": 4, "floors": [1, 2], "units": 1, "use": "gewerbe",
		"cost_cell": 700.0, "days_cell": 0.9, "parking": 2, "zones": ["gewerbe", "industrie"], "delivery": true},
	"oeffentliches_gebaeude": {"label": "Öffentliches Gebäude", "sprite": "office", "w": 6, "h": 4, "floors": [1, 3], "units": 1, "use": "oeffentlich",
		"cost_cell": 1500.0, "days_cell": 1.4, "parking": 3, "zones": ["oeffentlich"]},
}

## Zusaetzliche Regeln je Zone: Gebuehren, Erschliessungsbeitrag je Feld, benoetigte Anschluesse, Anteil Freiflaeche, Besonderheiten
const ZONE_RULES := {
	"wohnen": {"fee_base": 150.0, "fee_floor_cell": 6.0, "levy_cell": 12.0, "needs": ["strasse", "strom", "wasser", "abwasser"], "min_free": 0.35,
		"note": "Wohngebiet: höchstens 3 Geschosse, mindestens 35 % Freifläche."},
	"mischgebiet": {"fee_base": 250.0, "fee_floor_cell": 8.0, "levy_cell": 15.0, "needs": ["strasse", "strom", "wasser", "abwasser"], "min_free": 0.2,
		"note": "Mischgebiet: Wohnen und Gewerbe, bis 6 Geschosse."},
	"gewerbe": {"fee_base": 200.0, "fee_floor_cell": 6.0, "levy_cell": 10.0, "needs": ["strasse", "strom", "wasser"], "min_free": 0.2, "delivery": true,
		"note": "Gewerbegebiet: Lieferzugang für Lastwagen erforderlich."},
	"industrie": {"fee_base": 300.0, "fee_floor_cell": 5.0, "levy_cell": 9.0, "needs": ["strasse", "strom", "wasser", "abwasser"], "min_free": 0.15, "delivery": true,
		"note": "Industriegebiet: Lieferzugang und Abwasseranschluss erforderlich, höchstens 2 Geschosse."},
	"oeffentlich": {"fee_base": 0.0, "fee_floor_cell": 0.0, "levy_cell": 0.0, "needs": ["strasse", "strom", "wasser", "abwasser"], "min_free": 0.3,
		"note": "Fläche für öffentliche Einrichtungen: nur öffentliche Träger und gemeinnützige Nutzung."},
}
const PUBLIC_APPLICANT := "stadt"
const TEMP_ACCESS_COST := 2500.0       # provisorische Baustellenzufahrt
const UTILITY_COST_CELL := {"strasse": 40.0, "strom": 25.0, "wasser": 30.0, "abwasser": 35.0}   # Erschliessungskosten je Feld Grundstueck
const UTILITY_DAYS := {"strasse": 8, "strom": 5, "wasser": 6, "abwasser": 7}


static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func rules(zone: String) -> Dictionary:
	var z: Dictionary = Parcels.ZONES.get(zone, {})
	var r: Dictionary = ZONE_RULES.get(zone, {})
	return {"zone": zone, "label": z.get("label", zone), "nutzungen": z.get("types", []), "max_geschosse": z.get("floors", 0), "max_bebauung": z.get("cover", 0.0),
		"gebuehr_basis": r.get("fee_base", 0.0), "gebuehr_je_geschossfeld": r.get("fee_floor_cell", 0.0), "erschliessungsbeitrag_je_feld": r.get("levy_cell", 0.0),
		"anschluesse": r.get("needs", []), "min_freiflaeche": r.get("min_free", 0.0), "lieferzugang": r.get("delivery", false), "hinweis": r.get("note", "")}


## Gebaeude, die in der Zone zulaessig sind (Definition und Zone passen zusammen).
static func allowed_defs(zone: String) -> Array:
	var out: Array = []
	for id in DEFS:
		if zone in DEFS[id].zones and Parcels.ZONES[zone].buildable:
			out.append(id)
	return out


static func build_cost(def_id: String, floors: int) -> float:
	var d: Dictionary = DEFS[def_id]
	return snappedf(float(d.w * d.h * floors) * float(d.cost_cell), 10.0)


static func build_days(def_id: String, floors: int) -> int:
	var d: Dictionary = DEFS[def_id]
	return int(ceil(float(d.w * d.h * floors) * float(d.days_cell) / 4.0))


static func units_of(def_id: String, floors: int) -> int:
	var d: Dictionary = DEFS[def_id]
	return int(d.units) * floors if d.use in ["wohnen", "misch"] else int(d.units)


## Vorpruefung: `app` enthaelt def, floors, parking (geplante Stellplaetze), financing {eigenmittel, kredit, kredit_gesichert, foerderung}.
## Ergebnis: ok (grundsaetzlich genehmigungsfaehig), blocking (Ablehnungsgruende), questions (behebbar), conditions (Auflagen),
## costs (Bau, Gebuehr, Erschliessung), days (Bau, Erschliessung), missing (fehlende Anschluesse), units.
static func assess(parcel: Dictionary, app: Dictionary) -> Dictionary:
	var blocking: Array = []
	var questions: Array = []
	var conditions: Array = []
	var d: Dictionary = DEFS.get(str(app.get("def", "")), {})
	if d.is_empty():
		return {"ok": false, "blocking": ["Gebäudeart unbekannt."], "questions": [], "conditions": [], "costs": {}, "days": {}, "missing": [], "units": 0}
	var zone: String = parcel.zone
	var zr: Dictionary = rules(zone)
	var floors := int(app.get("floors", d.floors[0]))
	if not Parcels.ZONES[zone].buildable:
		blocking.append("Die Fläche ist als %s ausgewiesen und nicht bebaubar." % zr.label)
	elif zone not in d.zones:
		blocking.append("%s ist im %s nicht zulässig (zulässig: %s)." % [d.label, zr.label, ", ".join(allowed_defs(zone).map(func(i): return DEFS[i].label))])
	if floors < int(d.floors[0]) or floors > int(d.floors[1]):
		blocking.append("%s hat %d bis %d Geschosse, beantragt sind %d." % [d.label, int(d.floors[0]), int(d.floors[1]), floors])
	if int(zr.max_geschosse) > 0 and floors > int(zr.max_geschosse):
		blocking.append("Im %s sind höchstens %d Geschosse zulässig, beantragt sind %d." % [zr.label, int(zr.max_geschosse), floors])
	var pw := int(parcel.rect[2])
	var ph := int(parcel.rect[3])
	var fits: bool = (int(d.w) <= pw and int(d.h) <= ph) or (int(d.w) <= ph and int(d.h) <= pw)
	if not fits:
		blocking.append("Die Grundfläche %d×%d passt nicht auf das Grundstück (%d×%d)." % [int(d.w), int(d.h), pw, ph])
	var foot := int(d.w) * int(d.h)
	var cover := float(foot) / maxf(1.0, float(parcel.area))
	if cover > float(zr.max_bebauung):
		blocking.append("Bebauung %d %% übersteigt die zulässigen %d %%." % [roundi(cover * 100.0), roundi(float(zr.max_bebauung) * 100.0)])
	var free_cells := int(parcel.area) - foot
	var parking := int(app.get("parking", 0))
	if parking < int(d.parking):
		questions.append("Es fehlen Stellflächen: geplant %d, erforderlich %d." % [parking, int(d.parking)])
	if free_cells - parking < ceil(float(zr.min_freiflaeche) * float(parcel.area)) - 0.5 and fits:
		questions.append("Die Freifläche ist zu klein: erforderlich %d %% des Grundstücks." % roundi(float(zr.min_freiflaeche) * 100.0))
	var util: Dictionary = parcel.get("erschliessung", {})
	var missing: Array = []
	for need in zr.anschluesse:
		if not util.get(need, false):
			missing.append(need)
	var levy := float(ZONE_RULES.get(zone, {}).get("levy_cell", 0.0)) * float(parcel.area)
	var dev_cost := 0.0
	var dev_days := 0
	for m in missing:
		dev_cost += float(UTILITY_COST_CELL[m]) * float(parcel.area)
		dev_days = maxi(dev_days, int(UTILITY_DAYS[m]))
	if not missing.is_empty():
		conditions.append({"typ": "erschliessung", "teile": missing,
			"text": "Erschließung herstellen: %s. Nutzung erst nach Anschluss." % ", ".join(missing)})
		conditions.append({"typ": "baustellenzufahrt", "text": "Provisorische Baustellenzufahrt herstellen (%s)." % Catalog.money(TEMP_ACCESS_COST)})
	if bool(zr.lieferzugang) and not util.get("strasse", false):
		blocking.append("Im %s ist ein Lieferzugang erforderlich; es gibt keinen Straßenzugang." % zr.label)
	var ground := int(d.w) * int(d.h) * floors
	var fee := float(zr.gebuehr_basis) + float(zr.gebuehr_je_geschossfeld) * float(ground)
	var cost := build_cost(str(app.def), floors)
	var costs := {"bau": cost, "gebuehr": snappedf(fee, 1.0), "erschliessungsbeitrag": snappedf(levy, 1.0), "erschliessung": snappedf(dev_cost, 1.0)}
	costs["gesamt"] = cost + costs.gebuehr + costs.erschliessungsbeitrag + costs.erschliessung
	# Finanzierung: nur gesicherte Mittel zaehlen; eine unverbindliche Kreditanfrage ist keine Finanzierung
	var fin: Dictionary = app.get("financing", {})
	var secured := float(fin.get("eigenmittel", 0.0)) + float(fin.get("foerderung", 0.0)) + (float(fin.get("kredit", 0.0)) if bool(fin.get("kredit_gesichert", false)) else 0.0)
	if fin.is_empty():
		questions.append("Das Finanzierungskonzept fehlt.")
	elif secured + 0.5 < float(costs.gesamt):
		var gap := float(costs.gesamt) - secured
		if float(fin.get("kredit", 0.0)) > 0.0 and not bool(fin.get("kredit_gesichert", false)):
			questions.append("Der Kredit ist nicht zugesagt; gesichert sind %s von %s." % [Catalog.money(secured), Catalog.money(float(costs.gesamt))])
		else:
			questions.append("Die Finanzierung ist nicht gesichert: es fehlen %s." % Catalog.money(gap))
	var days := {"bau": build_days(str(app.def), floors), "erschliessung": dev_days}
	var ok := blocking.is_empty()
	return {"ok": ok, "blocking": blocking, "questions": questions, "conditions": conditions, "costs": costs, "days": days,
		"missing": missing, "units": units_of(str(app.def), floors), "cover": cover}


## Kurze, lesbare Zusammenfassung der Vorpruefung (Oberflaeche und KI).
static func explain(a: Dictionary) -> String:
	var parts: Array = []
	parts.append("grundsätzlich geeignet" if a.ok else "nicht genehmigungsfähig")
	for b in a.blocking:
		parts.append("✗ " + b)
	for q in a.questions:
		parts.append("? " + q)
	for c in a.conditions:
		parts.append("• " + c.text)
	if not a.costs.is_empty():
		parts.append("Kosten gesamt %s (Bau %s, Gebühr %s, Beitrag %s, Erschließung %s)" % [Catalog.money(float(a.costs.gesamt)), Catalog.money(float(a.costs.bau)),
			Catalog.money(float(a.costs.gebuehr)), Catalog.money(float(a.costs.erschliessungsbeitrag)), Catalog.money(float(a.costs.erschliessung))])
	return "\n".join(parts)
