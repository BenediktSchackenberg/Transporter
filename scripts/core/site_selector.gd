class_name SiteSelector
extends RefCounted
## Auftrag 8, Etappe 3 (docs/CITY_PLANNING.md): eine gemeinsame Standortpruefung fuer alle Bauvorhaben.
##
##   harte Pruefung (Grundstueck frei, Eigentum/Stadt, Zone passt, Grundflaeche passt ohne Ueberlappung, Strassenanschluss,
##   kein Gruenzug des Stadtplans)  ->  begrenzte Kandidatenmenge  ->  Bewertung nach sieben normierten Kriterien (0..1)
##   ->  Wahl mit kurzer Begruendung und den wichtigsten zurueckgestellten Alternativen  ->  atomare Reservierung, erneute Pruefung
##   beim Auftrag.
## Gibt es keinen gueltigen Standort, nennt das Ergebnis einen konkreten naechsten Schritt (z. B. Erschliessung genau der Grundstuecke,
## auf die der Bau passen wuerde) – es wird nie ungeprueft woanders gebaut.

const MAX_CANDS := 60      # hoechstens so viele gueltige Kandidaten bewerten (naechste zum Kern zuerst)
const MAX_DIST := 60.0     # Suchradius um den Stadtkern
## Nutzungsarten und ihre Gewichte (konfigurierbar; je Stadtprofil angepasst in _weights).
const WEIGHTS := {
	"wohnen": {"bedarf": 2.0, "nachbarschaft": 1.5, "struktur": 2.0, "erreichbar": 1.0, "kosten": 1.0, "profil": 1.5, "landschaft": 0.5},
	"versorgung": {"bedarf": 3.0, "nachbarschaft": 1.0, "struktur": 1.5, "erreichbar": 1.5, "kosten": 0.5, "profil": 1.0, "landschaft": 0.0},
	"gewerbe": {"bedarf": 1.0, "nachbarschaft": 2.0, "struktur": 1.5, "erreichbar": 2.0, "kosten": 1.0, "profil": 1.5, "landschaft": 0.0},
	"laerm": {"bedarf": 0.5, "nachbarschaft": 3.0, "struktur": 1.0, "erreichbar": 2.0, "kosten": 1.0, "profil": 1.5, "landschaft": 0.0},
	"oeffentlich": {"bedarf": 2.5, "nachbarschaft": 1.0, "struktur": 1.5, "erreichbar": 1.5, "kosten": 0.5, "profil": 1.0, "landschaft": 0.5},
	"tourismus": {"bedarf": 1.0, "nachbarschaft": 1.5, "struktur": 1.0, "erreichbar": 1.0, "kosten": 0.5, "profil": 1.5, "landschaft": 3.0},
}
## Zulaessige Zonen je Nutzungsart (die Zone des Grundstuecks muss passen)
const ART_ZONES := {
	"wohnen": ["wohnen", "mischgebiet"], "versorgung": ["mischgebiet", "wohnen", "gewerbe"], "gewerbe": ["gewerbe", "industrie", "mischgebiet"],
	"laerm": ["gewerbe", "industrie"], "oeffentlich": ["mischgebiet", "oeffentlich", "wohnen", "gewerbe"], "tourismus": ["mischgebiet", "wohnen"],
}
## Bevorzugte Viertelzone je Nutzungsart (Stadtstruktur)
const ART_DISTRICT := {"wohnen": ["wohnen", "mischgebiet"], "versorgung": ["mischgebiet", "wohnen"], "gewerbe": ["gewerbe"], "laerm": ["gewerbe", "industrie"],
	"oeffentlich": ["mischgebiet", "wohnen"], "tourismus": ["mischgebiet", "wohnen"]}
const LOUD_TYPES := ["warehouse", "freight_shed", "factory", "depot", "workshop", "workshop_small", "incineration_plant", "containers", "gas_station", "crane"]
const HOME_TYPES := ["house", "semi", "villa", "apartment", "highrise"]
const NAMES := {"bedarf": "Bedarf", "nachbarschaft": "Nachbarschaft", "struktur": "Stadtstruktur", "erreichbar": "Erreichbarkeit",
	"kosten": "Kosten", "profil": "Gestaltungsprofil", "landschaft": "Landschaft"}

var sim


func setup(simulation) -> void:
	sim = simulation


## Nutzungsart aus einer Bezeichnung (kommunale Dienste, Vorlagen): laute Betriebe abseits der Wohnhaeuser.
static func art_of(label: String) -> String:
	var l := label.to_lower()
	for w in ["abfall", "klär", "klaer", "bauhof", "werkstatt", "fahrzeugwerk", "werk ", "fabrik", "kfz", "recycling", "deponie", "müll", "muell", "wasserwerk", "hochbehälter", "kraftwerk", "lager", "betriebshof", "strassenmeisterei", "straßenmeisterei"]:
		if l.contains(w):
			return "laerm"
	for w in ["hotel", "pension", "kurhaus", "strandbad"]:
		if l.contains(w):
			return "tourismus"
	for w in ["laden", "markt", "bäckerei", "baeckerei", "drogerie", "restaurant", "kiosk", "apotheke", "café", "cafe"]:
		if l.contains(w):
			return "versorgung"
	return "oeffentlich"


## Standort waehlen. req: {w, h, art, label, zones?: Array, floors?: int, holder?: String (privater Antragsteller, darf eigene Grundstuecke),
## allow_no_road?: bool, district?: String (alte Wunschangabe "Zentrum/Wohngebiet/Rand")}.
## Ergebnis: {ok, rect: [x,y,w,h], parcel, score, viertel, begruendung, alternativen: [{parcel, score, warum}], kriterien} oder
## {ok: false, msg, naechster_schritt, ohne_strasse: [parcel ids]}.
func choose(k: int, req: Dictionary) -> Dictionary:
	var ranked := rank(k, req)
	if ranked.list.is_empty():
		return _none(k, req, ranked)
	var best: Dictionary = ranked.list[0]
	var alts: Array = []
	for i in range(1, mini(4, ranked.list.size())):
		var c: Dictionary = ranked.list[i]
		alts.append({"parcel": c.parcel, "score": c.score, "warum": _why_worse(c, best)})
	var out := {"ok": true, "rect": best.rect, "parcel": best.parcel, "score": best.score, "viertel": best.viertel_text,
		"kriterien": best.parts, "alternativen": alts, "kandidaten": ranked.list.size()}
	out["begruendung"] = _reason(req, best, alts)
	if sim.town_plan != null:
		sim.town_plan.note_decision(k, {"was": str(req.get("label", req.get("art", "Bau"))), "grundstueck": best.parcel, "viertel": best.viertel_text,
			"begruendung": out.begruendung, "alternativen": alts.map(func(a): return "%s: %s" % [a.parcel, a.warum])})
	return out


## Alle gueltigen Kandidaten, absteigend bewertet: {list: [{parcel, rect, score, parts, viertel_text, ...}], ohne_strasse: [ids], gruen: int}
func rank(k: int, req: Dictionary) -> Dictionary:
	var w := int(req.get("w", 3))
	var h := int(req.get("h", 3))
	var art := str(req.get("art", "oeffentlich"))
	var zones: Array = req.get("zones", ART_ZONES.get(art, ["mischgebiet"]))
	var holder := str(req.get("holder", ""))
	var wanted_district := str(req.get("district", "")).to_upper()
	var kern := _kern(k)
	var out := {"list": [], "ohne_strasse": [], "gruen": 0, "zu_klein": 0}
	if kern.x < 0:
		return out
	# Vorauswahl: freie, bebaubare Grundstuecke der Stadt (oder des Antragstellers) im Umkreis, naechste zuerst
	var pre: Array = []
	for p in sim.parcels.items.values():
		if str(p.state) != "frei" or not sim.parcels.is_buildable(p) or str(p.zone) not in zones:
			continue
		var own := str(p.owner)
		if not ((Towns.is_public(own) and Towns.town_of_owner(own) == k) or (holder != "" and own == holder)):
			continue
		var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		var d := Vector2(pr.get_center()).distance_to(Vector2(kern))
		if d > MAX_DIST:
			continue
		if pr.size.x < w or pr.size.y < h:
			out.zu_klein += 1
			continue
		pre.append([d, p, pr])
	pre.sort_custom(func(a, b): return a[0] < b[0])
	var ctx := _context(k, kern)
	var maxprice := 1.0
	var valid: Array = []
	for e in pre:
		if valid.size() >= MAX_CANDS:
			break
		var p: Dictionary = e[1]
		var pr: Rect2i = e[2]
		var v: Dictionary = sim.town_plan.district_at(k, pr.get_center()) if sim.town_plan != null else {}
		var fringe := false
		if v.is_empty() and sim.town_plan != null and sim.town_plan.has(k) and art != "laerm":
			# Kleine Gruendungsviertel haben kaum Platz fuer ganze Parzellen. Ihr direkter Rand
			# darf mitwachsen; entfernte Einzelstandorte werden nicht als Stadt verkauft.
			var nearest := INF
			for district in sim.town_plan.of(k).get("viertel", []):
				if str(district.zone) not in ART_DISTRICT.get(art, []):
					continue
				var midpoint := Vector2(float(district.mitte[0]), float(district.mitte[1]))
				var distance := Vector2(pr.get_center()).distance_to(midpoint)
				if distance <= float(district.radius) + 6.0 and distance < nearest:
					v = district
					nearest = distance
					fringe = true
		if sim.town_plan != null and sim.town_plan.has(k) and art != "laerm" and v.is_empty() and not sim.wildnis:
			continue
		# 25.11. (Benedikt: "er nutzt die Bauflaechen gar nicht aus"): in der Wildnis waren die Viertel voll (Radius 6-10), freie
		# 8x6-Grundstuecke mit Strasse 28-41 Felder vom Kern galten als "ausserhalb" – der Bautraeger baute 10 Tage nichts bei 39
		# Wartenden. Dort waechst die Stadt jetzt im Suchradius weiter (Strassenanschluss prueft _fit).
		if not v.is_empty() and str(v.zone) not in ART_DISTRICT.get(art, []):
			continue
		if wanted_district.begins_with("V") and wanted_district.substr(1).is_valid_int() and (v.is_empty() or str(v.id) != wanted_district):
			continue
		if not v.is_empty() and sim.town_plan.zone_at(k, pr.get_center()) == "gruen":
			out.gruen += 1
			continue   # Gruenzug, Aussicht, Uferweg des Stadtplans bleiben frei
		var fit := _fit(pr, w, h)
		if fit.size.x == 0 and bool(req.get("allow_no_road", false)):
			fit = _fit(pr, w, h, false)
		if fit.size.x == 0:
			if _fit(pr, w, h, false).size.x > 0:
				out.ohne_strasse.append(str(p.id))
			continue
		maxprice = maxf(maxprice, float(p.price))
		valid.append({"parcel": str(p.id), "rect": [fit.position.x, fit.position.y, w, h], "dist": float(e[0]), "p": p, "v": v, "fringe": fringe, "fit": fit})
	for c in valid:
		c.parts = _score_parts(k, art, req, c, ctx, maxprice)
		c.score = _total(k, art, c.parts)
		c.viertel_text = ("%s %s%s" % [c.v.id, c.v.text, " (am Rand)" if bool(c.fringe) else ""]) if not c.v.is_empty() else "außerhalb der geplanten Viertel"
		c.erase("p")
		c.erase("fit")
	valid.sort_custom(func(a, b): return float(a.score) > float(b.score))
	out.list = valid
	return out


## Standortangebote fuer Unternehmer (Auftrag 8, Abschnitt 9): die besten gueltigen Plaetze der Stadt fuer einen Gebaeudetyp mit Preis,
## Vorteilen, Auflagen (Zone, Geschosse) und Erschliessung – die Firma entscheidet selbst. Gecacht je Stadt/Typ fuer 2 Spielstunden.
var _offer_cache := {}


func offers(k: int, def_id: String, n: int = 3) -> Array:
	var key := "%d|%s" % [k, def_id]
	var now := float(sim.game_min)
	if _offer_cache.has(key) and now - float(_offer_cache[key][0]) < 120.0:
		return _offer_cache[key][1]
	var d: Dictionary = Planning.DEFS.get(def_id, {})
	if d.is_empty():
		return []
	var art := "versorgung" if str(d.use) == "versorgung" else ("gewerbe" if str(d.use) == "gewerbe" else "wohnen")
	var r := rank(k, {"w": int(d.w), "h": int(d.h), "art": art, "floors": int(d.floors[0]), "label": str(d.label)})
	var out: Array = []
	for c in (r.list as Array).slice(0, n):
		var p: Dictionary = sim.parcels.parcel(str(c.parcel))
		var pros: Array = []
		for crit in ["struktur", "nachbarschaft", "bedarf", "landschaft", "kosten"]:
			if float(c.parts.get(crit, 0.0)) >= 0.7:
				pros.append({"struktur": "im passenden Viertel", "nachbarschaft": "ruhige, passende Nachbarschaft", "bedarf": "nah am Ortskern",
					"landschaft": "Wasser in der Nähe", "kosten": "günstig"}[crit])
		var v: Dictionary = sim.town_plan.district_at(k, Vector2i(int(c.rect[0]), int(c.rect[1]))) if sim.town_plan != null else {}
		out.append({"grundstueck": c.parcel, "feld": [int(c.rect[0]), int(c.rect[1])], "preis": int(p.get("price", 0)), "bewertung": c.score,
			"viertel": c.viertel_text, "vorteile": pros, "auflagen": "Zone %s%s" % [p.zone, (", höchstens %d Geschosse" % int(v.geschosse)) if not v.is_empty() and int(v.geschosse) > 0 else ""],
			"erschliessung": "Straße liegt am Grundstück" if float(c.parts.erreichbar) >= 1.0 else "ohne Straße",
			"bauen": "Firma {aktion: {action: \"%s\", typ: \"%s\", grundstueck: \"%s\"}}" % ["gewerbe_bauen" if art == "gewerbe" else "haus_bauen", def_id, c.parcel]})
	if out.is_empty() and not (r.ohne_strasse as Array).is_empty():
		out.append({"hinweis": "Nur Grundstücke ohne Straße (%s) – erst eine Straße bauen (strasse_bauen) oder auf die Erschließung der Stadt warten." % ", ".join((r.ohne_strasse as Array).slice(0, 3))})
	_offer_cache[key] = [now, out]
	return out


## Bereits geordnete Grundstuecksliste (z. B. Kandidaten eines Bautraegers) nach der Standortbewertung sortieren; nicht bewertbare
## (ungueltige) bleiben hinten in alter Reihenfolge.
func order_parcels(k: int, parcels: Array, req: Dictionary, strict: bool = false) -> Array:
	if parcels.is_empty() or _kern(k).x < 0:
		return parcels
	var r := rank(k, req.merged({"zones": ART_ZONES.get(str(req.get("art", "wohnen")), ["wohnen"]) + ["mischgebiet", "gewerbe", "wohnen", "industrie"]}))
	var score := {}
	for c in r.list:
		score[c.parcel] = float(c.score)
	var known: Array = parcels.filter(func(p): return score.has(str(p.id)))
	var rest: Array = parcels.filter(func(p): return not score.has(str(p.id)))
	known.sort_custom(func(a, b): return float(score[str(a.id)]) > float(score[str(b.id)]))
	return known if strict else known + rest   # strict: nur gueltige, bewertete Plaetze (keine verstreuten Haeuser)


## Erneute Pruefung beim tatsaechlichen Auftrag: Grundstueck noch frei (oder vom Halter reserviert), Flaeche noch frei.
func still_valid(parcel_id: String, rect: Array, holder: String = "") -> bool:
	var p: Dictionary = sim.parcels.parcel(parcel_id)
	if p.is_empty():
		return false
	var mine := holder != "" and str(p.get("reservation", {}).get("holder", "")) == holder
	if str(p.state) != "frei" and not (mine and str(p.state) == "reserviert"):
		return false
	return sim.civic._cells_free(Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])))


## Gewaehlten Standort atomar reservieren (ein Grundstueck hat hoechstens einen Reservierer).
func reserve(choice: Dictionary, holder: String) -> bool:
	if not bool(choice.get("ok", false)) or not still_valid(str(choice.parcel), choice.rect):
		return false
	return bool(sim.parcels.reserve(str(choice.parcel), holder).get("ok", false))


# ------------------------------------------------------------------ Bewertung
func _context(k: int, kern: Vector2i) -> Dictionary:
	var homes: Array = []
	var loud: Array = []
	var built: Array = []
	for b in sim.city.buildings:
		var c := Vector2i(int(b.x) + int(b.w) / 2, int(b.y) + int(b.h) / 2)
		if Vector2(c).distance_to(Vector2(kern)) > MAX_DIST + 15.0:
			continue
		built.append(c)
		if str(b.type) in HOME_TYPES:
			homes.append(c)
		elif str(b.type) in LOUD_TYPES:
			loud.append(c)
	return {"kern": kern, "homes": homes, "loud": loud, "built": built}


static func _near(list: Array, c: Vector2i, r: float) -> int:
	var n := 0
	for q in list:
		if Vector2(q).distance_to(Vector2(c)) <= r:
			n += 1
	return n


func _score_parts(k: int, art: String, req: Dictionary, c: Dictionary, ctx: Dictionary, maxprice: float) -> Dictionary:
	var fit: Rect2i = c.fit
	var ctr := fit.get_center()
	var dn := clampf(float(c.dist) / 45.0, 0.0, 1.0)
	var homes := _near(ctx.homes, ctr, 12.0)
	var loud := _near(ctx.loud, ctr, 10.0)
	var built := _near(ctx.built, ctr, 7.0)
	var v: Dictionary = c.v
	var bedarf := 0.0
	var nachbar := 0.0
	match art:
		"wohnen":
			bedarf = 1.0 - dn
			nachbar = 1.0 - minf(1.0, loud / 3.0)
		"versorgung":
			bedarf = minf(1.0, homes / 8.0)
			nachbar = 1.0 - 0.5 * minf(1.0, loud / 4.0)
		"gewerbe":
			bedarf = 1.0 - 0.5 * dn
			nachbar = 1.0 - minf(1.0, homes / 6.0)
		"laerm":
			bedarf = 0.5 + 0.5 * dn
			nachbar = 1.0 - minf(1.0, homes / 4.0)
		"tourismus":
			bedarf = 1.0 - 0.5 * dn
			nachbar = 1.0 - minf(1.0, loud / 2.0)
		_:
			bedarf = 1.0 - dn
			nachbar = 1.0 - 0.5 * minf(1.0, loud / 3.0)
	var struktur := 0.2
	if not v.is_empty():
		struktur = (0.7 if bool(c.get("fringe", false)) else 1.0) if str(v.zone) in ART_DISTRICT.get(art, []) else 0.4
	if built >= 2:
		struktur = minf(1.0, struktur + 0.3)   # Baulücke schließen statt verstreut bauen
	var erreichbar := 1.0 if sim.civic._touches_road(fit) else 0.0
	var kosten := 1.0 - clampf(float(c.p.price) / maxprice, 0.0, 1.0)
	var profil := 0.5
	if not v.is_empty():
		var floors := int(req.get("floors", 1))
		profil = (1.0 if floors <= maxi(1, int(v.geschosse)) else 0.3) * (1.0 if str(c.p.zone) == sim.town_plan.zone_at(k, ctr) else 0.7)
	var wasser := _water_within(ctr, 8)
	var landschaft := 0.5
	if art in ["tourismus", "wohnen"]:
		landschaft = 1.0 if wasser else 0.3
	elif art in ["laerm", "gewerbe"]:
		landschaft = 0.3 if wasser else 0.7   # Ufer freihalten
	return {"bedarf": snappedf(bedarf, 0.01), "nachbarschaft": snappedf(nachbar, 0.01), "struktur": snappedf(struktur, 0.01),
		"erreichbar": erreichbar, "kosten": snappedf(kosten, 0.01), "profil": snappedf(profil, 0.01), "landschaft": landschaft}


func _weights(k: int, art: String) -> Dictionary:
	var wts: Dictionary = (WEIGHTS.get(art, WEIGHTS.oeffentlich) as Dictionary).duplicate()
	var p: Dictionary = sim.town_plan.of(k) if sim.town_plan != null else {}
	if p.is_empty():
		return wts
	match str(p.form):
		"buchtenstadt", "flussstadt":
			wts.landschaft = float(wts.landschaft) * 1.5
		"gartenstadt":
			wts.nachbarschaft = float(wts.nachbarschaft) * 1.3
		"marktort", "hafenort":
			wts.struktur = float(wts.struktur) * 1.3
		"hangstadt":
			wts.erreichbar = float(wts.erreichbar) * 1.3
	return wts


func _total(k: int, art: String, parts: Dictionary) -> float:
	var wts := _weights(k, art)
	var sum := 0.0
	var tot := 0.0
	for key in wts:
		sum += float(wts[key]) * float(parts.get(key, 0.0))
		tot += float(wts[key])
	return snappedf(sum / maxf(0.001, tot), 0.001)


# ------------------------------------------------------------------ Begruendung
func _reason(req: Dictionary, best: Dictionary, alts: Array) -> String:
	var parts: Dictionary = best.parts
	var good: Array = []
	var phr := {"bedarf": {"wohnen": "nah am Ortskern und an Arbeit/Versorgung", "versorgung": "viele Haushalte in Laufweite",
			"laerm": "abseits der Wohnhäuser", "gewerbe": "kurze Wege zur Stadt", "tourismus": "gut erreichbar", "oeffentlich": "zentral gelegen"},
		"nachbarschaft": "passende Nachbarschaft", "struktur": "im passenden Viertel/schließt eine Lücke", "erreichbar": "Straße direkt am Grundstück",
		"kosten": "günstiges Grundstück", "profil": "passt zu Höhe und Charakter des Viertels", "landschaft": "Wasser in der Nähe" if str(req.get("art", "")) in ["tourismus", "wohnen"] else "Ufer bleibt frei"}
	var keys := parts.keys()
	keys.sort_custom(func(a, b): return float(parts[a]) > float(parts[b]))
	for key in keys.slice(0, 3):
		if float(parts[key]) < 0.6:
			continue
		var t = phr[key]
		good.append(str(t.get(str(req.get("art", "oeffentlich")), "")) if t is Dictionary else str(t))
	good = good.filter(func(x): return x != "")
	var txt := "%s auf %s (%s): %s." % [str(req.get("label", "Bau")), best.parcel, best.viertel_text, ", ".join(good) if not good.is_empty() else "einziger gültiger Platz"]
	if not alts.is_empty():
		txt += " Zurückgestellt: %s." % "; ".join(alts.slice(0, 2).map(func(a): return "%s (%s)" % [a.parcel, a.warum]))
	return txt


func _why_worse(c: Dictionary, best: Dictionary) -> String:
	var worst := ""
	var gap := 0.0
	for key in c.parts:
		var g := float(best.parts.get(key, 0.0)) - float(c.parts[key])
		if g > gap:
			gap = g
			worst = key
	if worst == "":
		return "knapp schlechter bewertet"
	return {"bedarf": "geringerer Nutzen am Ort", "nachbarschaft": "unpassende Nachbarschaft", "struktur": "außerhalb des passenden Viertels",
		"erreichbar": "keine Straße am Grundstück", "kosten": "teurer", "profil": "passt schlechter zum Viertel", "landschaft": "schlechtere Lage am Wasser"}[worst]


func _none(k: int, req: Dictionary, ranked: Dictionary) -> Dictionary:
	var lbl := str(req.get("label", "Bau"))
	var size := "%d×%d" % [int(req.get("w", 3)), int(req.get("h", 3))]
	if _kern(k).x < 0:
		return {"ok": false, "msg": "%s: die Stadt ist noch nicht gegründet." % lbl, "naechster_schritt": "gruendung", "ohne_strasse": []}
	var bare: Array = (ranked.ohne_strasse as Array).slice(0, 4)
	if not bare.is_empty():
		return {"ok": false, "ohne_strasse": bare, "naechster_schritt": "erschliessen",
			"msg": "Kein Platz MIT Straßenanschluss für %s (%s Felder); passen würde es auf %s – diese erst erschließen." % [lbl, size, ", ".join(bare)]}
	var v_txt := ""
	if sim.town_plan != null:
		var vs: Array = (sim.town_plan.of(k).get("viertel", []) as Array).filter(func(v): return str(v.zone) in ART_DISTRICT.get(str(req.get("art", "")), []))
		if not vs.is_empty():
			v_txt = " Laut Stadtplan gehört das ins Viertel %s (%s) bei %s – erst erschließen: Amt {aktion: {action: \"viertel_erschliessen\", viertel: \"%s\"}}." % [vs[0].id, vs[0].text, str(vs[0].mitte), vs[0].id]
	return {"ok": false, "ohne_strasse": [], "naechster_schritt": "bauland",
		"msg": "Kein freies städtisches Grundstück für %s (%s Felder, passende Zone).%s" % [lbl, size, v_txt]}


# ------------------------------------------------------------------ Hilfen
func _kern(k: int) -> Vector2i:
	if sim.town_plan != null and sim.town_plan.has(k):
		var kp: Array = sim.town_plan.of(k).kern
		return Vector2i(int(kp[0]), int(kp[1]))
	if sim.town_plan != null:
		return sim.town_plan._kern_of(k)
	return Vector2i(-1, -1)


## Grundflaeche w x h im Grundstueck: alle Zellen frei, (road) eine Strasse direkt am Rand. Mittige Lage bevorzugt nicht noetig –
## die erste passende Lage entlang der Strasse (Eingang zur Strasse).
func _fit(pr: Rect2i, w: int, h: int, road: bool = true) -> Rect2i:
	for y in range(pr.position.y, pr.end.y - h + 1):
		for x in range(pr.position.x, pr.end.x - w + 1):
			var r := Rect2i(x, y, w, h)
			if sim.civic._cells_free(r) and (not road or sim.civic._touches_road(r)):
				return r
	return Rect2i()


func _water_within(c: Vector2i, r: int) -> bool:
	var C: CityData = sim.city
	for dy in range(-r, r + 1, 2):
		for dx in range(-r, r + 1, 2):
			var q := c + Vector2i(dx, dy)
			if C.inside(q) and C.g(q) == CityData.G.WATER:
				return true
	return false
