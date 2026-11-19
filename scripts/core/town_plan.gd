class_name TownPlan
extends RefCounted
## Auftrag 8, Etappe 2 (docs/CITY_PLANNING.md): dauerhaftes Gestaltungsprofil und Viertelplan je Stadt.
##
## Das Profil entsteht einmal je Stadt – bei der Gruendung (Wildnis: Buergeramt fertig) bzw. beim Laden eines Spielstands ohne Profil
## aus der tatsaechlichen Bebauung – und wird gespeichert; es wird beim Laden nicht neu ausgewuerfelt. Es leitet sich aus der Landschaft
## um den Ortskern ab (Meer, Fluss/See, Hang, Ackerland) und vermeidet Grundformen, die eine andere Stadt der Partie schon hat.
## Der Viertelplan ist eine unverbindliche Entwicklungsabsicht (Status "entwurf"): er sperrt keine Flaeche, sondern bestimmt Zone,
## Grundstuecksgroesse, Hoehen und Bevorzugung bei der Standortwahl. Harte Reservierungen laufen weiter ueber Parcels.reserve.

const VERSION := 2   # 2: Grundstuecke gross genug fuer die Bebauungsgrenzen (Wohnen 45 %)
const RADIUS := 30   # Landschaftsanalyse um den Kern

## Grundformen. block = Grundstuecksgroesse (Felder) fuer neues Bauland; hoehen = hoechste Geschosszahl je Ring (Kern, Mitte, Rand);
## freiraum = Art der Freiflaechen; wirtschaft = raeumliche Schwerpunkte (verbieten nichts).
const FORMS := {
	"hafenort": {"label": "Hafenort", "text": "kompakter Kern am Hafen, kurze Geschäftsstraße, Gewerbehöfe an eigener Güterzufahrt",
		"block": [8, 6], "hoehen": [3, 2, 1], "freiraum": "kai", "wirtschaft": ["hafen", "handel", "logistik"]},
	"buchtenstadt": {"label": "Buchtenstadt", "text": "Bebauung folgt der Bucht, Promenade und kleine Plätze am Ufer, Hotels mit Wasserblick",
		"block": [8, 7], "hoehen": [3, 2, 1], "freiraum": "promenade", "wirtschaft": ["tourismus", "gastronomie", "handel"]},
	"gartenstadt": {"label": "Gartenstadt", "text": "kleine Nachbarschaften mit Grünzügen dazwischen, Gärten, örtliche Versorgung",
		"block": [9, 8], "hoehen": [2, 2, 1], "freiraum": "gruenzug", "wirtschaft": ["handwerk", "versorgung", "landwirtschaft"]},
	"hangstadt": {"label": "Hangstadt", "text": "Baugruppen auf den flachen Lagen am Hang, Aussichtspunkte, Gewerbe im Tal",
		"block": [8, 6], "hoehen": [3, 2, 2], "freiraum": "aussicht", "wirtschaft": ["rohstoffe", "handwerk", "tourismus"]},
	"flussstadt": {"label": "Flussstadt", "text": "Uferquartiere beiderseits des Wassers, Brückenstandorte, Zugänge zum Ufer",
		"block": [8, 6], "hoehen": [3, 2, 1], "freiraum": "uferweg", "wirtschaft": ["handel", "handwerk", "logistik"]},
	"marktort": {"label": "Marktort", "text": "Ortskern um den Marktplatz, Hauptstraße mit Läden, Wohnstraßen ringsum",
		"block": [8, 6], "hoehen": [4, 2, 1], "freiraum": "platz", "wirtschaft": ["handel", "versorgung", "handwerk"]},
}
## Ortscharakter vom Kartenstart -> bevorzugte Grundform (Bonus bei der Wahl)
const FORM_OF_CHARACTER := {"Fischerdorf": "hafenort", "Hafenstadt": "hafenort", "Kurort": "buchtenstadt", "Bauerndorf": "gartenstadt",
	"Marktflecken": "marktort", "Handwerkerort": "marktort"}
## Stil kommunaler Bauten je Grundform (Municipal: pub_<typ>_<variante>_<stil>)
const STYLE_OF_FORM := {"hafenort": "backstein", "buchtenstadt": "modern", "gartenstadt": "gruen", "hangstadt": "industrie",
	"flussstadt": "backstein", "marktort": "backstein"}
const SUFFIXES := ["", "s1", "s2", "s3", "s4", "s5"]   # Material-/Farbvarianten der Wohnhaeuser
const HOUSE_FORMS := 8                                  # house0..house7: Bauformen (Silhouette)

var sim
var towns := {}   # str(k) -> Profil (siehe derive)
var _expansion_cache := {}
var _repair_cache := {}


func setup(simulation) -> void:
	sim = simulation


func of(k: int) -> Dictionary:
	return towns.get(str(k), {})


func has(k: int) -> bool:
	return towns.has(str(k))


## Profil anlegen, falls die Stadt gegruendet ist und noch keins hat. reason: "gruendung" | "bestand" | "start".
func ensure(k: int, reason: String = "bestand") -> Dictionary:
	if has(k):
		return of(k)
	var kern := _kern_of(k)
	if kern.x < 0:
		return {}
	var p := derive(k, kern)
	p["geschichte"] = [{"tag": _day(), "text": {"gruendung": "Bei der Gründung festgelegt", "start": "Beim Kartenstart festgelegt",
		"bestand": "Aus der bestehenden Bebauung abgeleitet"}.get(reason, reason) + ": %s – %s." % [p.label, FORMS[p.form].text]}]
	towns[str(k)] = p
	claim_land(k)
	p["land"] = true
	if sim.has_method("log_event"):
		sim.log_event("Stadtplan %s: %s (%s)." % [_name(k), p.label, FORMS[p.form].text], "info")
	return p


## Freies oeffentliches Land, das naeher am Kern von k liegt als am Kern jeder anderen gegruendeten Stadt (und hoechstens CLAIM_R
## entfernt), geht an die Stadt k (Partie 18.11.: Liorufer wurde 27 Felder neben Birkenklippe gegruendet – alles Land ringsum gehoerte
## Birkenklippe, der Buergermeister fand kein einziges eigenes Grundstueck). Nur freie Flaechen; Bebautes, Reserviertes, Privates bleibt.
const CLAIM_R := 45.0


func claim_land(k: int) -> int:
	var kern := _kern_of(k)
	if kern.x < 0 or sim.towns == null or sim.towns.count() < 2:
		return 0
	var others: Array = []
	for j in sim.towns.count():
		if j != k and _founded(j):
			var o := _kern_of(j)
			if o.x >= 0:
				others.append(Vector2(o))
	var mine := Towns.owner_of(k)
	var n := 0
	for p in sim.parcels.items.values():
		if str(p.state) != "frei" or not Towns.is_public(str(p.owner)) or str(p.owner) == mine:
			continue
		var c := Vector2(int(p.rect[0]) + int(p.rect[2]) / 2.0, int(p.rect[1]) + int(p.rect[3]) / 2.0)
		var d := c.distance_to(Vector2(kern))
		if d > CLAIM_R or others.any(func(o): return c.distance_to(o) <= d):
			continue
		p.owner = mine
		sim.parcels.touch(str(p.id))
		n += 1
	return n


## Alle gegruendeten Staedte ohne Profil nachziehen (Kartenstart und Laden alter Spielstaende).
func ensure_all(reason: String = "bestand") -> void:
	if sim.towns == null:
		return
	for k in sim.towns.count():
		if _founded(k):
			ensure(k, reason)
			revise_districts(k)
			if not bool(of(k).get("land", false)):   # Profile von vor der Landzuteilung (18.11.): einmal nachholen
				var n := claim_land(k)
				of(k)["land"] = true
				if n > 0 and sim.has_method("log_event"):
					sim.log_event("%s übernimmt %d freie städtische Grundstücke an ihrem Kern." % [_name(k), n], "info")


## Profil aus Landschaft und Nachbarstaedten ableiten (deterministisch aus Seed, Stadtnummer und Kern).
func derive(k: int, kern: Vector2i) -> Dictionary:
	var L := landscape(kern)
	var taken := {}
	for key in towns:
		if int(key) != k:
			taken[str(towns[key].form)] = int(taken.get(str(towns[key].form), 0)) + 1
	var ch := str(sim.towns.get_t(k).get("charakter", "")) if sim.towns != null else ""
	var score := {
		"hafenort": 2.2 * float(L.meer) + (0.6 if L.meer > 0.15 else 0.0),
		"buchtenstadt": 2.5 * float(L.bucht) + 0.8 * float(L.meer),
		"gartenstadt": 1.0 + 0.8 * float(L.acker) - 1.2 * float(L.meer),
		"hangstadt": 6.0 * float(L.hang),
		"flussstadt": 4.0 * float(L.fluss),
		"marktort": 1.1 - 0.5 * float(L.hang),
	}
	if FORM_OF_CHARACTER.has(ch):
		score[FORM_OF_CHARACTER[ch]] = float(score[FORM_OF_CHARACTER[ch]]) + 0.7
	var best := ""
	var best_s := -INF
	for f in score:
		var s: float = float(score[f]) - 3.0 * float(taken.get(f, 0)) + float(absi(hash([sim.city.seed_value, k, f])) % 100) / 200.0
		if s > best_s:
			best_s = s
			best = f
	# Der Gruender legt die Stadtform vor dem Bau des Buergeramts fest.
	if sim.eko != null:
		var founder_form := str(sim.eko.conflict.strategy_for_town(k).get("form", ""))
		if FORMS.has(founder_form):
			best = founder_form
	var F: Dictionary = FORMS[best]
	var d := {"v": VERSION, "town": k, "form": best, "label": F.label, "kern": [kern.x, kern.y], "landschaft": L,
		"wasser_richtung": L.richtung, "block": F.block, "hoehen": F.hoehen, "freiraum": F.freiraum, "wirtschaft": F.wirtschaft,
		"stil": STYLE_OF_FORM[best], "palette": _palette(k), "hausformen": _house_forms(k, best)}
	d["achse"] = _axis(kern, L)
	d["viertel"] = _districts(d)
	return d


## Landschaft um den Kern: Anteile Meer/Fluss-See/Hang/Acker (0..1), Richtung zum Meer, Buchtform (Wasser auf mehreren Seiten).
func landscape(kern: Vector2i) -> Dictionary:
	var C: CityData = sim.city
	var n := 0
	var meer := 0
	var fluss := 0
	var hang := 0
	var acker := 0
	var dir := Vector2.ZERO
	var sides := [0, 0, 0, 0]   # Wasser je Himmelsrichtung (O, S, W, N)
	for dy in range(-RADIUS, RADIUS + 1, 2):
		for dx in range(-RADIUS, RADIUS + 1, 2):
			var q := kern + Vector2i(dx, dy)
			if not C.inside(q):
				continue
			n += 1
			var g := C.g(q)
			if g == CityData.G.WATER:
				if _wide_water(q):
					meer += 1
					dir += Vector2(dx, dy)
				else:
					fluss += 1
				var ang := fposmod(atan2(float(dy), float(dx)), TAU)
				sides[int(round(ang / (PI / 2.0))) % 4] += 1
			elif not C.height.is_empty() and C.height[C.idx(q)] > 0:
				hang += 1
			elif g in [CityData.G.FIELD, CityData.G.CROP]:
				acker += 1
	n = maxi(1, n)
	var wet_sides := sides.filter(func(v): return v > n / 40).size()
	var r := Vector2i.ZERO
	if dir.length() > 0.0:
		var u := dir.normalized()
		r = Vector2i(int(round(u.x)), int(round(u.y)))
	return {"meer": snappedf(float(meer) / n, 0.01), "fluss": snappedf(float(fluss) / n, 0.01), "hang": snappedf(float(hang) / n, 0.01),
		"acker": snappedf(float(acker) / n, 0.01), "bucht": 1.0 if wet_sides >= 2 and meer > n / 12 else 0.0, "richtung": [r.x, r.y]}


## Breites Wasser (Meer, grosser See) gegenueber Fluss: Anteil Wasser im 7x7-Fenster.
func _wide_water(q: Vector2i) -> bool:
	var C: CityData = sim.city
	var w := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var p := q + Vector2i(dx, dy)
			if C.inside(p) and C.g(p) == CityData.G.WATER:
				w += 1
	return w >= 30


## Hauptachse: entlang der Kueste (quer zur Wasserrichtung), sonst Richtung Grosslager/Kartenmitte.
func _axis(kern: Vector2i, L: Dictionary) -> Array:
	var r := Vector2i(int(L.richtung[0]), int(L.richtung[1]))
	if r != Vector2i.ZERO:
		return [-r.y, r.x] if absi(r.x) + absi(r.y) > 0 else [1, 0]
	var to := Vector2(sim.city.size / 2, sim.city.size / 2)
	if sim.hub != null and sim.hub.enabled:
		var hb: Dictionary = sim.city.building(int(sim.hub.loc))
		if not hb.is_empty():
			to = Vector2(int(hb.x), int(hb.y))
	var u := (to - Vector2(kern)).normalized()
	return [int(round(u.x)), int(round(u.y))] if u.length() > 0.0 else [1, 0]


## Viertelplan je Grundform: Rolle, Zone, Mitte, Radius, hoechste Geschosszahl. Lage relativ zu Kern, Wasser (w) und Achse (a).
func _districts(d: Dictionary) -> Array:
	var kern := Vector2i(int(d.kern[0]), int(d.kern[1]))
	var w := Vector2i(int(d.wasser_richtung[0]), int(d.wasser_richtung[1]))
	var a := Vector2i(int(d.achse[0]), int(d.achse[1]))
	if w == Vector2i.ZERO:
		w = Vector2i(-a.y, a.x)   # ohne Wasser: "vorne" quer zur Achse
	var h: Array = d.hoehen
	var spec: Array = []   # [rolle, zone, versatz, radius, geschosse, text]
	match str(d.form):
		"hafenort":
			spec = [["kern", "mischgebiet", Vector2i.ZERO, 8, h[0], "Geschäftsstraße am alten Hafen"],
				["hafen_gewerbe", "gewerbe", w * 6 + a * 13, 7, h[1], "Lager- und Gewerbehöfe an der Güterzufahrt"],
				["wohnen_hang", "wohnen", -w * 13, 9, h[1], "Wohnstraßen hinter dem Kern"],
				["wohnen_kueste", "wohnen", -a * 15, 8, h[2], "Wohnen an der Küste, abseits vom Hafen"]]
		"buchtenstadt":
			spec = [["kern", "mischgebiet", Vector2i.ZERO, 7, h[0], "Platz an der Promenade"],
				["ufer_ost", "mischgebiet", w * 3 + a * 13, 6, h[1], "Hotels und Gastronomie mit Wasserblick"],
				["ufer_west", "mischgebiet", w * 3 - a * 13, 6, h[1], "Promenade mit kleinen Plätzen"],
				["wohnen", "wohnen", -w * 14, 10, h[2], "Wohnen hinter der Uferzeile"],
				["gewerbe", "gewerbe", -w * 24 + a * 10, 6, h[2], "Gewerbe abseits des Ufers, eigene Zufahrt"]]
		"gartenstadt":
			spec = [["kern", "mischgebiet", Vector2i.ZERO, 6, h[0], "kleiner Versorgungsplatz"],
				["nachbarschaft_1", "wohnen", a * 16 + w * 6, 7, h[1], "Nachbarschaft mit Gärten"],
				["nachbarschaft_2", "wohnen", -a * 16 + w * 6, 7, h[1], "Nachbarschaft mit Gärten"],
				["nachbarschaft_3", "wohnen", -w * 17, 7, h[2], "Nachbarschaft am Ortsrand"],
				["gruenzug", "gruen", -w * 8 + a * 8, 4, 0, "Grünverbindung zwischen den Nachbarschaften"],
				["handwerk", "gewerbe", a * 26, 6, h[2], "Handwerkerhöfe am Ortsrand"]]
		"hangstadt":
			spec = [["kern", "mischgebiet", Vector2i.ZERO, 7, h[0], "Ortskern auf der flachen Stufe"],
				["terrasse_1", "wohnen", a * 12, 6, h[1], "Baugruppe am Hang"],
				["terrasse_2", "wohnen", -a * 12, 6, h[1], "Baugruppe am Hang"],
				["aussicht", "gruen", -w * 10, 3, 0, "Aussichtspunkt"],
				["tal_gewerbe", "gewerbe", w * 14, 7, h[2], "Gewerbe im Tal an der Zufahrt"]]
		"flussstadt":
			spec = [["kern", "mischgebiet", Vector2i.ZERO, 7, h[0], "Marktplatz am Ufer"],
				["ufer_1", "wohnen", a * 14, 8, h[1], "Uferquartier"],
				["ufer_2", "wohnen", -a * 14, 8, h[1], "Uferquartier am anderen Ende"],
				["uferweg", "gruen", w * 4, 3, 0, "Zugang zum Wasser"],
				["gewerbe", "gewerbe", -w * 18, 7, h[2], "Gewerbe an der Landstraße"]]
		_:
			spec = [["kern", "mischgebiet", Vector2i.ZERO, 7, h[0], "Marktplatz und Hauptstraße"],
				["wohnen_nord", "wohnen", w * 13, 8, h[1], "Wohnstraßen am Kern"],
				["wohnen_sued", "wohnen", -w * 13, 9, h[1], "Wohnstraßen am Kern"],
				["wohnen_rand", "wohnen", -a * 17, 8, h[2], "Wohnen am Ortsrand"],
				["gewerbe", "gewerbe", a * 20, 7, h[2], "Gewerbe an der Ausfallstraße"]]
	var out: Array = []
	var i := 1
	for s in spec:
		var c := _on_land(kern + s[2], kern, int(d.town))
		out.append({"id": "V%d" % i, "rolle": s[0], "zone": s[1], "mitte": [c.x, c.y], "radius": s[3], "geschosse": s[4],
			"text": s[5], "status": "entwurf"})
		i += 1
	return out


## Viertelmitte auf freies Land legen: zuerst denselben Abstand in gedrehter Richtung (bis 90 Grad), dann naeher am Kern.
## Nicht im Wasser oder Berg und nicht naeher an einer anderen Stadt als am eigenen Kern (Partie 18.11.: Nachbarorte 27 Felder entfernt).
func _on_land(c: Vector2i, kern: Vector2i, k: int = -1) -> Vector2i:
	var off := Vector2(c - kern)
	if off == Vector2.ZERO:
		return kern
	for f in [1.0, 0.8, 0.6, 0.45]:
		for deg in [0, 30, -30, 60, -60, 90, -90]:
			var p := kern + Vector2i((off * f).rotated(deg_to_rad(deg)).round())
			if _good_spot(p, kern, k):
				return p
	return kern


func _good_spot(p: Vector2i, kern: Vector2i, k: int, min_free: float = 0.55) -> bool:
	var C: CityData = sim.city
	for q in [p, p + Vector2i(2, 0), p + Vector2i(-2, 0), p + Vector2i(0, 2), p + Vector2i(0, -2)]:
		if not C.inside(q) or C.g(q) == CityData.G.WATER or (not C.height.is_empty() and C.height[C.idx(q)] > 0):
			return false
	if free_share(p, 5) < min_free:
		return false   # Viertel braucht freies Land (18.11.: Gewerbeviertel lag mitten in der Bebauung)
	var own := Vector2(p).distance_to(Vector2(kern))
	if sim.towns != null:
		for j in sim.towns.count():
			if j == k:
				continue
			var o := _kern_of(j)
			if o.x >= 0 and Vector2(p).distance_to(Vector2(o)) < own:
				return false
	return true


## Anteil freier, bebaubarer Felder (kein Gebaeude, keine Strasse, Land, flach) im Umkreis r.
func free_share(c: Vector2i, r: int) -> float:
	var C: CityData = sim.city
	var n := 0
	var free := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dy)
			n += 1
			if C.inside(q) and C.building_at[C.idx(q)] < 0 and C.g(q) not in [CityData.G.ROAD, CityData.G.WATER, CityData.G.RAIL, CityData.G.QUAY] and (C.height.is_empty() or C.height[C.idx(q)] == 0):
				var pc: Dictionary = sim.parcels.at_cell(q)   # bebaubares freies Grundstueck (nicht Korridor/Gruen/vergeben)
				if not pc.is_empty() and str(pc.state) == "frei" and sim.parcels.is_buildable(pc):
					free += 1
	return float(free) / float(maxi(1, n))


## Auch jenseits der zuerst vermessenen Grundstuecke soll eine Stadt wachsen koennen.
## Die KI bekommt echte, gepruefte Standorte und waehlt Lage, Nutzung und Charakter selbst.
func expansion_sites(k: int) -> Array:
	var p := of(k)
	if p.is_empty() or (p.viertel as Array).size() >= 24 or int(p.get("last_expansion_day", -1)) == _day():
		return []
	var M = sim.towns.mayor(k)
	if M != null and M.projects.values().any(func(prj): return prj.has("road_plan") and str(prj.status) not in ["fertig", "abgelehnt", "abgebrochen"]):
		return []
	var key := "%d:%d:%d:%d" % [k, _day(), sim.city.road_count, (p.viertel as Array).size()]
	if _expansion_cache.has(key):
		return _expansion_cache[key]
	if _expansion_cache.size() > 32:
		_expansion_cache.clear()
	var kern := Vector2i(int(p.kern[0]), int(p.kern[1]))
	var sites: Array = []
	for rad in [28, 40, 52, 64]:
		for deg in range(0, 360, 45):
			var at := kern + Vector2i((Vector2.RIGHT.rotated(deg_to_rad(deg)) * rad).round())
			if not _expansion_spot_ok(k, at, kern, p):
				continue
			var free := _raw_free_share(at, 5, k)
			var roads := 0
			for dy in range(-10, 11, 5):
				for dx in range(-10, 11, 5):
					if sim.city.is_road(at + Vector2i(dx, dy)):
						roads += 1
			sites.append({"feld": [at.x, at.y], "punkte": int(free * 100.0) + roads * 3 - rad / 4,
				"grund": "%d %% freie Fläche, %d Straßenpunkte in der Nähe" % [int(free * 100.0), roads]})
	sites.sort_custom(func(a, b): return int(a.punkte) > int(b.punkte))
	_expansion_cache[key] = sites.slice(0, 6)
	return _expansion_cache[key]


func plan_district(k: int, a: Dictionary) -> Dictionary:
	var p := of(k)
	var raw = a.get("mitte", [])
	if not (raw is Array) or (raw as Array).size() < 2:
		return {"ok": false, "msg": "Wähle mitte: [x, y] aus stadtplan_erweiterung."}
	var center := Vector2i(int(raw[0]), int(raw[1]))
	var zone := str(a.get("zone", "wohnen"))
	if zone not in ["wohnen", "mischgebiet", "gewerbe", "gruen"]:
		return {"ok": false, "msg": "zone: wohnen | mischgebiet | gewerbe | gruen."}
	if not expansion_sites(k).any(func(s): return int(s.feld[0]) == center.x and int(s.feld[1]) == center.y):
		return {"ok": false, "msg": "Dieser Standort ist nicht mehr frei. Wähle einen der aktuellen Vorschläge aus stadtplan_erweiterung."}
	var n: int = (p.viertel as Array).size() + 1
	var text := str(a.get("name", "Neues Viertel")).strip_edges().left(60)
	var v := {"id": "V%d" % n, "rolle": "erweiterung", "zone": zone, "mitte": [center.x, center.y], "radius": 7 if zone != "gruen" else 5,
		"geschosse": 0 if zone == "gruen" else int(p.hoehen[2]), "text": text if text != "" else "Neues Viertel", "status": "erschlossen" if zone == "gruen" else "entwurf"}
	p.viertel.append(v)
	if zone != "gruen" and (street_plan(k, str(v.id)).cells as Array).is_empty():
		p.viertel.pop_back()
		var key := "%d:%d:%d:%d" % [k, _day(), sim.city.road_count, (p.viertel as Array).size()]
		if _expansion_cache.has(key):
			_expansion_cache[key] = (_expansion_cache[key] as Array).filter(func(site): return int(site.feld[0]) != center.x or int(site.feld[1]) != center.y)
		return {"ok": false, "msg": "Von diesem Standort ist derzeit kein zusammenhängender Straßenanschluss möglich. Wähle einen anderen freien Standort."}
	p["last_expansion_day"] = _day()
	_expansion_cache.clear()
	revise(k, "Bürgermeister plant %s (%s) bei %s: %s." % [v.id, zone, str(v.mitte), str(a.get("reason", ""))])
	return {"ok": true, "msg": "%s bei %s im Stadtplan: %s. %s" % [v.id, str(v.mitte), v.text,
		"Als Nächstes viertel_erschliessen beauftragen." if zone != "gruen" else "Grünzug bleibt frei; Parks können auf angrenzenden öffentlichen Grundstücken entstehen."], "viertel": v.id}


func _expansion_spot_ok(k: int, at: Vector2i, kern: Vector2i, p: Dictionary) -> bool:
	if not sim.city.inside(at) or _raw_free_share(at, 5, k) < 0.65:
		return false
	if (p.viertel as Array).any(func(v): return Vector2(at).distance_to(Vector2(int(v.mitte[0]), int(v.mitte[1]))) < float(int(v.radius) + 9)):
		return false
	var mine := Vector2(at).distance_to(Vector2(kern))
	for j in sim.towns.count():
		if j != k:
			var other := _kern_of(j)
			if other.x >= 0 and Vector2(at).distance_to(Vector2(other)) <= mine:
				return false
	return true


func _raw_free_share(at: Vector2i, r: int, k: int = -1) -> float:
	var C: CityData = sim.city
	var free := 0
	var total := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := at + Vector2i(dx, dy)
			total += 1
			if not C.inside(q):
				continue
			var parcel: Dictionary = sim.parcels.at_cell(q)
			if (C.building_at[C.idx(q)] < 0 and C.g(q) not in [CityData.G.ROAD, CityData.G.WATER, CityData.G.RAIL, CityData.G.QUAY, CityData.G.RUNWAY]
					and (C.height.is_empty() or C.height[C.idx(q)] == 0)
					and (parcel.is_empty() or (Towns.is_public(str(parcel.owner)) and (k < 0 or Towns.town_of_owner(str(parcel.owner)) == k)))):
				free += 1
	return float(free) / float(maxi(1, total))


## Planrevision: Entwurfs-Viertel ohne freies Land werden verlegt (begruendet in der Entwicklungsgeschichte). Beschlossene, in
## Erschliessung befindliche oder erschlossene Viertel bleiben.
func revise_districts(k: int) -> int:
	var p := of(k)
	if p.is_empty():
		return 0
	var kern := Vector2i(int(p.kern[0]), int(p.kern[1]))
	var n := 0
	for v in p.viertel:
		var c := Vector2i(int(v.mitte[0]), int(v.mitte[1]))
		var idx: int = (p.viertel as Array).find(v)
		var overlap: bool = (p.viertel as Array).slice(0, idx).any(func(o): return Vector2(c).distance_to(Vector2(int(o.mitte[0]), int(o.mitte[1]))) < 0.7 * float(int(o.radius) + int(v.radius)))
		if str(v.status) != "entwurf" or str(v.rolle) == "kern" or (free_share(c, 5) >= 0.4 and not overlap):
			continue
		var nc := _on_land(c + (c - kern) / 2, kern, k)
		if nc != kern and (p.viertel as Array).any(func(o): return o != v and Vector2(nc).distance_to(Vector2(int(o.mitte[0]), int(o.mitte[1]))) < float(int(o.radius) + int(v.radius))):
			nc = kern
		if nc == kern or nc == c:   # in der Naehe nichts frei: Ring um den Kern absuchen, moeglichst in alter Richtung
			var best := -INF
			var dir := Vector2(c - kern).normalized() if c != kern else Vector2.RIGHT
			for rad in range(12, 40, 4):
				for deg in range(0, 360, 20):
					var u := Vector2.RIGHT.rotated(deg_to_rad(deg))
					var q := kern + Vector2i((u * rad).round())
					if not _good_spot(q, kern, k, 0.35) or (p.viertel as Array).any(func(o): return o != v and Vector2(q).distance_to(Vector2(int(o.mitte[0]), int(o.mitte[1]))) < float(int(o.radius) + int(v.radius))):
						continue   # nicht auf ein anderes Viertel (18.11.: V3 und V4 landeten auf demselben Platz)
					var sc := free_share(q, 5) + 0.5 * u.dot(dir) - 0.01 * rad
					if sc > best:
						best = sc
						nc = q
		if nc == kern or nc == c:
			continue
		v.mitte = [nc.x, nc.y]
		revise(k, "Viertel %s (%s) verlegt von %s nach %s: %s." % [v.id, v.text, str([c.x, c.y]), str([nc.x, nc.y]), "lag auf einem anderen Viertel" if overlap else "am alten Ort kaum noch freies Land"])
		n += 1
	return n


## Material-/Farbpalette: 3 von 6 Varianten, je Stadt anders als die bisherigen Staedte (soweit moeglich).
func _palette(k: int) -> Array:
	var used := {}
	for key in towns:
		if int(key) != k:
			used[str(towns[key].palette)] = true
	var order := SUFFIXES.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash([sim.city.seed_value, k, "palette"]))
	for tries in 12:
		for i in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = order[i]
			order[i] = order[j]
			order[j] = t
		var pick: Array = order.slice(0, 3)
		pick.sort()
		if not used.has(str(pick)):
			return pick
	return order.slice(0, 3)


## Bauformen der Wohnhaeuser (Silhouette): 5 von 8, je Grundform verschoben, damit Staedte unterschiedliche Familien haben.
func _house_forms(k: int, form: String) -> Array:
	var start := (FORMS.keys().find(form) * 3 + absi(hash([sim.city.seed_value, k])) % 2) % HOUSE_FORMS
	var out: Array = []
	for i in 5:
		out.append((start + i) % HOUSE_FORMS)
	return out


## Viertel an einer Zelle (naechstes Viertel, dessen Radius die Zelle einschliesst), {} = ausserhalb des Plans.
func district_at(k: int, cell: Vector2i) -> Dictionary:
	var best := {}
	var best_d := INF
	for v in of(k).get("viertel", []):
		var d := Vector2(cell).distance_to(Vector2(int(v.mitte[0]), int(v.mitte[1])))
		if d <= float(v.radius) + 2.0 and d / float(v.radius) < best_d:
			best_d = d / float(v.radius)
			best = v
	return best


## Zone fuer neues Bauland an einer Zelle: Zone des Viertels; ausserhalb des Plans Wohnen. "gruen" = nicht bebauen.
func zone_at(k: int, cell: Vector2i) -> String:
	var v := district_at(k, cell)
	return str(v.zone) if not v.is_empty() else "wohnen"


## Grundstuecksgroesse fuer neues Bauland.
func plot_size(k: int) -> Vector2i:
	var p := of(k)
	return Vector2i(int(p.block[0]), int(p.block[1])) if not p.is_empty() else Vector2i(6, 6)


## Hausvariante aus Palette und Bauformen der Stadt: Teilmenge von variants ({} = keine Einschraenkung moeglich).
func variant_pool(k: int, type: String, variants: Array) -> Array:
	var p := of(k)
	if p.is_empty():
		return variants
	var pal: Array = p.palette
	var forms: Array = p.hausformen
	var pool: Array = variants.filter(func(v):
		var s := str(v)
		var suf := _suffix(s)
		if suf not in pal:
			return false
		if type == "house":
			var digit := s.substr(5, 1)
			return digit.is_valid_int() and int(digit) in forms
		return true)
	return pool if not pool.is_empty() else variants


static func _suffix(sp: String) -> String:
	var i := sp.rfind("s")
	return sp.substr(i) if i > 0 and sp.substr(i + 1).is_valid_int() else ""


## Kurzfassung fuer Beobachtungen der KI und die Oberflaeche.
func brief(k: int) -> Dictionary:
	var p := of(k)
	if p.is_empty():
		return {}
	return {"grundform": p.label, "leitbild": FORMS[p.form].text, "freiraum": p.freiraum, "wirtschaft": p.wirtschaft,
		"grundstuecke": "%dx%d" % [int(p.block[0]), int(p.block[1])], "hoehen_kern_mitte_rand": p.hoehen,
		"viertel": (p.viertel as Array).map(func(v): return {"id": v.id, "rolle": v.rolle, "zone": v.zone, "mitte": v.mitte,
			"geschosse_max": v.geschosse, "zweck": v.text, "status": v.status}),
		"letzte_standortwahl": (p.get("entscheidungen", []) as Array).slice(-3).map(func(e): return str(e.begruendung).left(220))}


## Strassennetz eines Viertels nach Grundform (Auftrag 8, Abschnitt 10): Hauptstrasse entlang der Achse, Querstrassen im Abstand
## der Bloecke; Gartenstadt als Ring um einen Gruenplatz, Buchtenstadt als Uferstrasse mit Stichstrasse zum Land, Hangstadt nur auf
## den flachen Lagen. Dazu die Anbindung an die naechste bestehende Strasse. Nur freie Felder (kein Gebaeude, Wasser, Berg, Gleis).
## Ergebnis {cells: Array[Vector2i] (neue Strassenfelder), platz: Vector2i (-1 = keiner), text}.
const STREET_CONNECT_MAX := 70


func street_plan(k: int, vid: String) -> Dictionary:
	var p := of(k)
	var v := {}
	for x in p.get("viertel", []):
		if str(x.id) == vid:
			v = x
	if v.is_empty() or str(v.zone) == "gruen":
		return {"cells": [], "platz": Vector2i(-1, -1), "text": ""}
	var c := Vector2i(int(v.mitte[0]), int(v.mitte[1]))
	var r := int(v.radius)
	var a := _cardinal(Vector2i(int(p.achse[0]), int(p.achse[1])))
	var q := Vector2i(-a.y, a.x)   # quer zur Achse
	var block := int(p.block[1]) * 2 + 1   # Grundstueck beidseits der Strasse
	var want: Array = []
	var platz := Vector2i(-1, -1)
	var text := ""
	var form := str(p.form)
	if form in ["gartenstadt", "buchtenstadt", "hangstadt"] and str(v.zone) == "gewerbe":
		form = "marktort"   # Gewerbe: Raster mit Zufahrten statt Ring/Uferstrasse/Hangstrasse
	match form:
		"gartenstadt":
			var h := maxi(3, r - 1)
			for i in range(-h, h + 1):
				want += [c + a * i + q * h, c + a * i - q * h, c + q * i + a * h, c + q * i - a * h]
			text = "Ringstraße um einen Grünplatz"
		"buchtenstadt":
			for i in range(-r, r + 1):
				want.append(c + a * i)
			for i in range(1, r + 1):
				want.append(c - q * i)
			text = "Uferstraße mit Stichstraße ins Land"
		"hangstadt":
			for i in range(-r, r + 1):
				want.append(c + a * i)
			for i in range(1, mini(r, block) + 1):
				want.append(c + q * i)
			text = "Straße auf der flachen Stufe am Hang"
		_:
			for i in range(-r, r + 1):
				want.append(c + a * i)
			var off := -r + (r % block)
			while off <= r:
				if off != 0:
					for i in range(-r / 2, r / 2 + 1):
						want.append(c + a * off + q * i)
				off += block
			text = "Hauptstraße mit Querstraßen im Abstand von %d Feldern" % block
	if str(v.rolle) == "kern" and str(p.freiraum) in ["platz", "kai", "promenade"]:
		platz = c + q * 2
		text += ", Platz mit Brunnen am Kern"
	var C: CityData = sim.city
	if platz.x >= 0:
		for py in 2:
			for px in 2:
				var at := platz + Vector2i(px, py)
				if not C.inside(at) or C.building_at[C.idx(at)] >= 0 or C.is_road(at):
					platz = Vector2i(-1, -1)
					break
	var seen := {}
	for w in want:
		if seen.has(w) or not _road_ok(w, k) or (platz.x >= 0 and Rect2i(platz, Vector2i(2, 2)).has_point(w)):
			continue
		seen[w] = true
	if seen.is_empty():
		return {"cells": [], "platz": Vector2i(-1, -1), "text": text}
	# Ein vorhandenes Straßenfeld am Rathaus ist die Wurzel. Nur mit ihm verbundene Straßen
	# zählen als Netz; alte einzelne Rauten werden bei der nächsten Erschließung angeschlossen.
	var hall: Dictionary = C.building(int(C.towns[k].get("town_hall", -1)))
	var root := Vector2i(-1, -1)
	if not hall.is_empty() and C.is_road(hall.road):
		root = hall.road
	else:
		var best := INF
		for dy in range(-STREET_CONNECT_MAX, STREET_CONNECT_MAX + 1):
			for dx in range(-STREET_CONNECT_MAX, STREET_CONNECT_MAX + 1):
				var w := c + Vector2i(dx, dy)
				var dist := absi(dx) + absi(dy)
				if dist < best and C.is_road(w):
					best = dist
					root = w
	if root.x < 0:
		return {"cells": [], "platz": Vector2i(-1, -1), "text": "Noch keine bestehende Straße als Anschluss vorhanden"}
	var network := _connected_roads(root, c)
	var pending := seen.duplicate()
	var cells: Array = []
	var accepted := {}
	var skipped := 0
	while not pending.is_empty():
		var component: Array = [pending.keys()[0]]
		pending.erase(component[0])
		var cursor := 0
		while cursor < component.size():
			var here: Vector2i = component[cursor]
			cursor += 1
			for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var next: Vector2i = here + d
				if pending.has(next):
					pending.erase(next)
					component.append(next)
		var connected := component.any(func(w): return network.has(w))
		var link: Array = [] if connected else _road_connector(component, network, c, platz, k)
		if not connected and link.is_empty():
			skipped += component.size()
			continue
		for w in component + link:
			network[w] = true
			if not C.is_road(w) and not accepted.has(w):
				accepted[w] = true
				cells.append(w)
	if skipped > 0:
		text += ", %d unanschließbare Felder ausgelassen" % skipped
	text += ", durchgehend an das Rathausnetz angeschlossen"
	return {"cells": cells, "platz": platz, "text": text}


func _connected_roads(root: Vector2i, center: Vector2i) -> Dictionary:
	var C: CityData = sim.city
	var found := {root: true}
	var todo: Array = [root]
	var i := 0
	while i < todo.size() and i < 10000:
		var w: Vector2i = todo[i]
		i += 1
		for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = w + d
			if not found.has(next) and maxi(absi(next.x - center.x), absi(next.y - center.y)) <= STREET_CONNECT_MAX + 12 and C.is_road(next):
				found[next] = true
				todo.append(next)
	return found


func _road_connector(component: Array, network: Dictionary, center: Vector2i, platz: Vector2i, k: int) -> Array:
	var previous := {}
	var todo: Array = []
	for w in component:
		previous[w] = w
		todo.append(w)
	var i := 0
	while i < todo.size() and i < 12000:
		var w: Vector2i = todo[i]
		i += 1
		for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = w + d
			if network.has(next):
				var path: Array = [w]
				while previous[w] != w:
					w = previous[w]
					path.push_front(w)
				return path
			if previous.has(next) or maxi(absi(next.x - center.x), absi(next.y - center.y)) > STREET_CONNECT_MAX + 12:
				continue
			if (platz.x >= 0 and Rect2i(platz, Vector2i(2, 2)).has_point(next)) or not _road_ok(next, k):
				continue
			previous[next] = w
			todo.append(next)
	return []


func _road_ok(w: Vector2i, k: int) -> bool:
	var C: CityData = sim.city
	if not C.inside(w) or C.building_at[C.idx(w)] >= 0 or C.g(w) in [CityData.G.WATER, CityData.G.RAIL, CityData.G.RUNWAY, CityData.G.QUAY]:
		return false
	if sim.eko != null:   # nicht durch einen Stammsitz (Mauern, Basis der Wesen)
		for e in sim.eko.estates.estates.values():
			if Rect2i(int(e.rect[0]), int(e.rect[1]), EkoEstates.SIDE, EkoEstates.SIDE).grow(1).has_point(w):
				return false
	if not C.height.is_empty() and C.height[C.idx(w)] > 0:
		return false
	var parcel: Dictionary = sim.parcels.at_cell(w)
	if not C.is_road(w) and not parcel.is_empty() and (not Towns.is_public(str(parcel.owner)) or Towns.town_of_owner(str(parcel.owner)) != k):
		return false
	return sim.access == null or not sim.access.reserved(w) or C.is_road(w)


static func _cardinal(a: Vector2i) -> Vector2i:
	if a == Vector2i.ZERO:
		return Vector2i(1, 0)
	return Vector2i(signi(a.x), 0) if absi(a.x) >= absi(a.y) else Vector2i(0, signi(a.y))


## Naechster Entwicklungsabschnitt (Auftrag 8, Abschnitt 6): laeuft schon ein Strassennetz, erst dieses; sonst das naechste Entwurfs-
## Viertel mit freiem Land – bei Wohnungsnot zuerst Wohnen, dann nach Naehe zum Kern. {} = nichts zu tun.
func next_district(k: int, housing_need: bool) -> Dictionary:
	var p := of(k)
	if p.is_empty():
		return {}
	var M = sim.towns.mayor(k) if sim.towns != null else null
	if M != null:
		for prj in M.projects.values():
			if prj.has("road_plan") and str(prj.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
				return {"warten": prj.id, "text": "Straßennetz %s für Viertel %s läuft – erst fertigstellen." % [prj.id, prj.viertel]}
	var repair := _repair_step(k, p)
	if not repair.is_empty():
		return repair
	var kern := Vector2(int(p.kern[0]), int(p.kern[1]))
	var best := {}
	var best_s := INF
	for v in p.viertel:
		if str(v.status) != "entwurf" or str(v.zone) == "gruen" or str(v.rolle) == "kern":
			continue
		var c := Vector2i(int(v.mitte[0]), int(v.mitte[1]))
		if maxf(free_share(c, 5), _raw_free_share(c, 5, k)) < 0.3:
			continue
		var sc := Vector2(c).distance_to(kern) - (40.0 if housing_need and str(v.zone) == "wohnen" else 0.0)
		if sc < best_s:
			best_s = sc
			best = v
	if best.is_empty():
		var sites := expansion_sites(k)
		if sites.is_empty():
			return {}
		var zone := "wohnen" if housing_need else ("gruen" if (p.viertel as Array).size() % 4 == 0 else "mischgebiet")
		return {"text": "Neue Stadterweiterung planen: Standort und Nutzung anhand der freien Flächen wählen.",
			"kandidaten": sites, "aktion": {"action": "stadtteil_planen", "mitte": sites[0].feld, "zone": zone,
				"name": "Neues %sviertel" % ("Grün" if zone == "gruen" else "Wohn" if zone == "wohnen" else "Misch"),
				"reason": "Freie Fläche mit Anschluss an den bestehenden Stadtkern"}}
	return {"viertel": best.id, "text": "Als Nächstes Viertel %s (%s, %s) erschließen%s." % [best.id, best.text, best.zone, " – es fehlt Wohnraum" if housing_need and str(best.zone) == "wohnen" else ""],
		"aktion": {"action": "viertel_erschliessen", "viertel": best.id, "reason": "Stadtplan: nächster Abschnitt"}}


## Alte Spielstaende koennen bereits einzelne Straßenrauten enthalten. Der Buergermeister
## erkennt fehlende Anschluesse einmal pro Tag und kann sie als normales Projekt schliessen.
func _repair_step(k: int, p: Dictionary) -> Dictionary:
	var key := "%d:%d:%d:%d" % [k, _day(), sim.city.road_count, sim.city.buildings.size()]
	if _repair_cache.has(key):
		return _repair_cache[key]
	if _repair_cache.size() > 32:
		_repair_cache.clear()
	var out := {}
	for v in p.viertel:
		if str(v.status) != "erschlossen" or str(v.zone) == "gruen":
			continue
		var sp: Dictionary = street_plan(k, str(v.id))
		if not (sp.cells as Array).is_empty():
			out = {"viertel": v.id, "text": "Straßennetz in Viertel %s ergänzen: %d fehlende, zusammenhängende Felder." % [v.id, sp.cells.size()],
				"aktion": {"action": "viertel_erschliessen", "viertel": v.id, "reason": "Lücken und isolierte Straßen im bestehenden Viertel verbinden"}}
			break
	_repair_cache[key] = out
	return out


## Standortentscheidung festhalten (SiteSelector): die letzten 12 je Stadt, fuer Zuschauer und KI nachvollziehbar.
const DECISIONS_MAX := 12


func note_decision(k: int, d: Dictionary) -> void:
	var p := of(k)
	if p.is_empty():
		return
	if not p.has("entscheidungen"):
		p["entscheidungen"] = []
	d["tag"] = _day() + 1
	(p.entscheidungen as Array).append(d)
	if (p.entscheidungen as Array).size() > DECISIONS_MAX:
		p.entscheidungen = (p.entscheidungen as Array).slice(-DECISIONS_MAX)


## Planrevision mit Begruendung (Entwicklungsgeschichte); aendert nie bestehende Gebaeude.
func revise(k: int, text: String) -> void:
	var p := of(k)
	if p.is_empty():
		return
	(p.geschichte as Array).append({"tag": _day(), "text": text})


func _kern_of(k: int) -> Vector2i:
	var t: Dictionary = sim.towns.get_t(k) if sim.towns != null else {}
	var hall := int(t.get("town_hall", -1))
	if hall >= 0:
		var b: Dictionary = sim.city.building(hall)
		if not b.is_empty():
			return Vector2i(int(b.x) + int(b.w) / 2, int(b.y) + int(b.h) / 2)
	return Vector2i(-1, -1)


func _founded(k: int) -> bool:
	return sim.town_ready(k) and int(sim.towns.get_t(k).get("town_hall", -1)) >= 0


func _name(k: int) -> String:
	return sim.towns.name_of(k) if sim.towns != null else str(k)


func _day() -> int:
	return GameCalendar.day_of(sim.game_min)


func to_dict() -> Dictionary:
	return {"v": VERSION, "towns": towns}


func from_dict(d: Dictionary) -> void:
	towns = d.get("towns", {})
	_expansion_cache.clear()
	_repair_cache.clear()
	for key in towns:   # Version 1 (18.11.): 6x5-Grundstuecke – ein Einfamilienhaus (5x4) ueberschritt die zulaessige Bebauung
		var p: Dictionary = towns[key]
		if int(p.get("v", 1)) < 2 and FORMS.has(str(p.form)):
			p.block = FORMS[str(p.form)].block.duplicate()
			p.v = VERSION
	for key in towns:   # JSON liefert Zahlen als float
		var p: Dictionary = towns[key]
		p.town = int(p.town)
		p.hausformen = (p.hausformen as Array).map(func(x): return int(x))
		p.hoehen = (p.hoehen as Array).map(func(x): return int(x))
		p.block = (p.block as Array).map(func(x): return int(x))
		for v in p.viertel:
			v.radius = int(v.radius)
			v.geschosse = int(v.geschosse)
