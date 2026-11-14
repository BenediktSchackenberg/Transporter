class_name StoneWorks
extends RefCounted
## Auftrag 23: Steinbauten und Stein-Kreationen der Unternehmer.
##
## Die KI plant (Motiv, Name, Standort auf dem eigenen Grundstueck, Grundton + Akzent); die Engine prueft
## Platz, Strasse, Kollision und Material (Aufbereiteter Stein aus dem Grosslager) und baut das Werk als
## Steinbau. Der Bau schreitet ueber die Bauzeit voran; danach malen eigene Maler (Faehigkeit "malen", ein
## Arbeitstag) das Werk in Grundton + Akzent an. Ohne Maler bleibt der Stein naturfarben. Das Spiel liest
## nur den Zustand; sichtbar macht es StoneWorksView (Requisit sw_<motiv> + zwei Farbmasken).

signal work_changed(id: String)

## Farbpalette der Maler (beide Ebenen frei kombinierbar -> viele unterscheidbare Werke).
const PALETTE := {
	"weiss": "#f2efe6", "creme": "#e8dcc0", "grau": "#8f9aa6", "blaugrau": "#6f8296", "schwarz": "#2b2e35",
	"rot": "#c23b33", "koralle": "#d96a4a", "orange": "#e07a2a", "gelb": "#e3b53c", "gruen": "#4c9a5a",
	"petrol": "#3f7d8c", "blau": "#3d6fb3", "lila": "#8e44ad", "weinrot": "#7c2b45", "rosa": "#d77a9e",
	"braun": "#8a5c38",
}
## Baumaterialien der Werke (13.11.: nicht nur Stein). Menge je Werk und Naturfarbe des unbemalten Werks (Tönung des Steinbilds;
## multiplikativ auf grauem Stein, daher hell gewaehlt).
const MATERIALS := {
	"stein": {"item": "naturstein_aufbereitet", "qty": 12, "tint": "", "label": "Stein"},
	"bronze": {"item": "bronze", "qty": 4, "tint": "#ffc47a", "label": "Bronze"},
	"holz": {"item": "holz", "qty": 20, "tint": "#f2c28c", "label": "Holz"},
	"stahl": {"item": "stahl", "qty": 8, "tint": "#dbe8f7", "label": "Stahl"},
	"beton": {"item": "beton", "qty": 15, "tint": "#fff6e8", "label": "Beton"},
}
const BUILD_DAYS_MIN := 3.0
const PAINT_MIN := 120.0            # Arbeitstage-Aufwand eines Malers (Spielminuten), Stufe 1

var sim
var works := {}                     # "SW<n>" -> {id, cid, motif, name, rect, parcel, base, accent, status, base_color, accent_color, progress, day, built_day, painted_day, m}
var _next := 1


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)


func enabled() -> bool:
	return sim != null and sim.estate != null


## Motive mit dem Label aus der Voxel-Pipeline (tools/vox/stoneworks.py; alle 1×1 Feld, Material 12).
const MOTIF_LABELS := {
	"statue": "Statue", "obelisk": "Obelisk", "fountain": "Springbrunnen", "gate": "Triumphbogen", "column": "Säule",
	"monument_wall": "Gedächtniswand", "cat_statue": "Steinkatze", "ufo": "Ufo-Stein", "ice_cream": "Rieseneis",
	"mushroom": "Pilzhütte", "ferris_wheel": "Riesenrad", "carousel": "Karussell", "hedgehog": "Steinigel",
	"balloon": "Ballon-Stein", "lighthouse": "Leuchtturm", "turtle": "Stein-Schildkröte", "rocket": "Steinrakete",
}

## Katalog der Motive: id -> {motiv, label, w, h, material} — waehlt die KI, die Engine baut.
func motif_catalog() -> Array:
	var out: Array = []
	for m in MOTIF_LABELS:
		out.append({"motiv": m, "label": MOTIF_LABELS[m], "w": 1, "h": 1, "material": 12})
	return out


## Beobachtung fuer die KI: eigene Werke (Name, Motiv, Status, Farben) und der Motiventwurf.
func obs_of(cid: int) -> Dictionary:
	var mine: Array = []
	for a in works.values():
		if int(a.cid) != cid:
			continue
		mine.append({"name": a.name, "motiv": a.motif, "status": a.status,
			"grundton": (a.base_color if a.base_color != "" else "natur"), "akzent": (a.accent_color if a.accent_color != "" else "natur")})
	var painters: int = sim.personnel.employed(cid).filter(func(w): return int(w.skills.get("malen", 0)) > 0).size()
	# Motive und Farbpalette stehen im Aktions-Handbuch (create_stone_work); die Beobachtung haelt nur den
	# dynamischen Zustand klein, damit der Prompt der lokalen Modelle unter dem Token-Budget bleibt.
	# Machbarkeit jetzt je Material (13.11.: die Modelle bauten nie, die Beobachtung sagte nicht, ob Material, Geld und Platz reichen)
	var site := not _find_site(cid, 1, 1).is_empty() or not _site_offer(cid, 1, 1).is_empty()   # notfalls kleines Grundstueck kaufen
	var cash: float = sim.company(cid).ledger.cash if sim.company(cid) != null else 0.0
	# Kompakt (Token-Budget der lokalen Modelle): nur die jetzt machbaren Materialien mit ihren Kosten und eine Anregung.
	var costs := {}
	for m in MATERIALS:
		var f := material_cost(cid, str(m))
		if site and bool(f.vorhanden) and cash >= float(f.kosten_eur):
			costs[m] = int(f.kosten_eur)
	var ok := not costs.is_empty()
	var out := {"werke": mine, "maler": painters, "jetzt_moeglich": ok}
	if not ok:
		out["grund"] = "kein freier Platz" if not site else "Material/Geld fehlt"
		return out
	out["material_kosten"] = costs
	var rng := RandomNumberGenerator.new()   # Anregung, wechselt taeglich: nehmen, abwandeln oder etwas ganz anderes bauen
	rng.seed = hash("idee%d_%d" % [cid, GameCalendar.day_of(sim.game_min)])
	var mot: Array = MOTIF_LABELS.keys()
	var cols: Array = PALETTE.keys()
	var feasible: Array = costs.keys()
	out["idee"] = "%s/%s/%s/%s" % [mot[rng.randi() % mot.size()], feasible[rng.randi() % feasible.size()], cols[rng.randi() % cols.size()], cols[rng.randi() % cols.size()]]
	return out


## Bedarf, Vorrat und Kosten eines Materials fuer ein Werk der Firma.
func material_cost(cid: int, material: String) -> Dictionary:
	var m: Dictionary = MATERIALS[material]
	var item: String = m.item
	var own: int = sim.stock.available(item, "C%d" % cid)
	var hub_on: bool = sim.hub != null and sim.hub.enabled and sim.hub.GOODS.has(item)
	var hub_have: int = sim.hub.stock_of(item) if hub_on else 0
	var need := int(m.qty)
	var cost := snappedf(sim.hub.price(item) * float(maxi(0, need - own)), 1.0) if hub_on and need > own else 0.0
	return {"noetig": need, "eigen": own, "grosslager": hub_have, "kosten_eur": cost, "vorhanden": own + hub_have >= need}


func colors_valid(base: String, accent: String) -> String:
	for col in [base, accent]:
		if col == "" or (str(col).begins_with("#") or PALETTE.has(str(col))):
			continue
		return "Unbekannte Farbe '%s' (Palette: %s oder hex)." % [col, ", ".join(PALETTE.keys())]
	return ""


## Grundton + Akzent als Hex aufloesen (Palette oder hex); leer bleibt naturfarbener Stein.
func _resolve(col: String) -> String:
	if col == "":
		return ""
	if PALETTE.has(str(col)):
		return str(PALETTE[col])
	if str(col).begins_with("#"):
		return str(col).left(7)
	return ""


## KI plant, Engine baut: prueft Motiv, Platz (freies eigenes Grundstueck mit Strasse), Material und
## baut das Werk. status "geplant" -> "im_bau" (Baufortschritt) -> "fertig" (Maler malt es an).
func create(cid: int, motif: String, name: String, base_color: String, accent_color: String, params: Dictionary = {}) -> Dictionary:
	if not enabled():
		return {"ok": false, "msg": "Steinbauten sind auf dieser Karte nicht verfuegbar."}
	var c = sim.company(cid)
	if c == null or c.status in ["insolvenz", "verwertung", "geschlossen"]:
		return {"ok": false, "msg": "Unternehmen kann nicht bauen."}
	var catalog := motif_catalog()
	var found: Dictionary = {}
	for m in catalog:
		if str(m.motiv) == motif:
			found = m
	if found.is_empty():
		return {"ok": false, "msg": "Unbekanntes Motiv '%s'. Motive: %s" % [motif, ", ".join(catalog.map(func(m): return str(m.motiv)))]}
	var err := colors_valid(base_color, accent_color)
	if err != "":
		return {"ok": false, "msg": err}
	var w: int = int(found.w)
	var h: int = w
	var site := acquire_site(cid, w, h)
	if site.is_empty():
		return {"ok": false, "msg": "Kein freies eigenes Grundstueck %d×%d mit Strasse gefunden und keines bis %s zu kaufen." % [w, w, Catalog.money(SITE_MAX_PRICE)], "grund": "platz"}
	var material := str(params.get("material", "stein")).to_lower()
	if material == "" or material == "naturstein":
		material = "stein"
	if not MATERIALS.has(material):
		return {"ok": false, "msg": "Unbekanntes Material '%s'. Möglich: %s." % [material, ", ".join(MATERIALS.keys())]}
	var item: String = MATERIALS[material].item
	var iname: String = CityGoods.get_item(item).name if CityGoods.exists(item) else item
	var mat := int(MATERIALS[material].qty)
	var own: int = sim.stock.available(item, "C%d" % cid)
	var hub_enabled: bool = sim.hub != null and sim.hub.enabled
	var hub_have: int = sim.hub.stock_of(item) if hub_enabled else 0
	if own + hub_have < mat:
		return {"ok": false, "msg": "Nur %d × %s erreichbar (eigene Depots %d, Großlager %d; benötigt %d). Anderes Material wählen oder mit hub_buy zukaufen." % [own + hub_have, iname, own, hub_have, mat], "grund": "material", "verfuegbar": own, "grosslager": hub_have, "noetig": mat}
	# Eigene Vorräte sind bereits bezahlt; nur der Großlager-Anteil kostet Geld (zum aktuellen Lagerpreis).
	var est_hub := mini(mat - own, hub_have)
	var est_cost := snappedf(sim.hub.price(item) * float(est_hub), 0.01) if hub_enabled else 0.0
	if c.ledger.cash < est_cost:
		return {"ok": false, "msg": "Der Großlager-Anteil (%d × %s) kostet %s, verfügbar %s." % [est_hub, iname, Catalog.money(est_cost), Catalog.money(c.ledger.cash)], "grund": "geld"}
	var days := snappedf(BUILD_DAYS_MIN + float(w) * 2.0, 0.5)
	var id := "SW%d" % _next
	_next += 1
	var a := {"id": id, "cid": cid, "motif": motif, "name": str(name).left(40) if name != "" else str(found["label"]),
		"rect": site.rect, "parcel": str(site.parcel), "base": _resolve(base_color), "accent": _resolve(accent_color),
		"status": "geplant", "base_color": "", "accent_color": "", "progress": 0.0, "day": GameCalendar.day_of(sim.game_min),
		"built_day": -1, "painted_day": -1, "m": mat, "days": days, "material": material}
	works[id] = a
	# Material wird beim Baubeginn verbraucht; bis dahin reserviert (eigene Depots, dann Großlager), damit nichts doppelt vergeben wird.
	var refs: Array = _reserve_material(cid, id, mat, item)
	var total := int(refs.back()) if refs.size() >= 2 else 0
	if total < mat:
		for r in refs.slice(0, -1):
			sim.stock.release(r)
		works.erase(id)
		return {"ok": false, "msg": "Nicht genug %s reservierbar (verfügbar %d, benötigt %d). Anderes Material wählen oder im Großlager nachkaufen." % [iname, own, mat], "grund": "material"}
	# Bezahlt wird genau der Großlager-Anteil (eigene Vorräte sind bereits bezahlt); Ware + Geld wechseln beim Kauf.
	var hub_qty := 0
	for r in refs:
		if str(r).ends_with("@hub"):
			hub_qty += int(sim.stock.reservations[r].qty)
	if hub_enabled and hub_qty > 0:
		var cost := snappedf(sim.hub.price(item) * float(hub_qty), 0.01)
		if c.ledger.cash < cost:
			for r in refs:
				sim.stock.release(r)
			works.erase(id)
			return {"ok": false, "msg": "Der Großlager-Anteil (%d × %s) kostet %s, verfügbar %s." % [hub_qty, iname, Catalog.money(cost), Catalog.money(c.ledger.cash)], "grund": "geld"}
		c.ledger.book("supplies", -cost, true, "Großlager: %d × %s (Werk %s)" % [hub_qty, iname, a.name], sim.game_min, CentralHub.ACCT)
		sim.hub.demand[item] = float(sim.hub.demand.get(item, 0.0)) + float(hub_qty)
	a["refs"] = refs.slice(0, -1)
	sim.log_event("%s plant %s (Motiv %s aus %s). Material %d × %s (davon %d Großlager), Bau %d Tage." % [
		c.company_name, a.name, motif, MATERIALS[material].label, mat, iname, hub_qty, int(days)], "info", cid)
	work_changed.emit(id)
	return {"ok": true, "msg": "%s geplant: %s auf %s (Bauzeit %d Tage). Material reserviert – der Bau läuft, danach malt der Maler an." % [
		a.name, a.name, a.parcel, int(days)], "ref": id}


## Material an den eigenen Standorten reservieren, Rest beim Großlager. Rückgabe [Ref1, Ref2, ..., gesamt reserviert].
func _reserve_material(cid: int, wid: String, amount: int, item: String = "naturstein_aufbereitet") -> Array:
	var out: Array = []
	var left := amount
	var c = sim.company(cid)
	for site in (c.depots if c != null and not c.depots.is_empty() else []):
		if left <= 0:
			break
		# nur so viel wie an diesem Standort frei ist (reserve ist alles-oder-nichts)
		var avail: int = sim.stock.available(item, "C%d" % cid, site)
		if avail <= 0:
			continue
		var take := mini(left, avail)
		var ref := "%s@%d" % [wid, site]
		var got: bool = sim.stock.reserve(ref, item, take, "C%d" % cid, site)
		if got:
			out.append(ref)
			left -= int(sim.stock.reservations[ref].qty)
	if left > 0 and sim.hub != null and sim.hub.enabled:
		var href := "%s@hub" % wid
		if sim.stock.reserve(href, item, left, CentralHub.ACCT, sim.hub.loc):
			out.append(href)
			left -= int(sim.stock.reservations[href].qty)
	out.append(maxi(0, amount - left))
	return out


## Freies eigenes Grundstueck (Estate) mit Strasse am Rand, das w×w Zellen frei haelt.
## Platz fuer ein Werk oder Bauwerk: zuerst auf eigenem Grund; ist alles belegt (Partie 14.11.: "kein freier Platz" bei vollen
## Hoefen), kauft die Firma ein kleines freies Grundstueck mit Strassenzugang im Heimatort (hoechstens SITE_MAX_PRICE, Reserve bleibt).
const SITE_MAX_PRICE := 15000.0
const SITE_CASH_LEFT := 10000.0


func acquire_site(cid: int, w: int, h: int) -> Dictionary:
	var site := _find_site(cid, w, h)
	if not site.is_empty():
		return site
	var p := _site_offer(cid, w, h)
	if p.is_empty():
		return {}
	var c: Company = sim.company(cid)
	var town: int = sim.towns.of_parcel(str(p.id)) if sim.towns.is_region() else 0
	var seller := Towns.account_of(town)
	var price := float(p.price)
	p.owner = "C%d" % cid
	p["lease_by"] = -1
	p["book"] = price
	c.ledger.invest(price, seller)
	c.land_book += price
	sim.parcels.touch(str(p.id))
	sim.log_event("%s kauft Grundstück %s (%d Felder, %s) für ein eigenes Bauwerk." % [c.company_name, p.id, int(p.area), Catalog.money(price)], "info", cid)
	return _find_site(cid, w, h)


## Guenstigstes freies Grundstueck im Heimatort, gross genug, mit Strasse, bezahlbar - ohne zu kaufen.
func _site_offer(cid: int, w: int, h: int) -> Dictionary:
	var c: Company = sim.company(cid)
	if c == null or sim.parcels == null:
		return {}
	var budget := minf(SITE_MAX_PRICE, c.ledger.cash - SITE_CASH_LEFT)
	if budget <= 0.0:
		return {}
	var crit := {"min_area": (w + 1) * (h + 1), "max_price": budget, "limit": 30}
	if sim.towns.is_region():
		crit["town"] = int(c.home_town)
	var offers: Array = []
	for zone in ["gewerbe", "mischgebiet", "industrie", "wohnen"]:   # keine Flaechen fuer oeffentliche Einrichtungen, Gruen oder Strand
		var cz := crit.duplicate()
		cz["zone"] = zone
		offers.append_array(sim.parcels.search(cz).filter(func(q): return float(q.price) > 0.0))
	offers.sort_custom(func(a, b): return float(a.price) < float(b.price))
	for p in offers:
		if not bool(sim.parcels.utilities_of(p).get("strasse", false)):
			continue
		var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		for y in range(pr.position.y, pr.end.y - h + 1):
			for x in range(pr.position.x, pr.end.x - w + 1):
				if sim.events._free(Rect2i(x, y, w, h)):
					return p
	return {}


func _find_site(cid: int, w: int, h: int) -> Dictionary:
	for p in sim.estate.plot_of(cid):
		if int(p.get("w", 0)) * int(p.get("h", 0)) < w * h:
			continue
		var pr := Rect2i(int(p.x), int(p.y), int(p.w), int(p.h))
		if pr.size.x < w or pr.size.y < h:
			continue
		# andere Werke auf diesem Grundergrund meiden
		var occ := _occupied_cells(cid)
		for y in range(pr.position.y, pr.end.y - h + 1):
			for x in range(pr.position.x, pr.end.x - w + 1):
				var r := Rect2i(x, y, w, h)
				if not _cells_free(r, occ):
					continue
				if not _touches_road(r):
					continue
				return {"rect": [r.position.x, r.position.y, w, h], "parcel": str(p.id)}
	# Gruender haben kein Startgrundstueck, sondern eigene Parzellen (gekauft/gepachtet fuer ihre Betriebe);
	# dort ist frei, was kein Gebaeude traegt (EventDirector._free prueft Gebaeude, Sperren, Wasser und Strassenzugang).
	if sim.parcels == null:
		return {}
	var occ2 := _occupied_cells(cid)
	for p in sim.parcels.items.values():
		if str(p.owner) != "C%d" % cid:
			continue
		var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		for y in range(pr.position.y, pr.end.y - h + 1):
			for x in range(pr.position.x, pr.end.x - w + 1):
				var r := Rect2i(x, y, w, h)
				if _cells_free(r, occ2) and sim.events._free(r):
					return {"rect": [r.position.x, r.position.y, w, h], "parcel": str(p.id)}
	return {}


## Zellenbelegung der Firma: Einrichtungen aus sim.estate.facilities (der Parzellen-Container ist ein
## Gebaeude ueber das ganze Grundstueck und darf nicht zoehlen) plus unsere fertigen/im Bau befindlichen Werke.
func _occupied_cells(cid: int) -> Dictionary:
	var out := {}
	for f in sim.estate.facilities.values():
		if int(f.get("owner", -1)) != cid:
			continue
		for c in _estate_cells(f):
			out[c] = "facility"
	for a in works.values():
		if str(a.status) in ["abgelehnt", "geplant"]:
			continue
		var r := Rect2i(int(a.rect[0]), int(a.rect[1]), int(a.rect[2]), int(a.rect[3]))
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				out[Vector2i(x, y)] = "work"
	if sim.freebuild != null:
		for fb in sim.freebuild.builds.values():
			if int(fb.cid) == cid:
				for q in sim.freebuild.cells_of(fb):
					out[q] = "freibau"
	return out


func _estate_cells(f: Dictionary) -> Array:
	var out: Array = []
	for y in range(int(f.h)):
		for x in range(int(f.w)):
			out.append(Vector2i(int(f.x) + x, int(f.y) + y))
	return out


func _cells_free(r: Rect2i, occ: Dictionary) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var q := Vector2i(x, y)
			if not sim.city.inside(q):
				return false
			if sim.city.g(q) in [CityData.G.ROAD, CityData.G.WATER, CityData.G.RAIL]:
				return false
			if occ.has(q):
				return false
	return true


func _touches_road(r: Rect2i) -> bool:
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			if sim.city.inside(Vector2i(x, y)) and sim.city.is_road(Vector2i(x, y)):
				return true
	return false


## Bauablauf je Tag; fertige Werke werden vom Maler angemalt (Aufgabe "malen", ein Arbeitstag).
func on_day(day: int) -> void:
	if not enabled():
		return
	for a in works.values():
		match str(a.status):
			"geplant":
				a.status = "im_bau"
				a.progress = 0.0
				# Material wird jetzt verausgabt (alle Reservierungs-Referenzen)
				for r in a.get("refs", []):
					sim.stock.consume_reserved(r, "Steinbau %s (Baubeginn)" % a.name, sim.game_min)
				a["refs"] = []
				work_changed.emit(a.id)
			"im_bau":
				a.progress = clampf(float(a.progress) + 1.0 / float(a.days), 0.0, 1.0)
				if a.progress >= 1.0:
					a.status = "fertig"
					a.built_day = day
					sim.log_event("%s: %s steht – der Stein wartet auf die Maler." % [sim.company(int(a.cid)).company_name, a.name], "good", int(a.cid))
					if a.get("paint_days", -1) < 0:
						_assign_painter(int(a.cid), a.id)
					work_changed.emit(a.id)
			"fertig":
				# Werk ohne Farben bleibt naturfarben
				if a.base == "" and a.accent == "":
					a.status = "natur"
					work_changed.emit(a.id)
					continue
				# Anmalen: ein Arbeitstag pro Maler (auf Tag-Basis, damit es auch ohne Frameschritte laeuft).
				if a.get("paint_days", -1) < 0:
					_assign_painter(int(a.cid), a.id)
				elif a.painted_day < 0:
					# Maler seit gestern im Einsatz: ein Arbeitstag = ein Tag
					a.painted_day = day
				elif day - a.painted_day >= int(a.get("paint_days", 1)):
					a.base_color = a.base
					a.accent_color = a.accent
					a.status = "angemalt"
					var pw: Worker = sim.personnel.workers.get(str(a.get("painter", "")))
					if pw != null:
						pw.experience = minf(100.0, pw.experience + 3.0)
					sim.log_event("%s: %s ist angemalt (Grundton %s, Akzent %s). Ein Steinwerk der Stadt." % [sim.company(int(a.cid)).company_name, a.name, _colname(a.base), _colname(a.accent)], "good", int(a.cid))
					work_changed.emit(a.id)


## Ein frei disponierbarer Maler der Firma malt das Werk (Aufgabe "malen", Ziel = Werk-ID).
func _assign_painter(cid: int, work_id: String) -> void:
	for w in sim.personnel.employed(cid):
		if int(w.skills.get("malen", 0)) < 1:
			continue
		if sim.personnel.can_take(w, "malen") != "":
			continue
		var a: Dictionary = works[work_id]
		var center := Vector2i(int(a.rect[0]) + int(a.rect[2]) / 2, int(a.rect[1]) + int(a.rect[3]) / 2)
		sim.personnel.create_task(cid, "malen", {"work": work_id}, w.id, "", 2, "Steinbauten")
		w.pos = sim.city.tile_center(center)
		a["paint_days"] = 1
		a["painter"] = w.id
		return


## Vom Maler (Aufgabe abgeschlossen) aufgerufen: Farben uebernehmen, Status "angemalt".
func painted(work_id: String, base_hex: String, accent_hex: String) -> void:
	var a: Dictionary = works.get(work_id, {})
	if a.is_empty() or str(a.status) != "fertig":
		return
	a.base_color = base_hex
	a.accent_color = accent_hex
	a.status = "angemalt"
	a.painted_day = GameCalendar.day_of(sim.game_min)
	var c = sim.company(int(a.cid))
	sim.log_event("%s: %s ist angemalt (Grundton %s, Akzent %s). Ein Steinwerk der Stadt." % [c.company_name, a.name, _colname(base_hex), _colname(accent_hex)], "good", int(a.cid))
	work_changed.emit(a.id)


func _colname(hex: String) -> String:
	for k in PALETTE:
		if str(PALETTE[k]) == hex:
			return str(k)
	return hex


## Werk an einen Standort verschieben/entfernen (Rueckbau).
func demolish(cid: int, work_id: String) -> Dictionary:
	var a: Dictionary = works.get(work_id, {})
	if a.is_empty() or int(a.cid) != cid:
		return {"ok": false, "msg": "Kein eigenes Werk %s." % work_id}
	a.status = "abgelehnt"
	work_changed.emit(work_id)
	return {"ok": true, "msg": "%s wird abgerissen." % a.name}


func works_of(cid: int) -> Array:
	return works.values().filter(func(a): return int(a.cid) == cid and str(a.status) not in ["abgelehnt"])


func to_dict() -> Dictionary:
	return {"works": works, "next": _next}


func from_dict(d: Dictionary) -> void:
	works = d.get("works", {})
	_next = int(d.get("next", 1))
