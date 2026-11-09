class_name Production
extends RefCounted
## Produktionsketten der Unternehmer (Auftrag 14, Etappe 2: Getreide -> Mehl -> Brot; docs/ENTREPRENEURS.md).
##
## Betriebe (Businesses) mit Feld oder Rezept arbeiten einmal je Spieltag:
##   Feld:     Vorbereitung -> Aussaat (verbraucht Saatgut) -> Wachstum (Wetter, Pflege) -> Ernte -> Getreide liegt am Feld.
##   Rezept:   Eingangswaren am Standort + Personal + Strom -> Ausgangswaren am Standort (Muehle, Baeckerei).
## Beschaffung: Fehlt Eingangsware, bestellt der Betrieb beim guenstigsten Anbieter (Ware + Fracht je Stueck): andere Betriebe mit
## freiem Bestand oder Import ueber das Lager des Lebensmittelgrosshandels (Lieferzeit = Transport). Ein Liefervertrag ("D<n>") reserviert die Ware beim
## Verkaeufer und schreibt einen echten Transportauftrag aus (Zahler = Kaeufer). Bei Anlieferung wechselt das Eigentum und der
## Kaeufer zahlt. Interne Lieferungen (gleiche Company) kosten keinen Warenpreis und erzeugen keinen Umsatz.
## Der Lebensmittelgrosshandel (W0) kauft Brot zuerst bei lokalen Baeckereien (Retail._stock_wholesale), nur der Rest ist Import.
## Ware entsteht nur durch Ernte, Rezeptausgang oder Import (StockBook.add) und verschwindet nur durch Verbrauch/Verderb (consume).

const ARTICLES_PATH := "res://config/articles.json"
const IMPORT := "X0"
const OFFER_DAYS := 1
const FALLBACK_SHARE := 0.7          # Lieferdienst, wenn niemand den Transport uebernimmt (wie im Einzelhandel)
const SPOIL_SHARE := 0.25            # Anteil verderblicher Ware am Produktionsstandort, der taeglich verdirbt
const MAX_DEALS_KEPT := 300
const COLD_SPOIL := 0.08             # Kuehlware je Tag im gekuehlten Lager
const WARM_SPOIL := 0.5              # Kuehlware je Tag ohne Strom
const START_BATCHES := 4
const UPSTREAM := {"getreide": "feld", "holz": "forst", "mehl": "muehle", "schlachttier": "tierhaltung", "koks": "kokerei", "eisenerz": "bergwerk", "kohle": "bergwerk", "kalkstein": "bergwerk"}
## Lagerstaetten (Abschnitt 5, vereinfacht): ausgewaehlte freie Parzellen ausserhalb von Wohn- und Mischgebiet tragen ein Vorkommen.
## Deterministisch aus Stadtsamen und Parzellen-ID; Menge in Einheiten (100 kg), Qualitaet 0,6-1,0 (Foerderung je Person).
const DEPOSIT_KINDS := ["eisenerz", "kohle", "kalkstein", "rohmaterial"]
const DEPOSIT_SHARE := 0.35
const OUTSKIRTS := 0.62           # Anteil des Kartenhalbmessers, ab dem der Aussenbereich beginnt   # Rohware -> Branche, die sie in der Stadt erzeugt             # Mindestbestand verderblicher Ware in Chargen (Anlauf ohne Absatzmessung)

static var _articles := {}

var sim
var deals := {}                      # "D<n>" -> Liefervertrag
var mined := {}                      # Parzelle -> bereits gefoerderte Menge (Lagerstaette bleibt beim Besitzerwechsel erschoepft)
var terrain := {}                    # Parzelle -> Bergmassiv {cells: {Vector2i: Hoehe in Stufen}, order: [Zellen ab der Abbaufront], art}
var blasts := {}                     # Betrieb -> Spielminute der letzten Sprengung (fuer Darstellung und Protokoll)
var _deposits := {}
var stats := {"produced": {}, "consumed": {}, "imported": {}, "exported": {}, "sold": 0.0, "deals": 0, "fallback": 0, "spoiled": 0}
var _next := 1


static func articles() -> Dictionary:
	if _articles.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ARTICLES_PATH)) if FileAccess.file_exists(ARTICLES_PATH) else null
		var d: Dictionary = parsed if parsed is Dictionary else {}
		for k in d:
			if not str(k).begins_with("_"):
				_articles[k] = d[k]
	return _articles


static func art(item: String) -> Dictionary:
	return articles().get(item, {})


static func item_name(item: String) -> String:
	return str(art(item).get("name", item))


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)
	_build_deposits()
	_build_terrain()


# ------------------------------------------------------------------ Gruendung
## Produktionsbetrieb gruenden. params: standort ("hauptsitz" | "markt" | Parzelle "G<n>"; ohne Angabe der Standard der Branche),
## grundstueck (Parzelle "G<n>", gleichbedeutend), modus ("pachten"|"kaufen"). Feld: guenstigste passende Parzelle. "markt": freie
## Parzelle mit Strassenzugang, die dem Lebensmittelgrosshandel am naechsten liegt (kurze Wege zu Kunden, aber hoehere Pacht).
## Ausstattung (Maschinen, Ofen, Traktor) ist eine Investition mit Abschreibung je Tag (Kostenstelle des Betriebs).
## Neue Betriebsgebaeude baut ein Bautrupp (Construction.add_company_works); in Tests mit fertigen Betrieben abschaltbar.
var instant_build := false
const WORKS_SHARE := 0.4            # Anteil der Ausstattung, der als Bauauftrag an die Baufirma geht (Gesamtkosten unveraendert)


func found(cid: int, branch: String, params: Dictionary, reason: String) -> Dictionary:
	var spec: Dictionary = Businesses.branches().get(branch, {})
	var c = sim.company(cid)
	var equip := float(spec.get("ausstattung", 0.0))
	var site := -1
	var parcel := {}
	var land := 0.0
	var mode := str(params.get("modus", "pachten"))
	var cands: Array = []
	var where := str(params.get("grundstueck", ""))
	if where == "":
		where = str(params.get("standort", ""))
	if where == "":
		where = str(spec.get("standort", "hauptsitz"))
	var btype := str(spec.get("gebaeude", "farm"))
	var bsize: Array = CityGenerator.TYPES[btype]
	if spec.has("abbau"):
		if sim.mining.enabled and not where.begins_with("G"):
			var own_pid: String = sim.mining.permitted_for(cid, str(params.get("rohstoff", "")))   # Lagerstaette mit eigenem Abbaurecht zuerst
			if own_pid != "":
				where = own_pid
		var dep := best_deposit(str(params.get("rohstoff", "")), where if where.begins_with("G") else "")
		if not dep.is_empty():
			var chk: Dictionary = sim.mining.check_found(cid, str(dep.grundstueck))
			if not chk.ok:
				return chk
		if dep.is_empty():
			var far := remote_deposit(str(params.get("rohstoff", "")))
			if not far.is_empty():
				return {"ok": false, "msg": "Keine Lagerstätte mit Straßenanschluss%s. Zufahrt zu %s bauen (build_access, %s, %d Tage)." % [(" für " + str(params.get("rohstoff", ""))) if str(params.get("rohstoff", "")) != "" else "", far.grundstueck, Catalog.money(float(far.kosten)), int(far.tage)]}
			return {"ok": false, "msg": "Keine freie Lagerstätte%s gefunden (deposits: %s)." % [(" für " + str(params.get("rohstoff", ""))) if str(params.get("rohstoff", "")) != "" else "", ", ".join(DEPOSIT_KINDS)]}
		mode = "kaufen"   # Abbaurecht nur auf eigenem Grund
		cands = [sim.parcels.parcel(str(dep.grundstueck))]
		parcel = cands[0]
		land = float(parcel.price)
	elif spec.has("feld") or where != "hauptsitz":
		var pid := where if where.begins_with("G") else ""
		var min_area: int = int(spec.feld.min_flaeche) if spec.has("feld") else int(bsize[1]) * int(bsize[2]) + 4
		var near_to: int = int(sim.trader.bauhof) if str(spec.get("naehe", "")) == "bauhof" else int(sim.retail.wholesale_building)
		var town0 := target_town(cid, params)
		if town0 >= 0 and town0 != sim.towns.of_building(near_to):
			near_to = int(sim.towns.get_t(town0).town_hall)   # Region: Marktlage in der Zielstadt (Naehe Ortszentrum)
		cands = _parcel_candidates(pid, min_area, float(spec.get("strom_kw", 0.0)) > 0.0) if spec.has("feld") or pid != "" or where == "parzelle" else _market_candidates(min_area, near_to)
		var town := target_town(cid, params)
		if town >= 0 and pid == "":
			cands = cands.filter(func(p): return sim.towns.of_parcel(str(p.id)) == town)   # Region: Standort in der gewuenschten Stadt
		if branch in ["hotel", "strandbar"]:
			cands = cands.filter(func(p):
				var tk: int = sim.towns.of_parcel(str(p.id))
				var ctr: Vector2i = sim.towns.get_t(tk).center
				var px := int(p.rect[0]) + int(p.rect[2]) / 2
				return sim.city.coastal() and absi(px - ctr.x) <= (28 if branch == "hotel" else 20) and p.zone != "strand")
		if cands.is_empty() and pid != "":
			return {"ok": false, "msg": "Grundstück %s (%s) ist nicht frei, kleiner als %d Felder, ohne Straßenzugang oder nicht bebaubar - ein Grundstück aus den Standorthinweisen wählen." % [pid, sim.towns.name_of(sim.towns.of_parcel(pid)), min_area]}
		if cands.is_empty():
			return {"ok": false, "msg": "Kein freies Grundstück mit Straßenzugang und mindestens %d Feldern verfügbar%s." % [min_area, (" in " + sim.towns.name_of(town)) if town >= 0 else ""]}
		parcel = cands[0]
		land = float(parcel.price) if mode == "kaufen" else 0.0
	else:
		if c.depots.is_empty():
			return {"ok": false, "msg": "Kein Hauptsitz vorhanden."}
		site = int(c.depots[0])
		if sim.biz.of(cid).any(func(b): return b.branch == branch and int(b.site) == site):
			return {"ok": false, "msg": "Am Hauptsitz gibt es schon einen Betrieb dieser Branche."}
	if c.ledger.cash < equip + land:
		return {"ok": false, "msg": "Nicht genug Bargeld: Ausstattung %s%s." % [Catalog.money(equip), " + Grundstück %s" % Catalog.money(land) if land > 0.0 else ""]}
	if not parcel.is_empty() and sim.towns.is_region():
		var perm: Dictionary = sim.towns.mayor(sim.towns.of_parcel(str(parcel.id))).business_permit(cid, parcel, branch)   # Stadt der Lage entscheidet
		if not perm.ok:
			return perm
	if not parcel.is_empty():
		var bld := {}
		for p in cands:   # erstes Grundstueck, auf dem das Hofgebaeude Strassenzugang hat
			if mode == "kaufen" and c.ledger.cash < equip + float(p.price):
				continue
			bld = _place_field(p, "%s %s" % [spec.label, c.company_name], btype)
			if not bld.is_empty():
				parcel = p
				land = float(p.price) if mode == "kaufen" else 0.0
				break
		if bld.is_empty():
			return {"ok": false, "msg": "Auf %s ist kein Platz mit Straßenzugang." % ("Grundstück " + str(parcel.id) if cands.size() == 1 else "den freien Grundstücken")}
		site = int(bld.id)
		var seller := Towns.account_of(sim.towns.of_parcel(str(parcel.id)))   # Verkaeufer: Stadt der Lage
		parcel.owner = "C%d" % cid
		parcel["lease_by"] = cid if mode != "kaufen" else -1
		if mode == "kaufen":
			c.ledger.invest(land, seller)
			c.land_book += land
			parcel["book"] = land
		sim.parcels.touch(parcel.id)
	var build := not instant_build and not parcel.is_empty()   # neues Gebaeude: erst bauen, dann betreiben
	var b: Dictionary = sim.biz.create(cid, branch, site, "", "im_bau" if build else "aktiv")   # nie Standard-Kostenstelle: Transport- und Hauptsitzbuchungen gehoeren nicht hierher
	var works_price := snappedf(maxf(equip, 8000.0) * WORKS_SHARE, 10.0) if build else 0.0
	if equip > 0.0 or works_price > 0.0:
		c.ledger.invest(maxf(0.0, equip - works_price), "S0")
		if works_price > 0.0:
			c.ledger.invest(works_price, "K0")   # Bauauftrag: Geld liegt bei den Baufirmen (K0) bis zur Fertigstellung
		c.property_book += maxf(equip, works_price)
		b["book"] = maxf(equip, works_price)
		b["equip"] = equip
		b["works_price"] = works_price
	b["prices"] = {}
	if not parcel.is_empty():
		b["parcel"] = parcel.id
		b["land_mode"] = "kauf" if mode == "kaufen" else "pacht"
		b["lease_day"] = float(parcel.lease_month) / 30.0 if mode != "kaufen" else 0.0
	if spec.has("abbau"):
		var dp := deposit_of(str(parcel.id))
		b["deposit"] = {"art": dp.art, "qualitaet": dp.qualitaet}
	if spec.has("feld"):
		b["field"] = {"area": int(parcel.area), "phase": "brache", "day": 0, "growth": 0.0, "grow_days": 0, "cycles": 0, "last_yield": 0}
	sim.biz.note(b.id, "Gegründet: %s" % (reason if reason != "" else spec.label), "Unternehmer")
	sim.log_event("%s gründet %s%s." % [c.company_name, b.name, " auf Grundstück %s (%d Felder, %s)" % [parcel.id, int(parcel.area), "gekauft" if mode == "kaufen" else "gepachtet"] if not parcel.is_empty() else " am Hauptsitz"], "info", cid)
	if build:
		var w: Dictionary = sim.construction.add_company_works(cid, b, site, "bergwerk" if spec.has("abbau") else "betrieb", works_price)
		sim.biz.note(b.id, "Bauauftrag %s an %s (%s, etwa %d Tage)" % [w.id, w.builder_name, Catalog.money(float(w.price)), int(w.days)], "Unternehmer")
		return {"ok": true, "msg": "%s gegründet (%s); %s baut das Gebäude (Auftrag %s, etwa %d Tage). Danach Personal zuordnen (assign_staff)." % [b.name, b.id, w.builder_name, w.id, int(w.days)], "ref": b.id}
	return {"ok": true, "msg": "%s gegründet (%s). Personal zuordnen (assign_staff), sonst ruht der Betrieb." % [b.name, b.id], "ref": b.id}


## Grundstuecke fuer ein Feld: das genannte oder freie Grundstuecke mit Strassenanschluss, Aecker bevorzugt ausserhalb von Wohn-
## und Mischgebiet, dann nach Preis je Feld.
## Region: Zielstadt einer Gruendung (Parameter "stadt" als ID oder Name, sonst Heimatstadt). -1 in der Einzelstadt.
func target_town(cid: int, params: Dictionary) -> int:
	if not sim.towns.is_region():
		return -1
	var want := str(params.get("stadt", ""))
	if want != "":
		if want.is_valid_int() and int(want) >= 0 and int(want) < sim.towns.count():
			return int(want)
		for t in sim.towns.list:
			if str(t.name).to_lower() == want.to_lower():
				return int(t.id)
	return int(sim.company(cid).home_town)


func _parcel_candidates(pid: String, min_area: int, need_power: bool = false) -> Array:
	if pid != "":
		var p: Dictionary = sim.parcels.parcel(pid)
		return [p] if not p.is_empty() and p.state == "frei" and Towns.is_public(str(p.owner)) and int(p.area) >= min_area and sim.parcels.is_buildable(p) else []
	var t: Dictionary = sim.city.building(import_point())
	var near := func(p) -> int: return absi(int(p.rect[0]) - int(t.x)) + absi(int(p.rect[1]) - int(t.y))
	var out: Array = sim.parcels.search({"min_area": min_area, "limit": 2000}).filter(func(p): return bool(sim.parcels.utilities_of(p).strasse) and p.zone not in ["wohnen", "mischgebiet"] 		and (not need_power or bool(p.get("erschliessung", {}).get("strom", true))))   # Stall/Betrieb mit Strombedarf braucht Anschluss
	# kurze Wege zur Muehle/Verladestelle zaehlen mehr als billiges Land am Rand (Fracht je dt sonst hoeher als der Ertrag)
	out.sort_custom(func(a, b): return near.call(a) < near.call(b))
	return out.slice(0, 40)


## Freie Parzellen mit Strassenzugang fuer einen marktnahen Betrieb, nach Abstand zum Hauptabnehmer (Standard: Lebensmittelgrosshandel).
func _market_candidates(min_area: int, near_to: int = -1) -> Array:
	var target: Dictionary = sim.city.building(near_to if near_to >= 0 else sim.retail.wholesale_building)
	var t := Vector2i(int(target.x), int(target.y))
	var out: Array = sim.parcels.search({"min_area": min_area, "limit": 2000}).filter(func(p): return bool(sim.parcels.utilities_of(p).strasse) 		and bool(p.get("erschliessung", {}).get("strom", true)))   # Strom fuer Muehle/Baeckerei (PowerGrid.connected)
	out.sort_custom(func(a, b): return absi(int(a.rect[0]) - t.x) + absi(int(a.rect[1]) - t.y) < absi(int(b.rect[0]) - t.x) + absi(int(b.rect[1]) - t.y))
	return out.slice(0, 40)


## Trockenlauf von _place_field: Gibt es auf der Parzelle eine Stelle fuer das Gebaeude mit Strassenzugang direkt daneben?
## Gleiche Pruefungen wie EventDirector._free/_add_building, ohne etwas zu belegen.
func placeable(p: Dictionary, btype: String) -> bool:
	var info: Array = CityGenerator.TYPES[btype]
	var w := int(info[1])
	var h := int(info[2])
	var c: CityData = sim.city
	var r0 := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
	for y in range(r0.position.y, r0.end.y - h + 1):
		for x in range(r0.position.x, r0.end.x - w + 1):
			var r := Rect2i(x, y, w, h)
			if not sim.events._free(r):
				continue
			var fits := true
			for yy in range(r.position.y, r.end.y):
				for xx in range(r.position.x, r.end.x):
					var q := Vector2i(xx, yy)
					if c.g(q) in [CityData.G.RAIL, CityData.G.RUNWAY] or (sim.access != null and sim.access.reserved(q)):
						fits = false
			if fits:
				return true
	return false


## Betriebsgebaeude (Kartenbild nach Branche, z. B. "farm" 3x3) an einer Stelle der Parzelle mit Strassenzugang.
func _place_field(p: Dictionary, name: String, btype: String = "farm") -> Dictionary:
	var info: Array = CityGenerator.TYPES[btype]
	var w := int(info[1])
	var h := int(info[2])
	var r0 := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
	for y in range(r0.position.y, r0.end.y - h + 1):
		for x in range(r0.position.x, r0.end.x - w + 1):
			var r := Rect2i(x, y, w, h)
			if not sim.events._free(r):
				continue
			var b: Dictionary = sim.events._add_building(btype, r, name)
			if not b.is_empty():
				sim.market.refresh()
				sim.events.buildings_added.emit([b.id])
				return b
	return {}


# ------------------------------------------------------------------ Tageslauf
func on_day(day: int) -> void:
	for b in sim.biz.items.values():
		var spec: Dictionary = sim.stages.spec_of(b)   # mit der Wirkung der Gebaeudestufe
		if not (spec.has("feld") or spec.has("rezept") or spec.has("laden") or spec.has("bau") or spec.has("abbau") or spec.has("dienste")) or b.status not in Businesses.RUNNING or sim.biz.frozen(int(b.owner)):
			continue
		_costs(b)
		if spec.has("bau") or spec.has("dienste"):
			_staff_ok(b, spec)
			continue   # Baufirma arbeitet im Bausystem (Construction), IT-Betrieb in ItServices
		b["sales_avg"] = float(b.get("sales_avg", 0.0)) * 0.7 + float(b.get("sold_today", 0)) * 0.3
		b["sold_today"] = 0
		if spec.has("feld"):
			_field_day(b, spec)
		elif spec.has("abbau"):
			_mine_day(b, spec)
		elif spec.has("rezept"):
			_recipe_day(b, spec)
		else:
			_kitchen_day(b, spec)
		_spoil(b, spec)
	_export_surplus()
	_advance_deals()


## Laufende Kosten je Betrieb: Abschreibung der Ausstattung, Pacht des Feldes (Kostenstelle des Betriebs).
func _costs(b: Dictionary) -> void:
	var c = sim.company(int(b.owner))
	var spec: Dictionary = Businesses.branches()[b.branch]
	var dep := minf(float(b.get("equip", 0.0)) * float(spec.get("abschreibung_tag", 0.0)), float(b.get("book", 0.0)))
	if dep > 0.0:
		b.book = float(b.book) - dep
		c.property_book = maxf(0.0, c.property_book - dep)
		c.ledger.book("depreciation", -dep, false, "Abschreibung %s" % b.name, sim.game_min, "", b.id)
	if float(b.get("lease_day", 0.0)) > 0.0:
		c.ledger.book("rent", -float(b.lease_day), true, "Pacht %s" % b.get("parcel", ""), sim.game_min, Towns.account_of(sim.towns.of_parcel(str(b.get("parcel", "")))), b.id)


func _staff_ok(b: Dictionary, spec: Dictionary) -> int:
	var n: int = sim.biz.staff_of(b.id).size()
	if n < int(spec.get("personal_min", 1)):
		sim.biz.block(b.id, "personal", "Kein Personal: mindestens %d Mitarbeiter zuordnen (assign_staff)" % int(spec.get("personal_min", 1)))
	else:
		sim.biz.unblock(b.id, "personal")
	return n


func _field_day(b: Dictionary, spec: Dictionary) -> void:
	var F: Dictionary = spec.feld
	var crop := str(F.get("artikel", "getreide"))   # Ernteartikel (Feld: Getreide, Forst: Holz)
	var seed := str(F.get("saat", seed))
	var f: Dictionary = b.field
	var cid := int(b.owner)
	var acct := "C%d" % cid
	var site := int(b.site)
	var staff := _staff_ok(b, spec)
	var days: Dictionary = F.tage
	match str(f.phase):
		"brache", "vorbereitung":
			_ensure_input(b, seed, _seed_need(b, F), _seed_need(b, F))
			if staff <= 0:
				return
			if f.phase == "brache":
				f.phase = "vorbereitung"
				f.day = 0
				sim.biz.note(b.id, "Feldvorbereitung begonnen", "Betrieb")
			f.day = int(f.day) + 1
			if int(f.day) >= int(days.vorbereitung):
				f.phase = "aussaat"
				f.day = 0
		"aussaat":
			var need := _seed_need(b, F)
			if sim.stock.available(seed, acct, site) < need:
				sim.biz.block(b.id, "material", "Wartet auf %s (%d nötig)" % [item_name(seed), need])
				_ensure_input(b, seed, need, need)
				return
			sim.biz.unblock(b.id, "material")
			if staff <= 0:
				return
			f.day = int(f.day) + 1
			if int(f.day) >= int(days.aussaat):
				_use(b, seed, need, acct, site)
				f.phase = "wachstum"
				f.day = 0
				f.growth = 0.0
				f.grow_days = 0
				sim.biz.note(b.id, "Aussaat abgeschlossen (%d × %s)" % [need, item_name(seed)], "Betrieb")
		"wachstum":
			var w := growth_factor()
			if staff <= 0:
				w *= float(F.ohne_pflege)   # ohne Pflege waechst weniger
			f.growth = float(f.growth) + w
			f.grow_days = int(f.grow_days) + 1
			f.day = int(f.day) + 1
			if int(f.day) >= int(days.wachstum):
				f.phase = "ernte"
				f.day = 0
		"ernte":
			if staff <= 0:
				return
			f.day = int(f.day) + 1
			if int(f.day) >= int(days.ernte):
				var avg := float(f.growth) / maxf(1.0, float(f.grow_days))
				var y := int(round(float(f.area) * float(F.ertrag_dt_je_feld) * avg))
				if y > 0:
					sim.stock.add(crop, y, acct, site, "Ernte %s" % b.id, sim.game_min)
					_count("produced", crop, y)
					_first_output(b)
				f.last_yield = y
				f.cycles = int(f.cycles) + 1
				f.phase = "brache"
				f.day = 0
				sim.biz.note(b.id, "Ernte: %d %s (Wachstum %.0f %%) liegen bereit zum Abtransport" % [y, item_name(crop), avg * 100.0], "Betrieb")
				sim.log_event("%s erntet %d × %s." % [b.name, y, item_name(crop)], "good", cid)


# ------------------------------------------------------------------ Lagerstaetten und Bergwerk
func deposit_of(pid: String) -> Dictionary:
	if _deposits.is_empty():
		_build_deposits()
	var d: Dictionary = _deposits.get(pid, {})
	if d.is_empty():
		return {}
	var out := d.duplicate()
	out.menge = maxi(0, int(d.menge) - int(mined.get(pid, 0)))
	return out


## Grundstuecke mit Lagerstaette (legt die Lagerstaetten bei Bedarf an).
func deposit_parcels() -> Array:
	if _deposits.is_empty():
		_build_deposits()
	return _deposits.keys()


func _build_deposits() -> void:
	var seed_v: int = int(sim.city.seed_value)
	var cands: Array = sim.parcels.items.values().filter(func(p): return (_near_mountain(p) if sim.city.coastal() else _outskirts(p)) 		and p.zone not in ["gruen", "korridor"] and sim.parcels.is_buildable(p) and int(p.area) >= 40 and p.state == "frei")
	for p in cands:
		var h := absi(hash([seed_v, p.id, "vorkommen"]))
		if float(h % 1000) / 1000.0 >= DEPOSIT_SHARE:
			continue
		_deposits[p.id] = {"art": DEPOSIT_KINDS[(h / 1000) % DEPOSIT_KINDS.size()], "menge": 3000 + (h / 7) % 9000, "qualitaet": snappedf(0.6 + float((h / 13) % 41) / 100.0, 0.01)}
	# Jeder Rohstoff mindestens einmal auf einer erreichbaren Parzelle am Stadtrand (die aeussersten zuerst)
	var coast: bool = sim.city.coastal()   # Kuestenort: Lagerstaetten duerfen abgelegen sein (Zufahrt per build_access)
	var reach: Array = cands if coast else cands.filter(func(p): return bool(sim.parcels.utilities_of(p).strasse))
	reach.sort_custom(func(a, b): return _center_dist(a) > _center_dist(b))
	for kind in DEPOSIT_KINDS:
		var have := false
		for k in _deposits:
			if _deposits[k].art == kind and (coast or bool(sim.parcels.utilities_of(sim.parcels.parcel(k)).strasse)):
				have = true
				break
		if have:
			continue
		for p in reach:
			if not _deposits.has(p.id):
				_deposits[p.id] = {"art": kind, "menge": 5000, "qualitaet": 0.8}
				break


## Kuestenort: Lagerstaetten liegen an den Bergraendern (Parzelle grenzt bis auf 2 Felder an ein Berggebiet).
func _near_mountain(p: Dictionary) -> bool:
	var h: PackedByteArray = sim.city.height
	if h.is_empty():
		return false
	for y in range(int(p.rect[1]) - 2, int(p.rect[1]) + int(p.rect[3]) + 2):
		for x in range(int(p.rect[0]) - 2, int(p.rect[0]) + int(p.rect[2]) + 2):
			var q := Vector2i(x, y)
			if sim.city.inside(q) and h[sim.city.idx(q)] > 0:
				return true
	return false


## Abstand des Parzellenmittelpunkts vom Kartenmittelpunkt (Felder, groesste Achse).
func _center_dist(p: Dictionary) -> float:
	var c := Vector2(float(p.rect[0]) + float(p.rect[2]) * 0.5, float(p.rect[1]) + float(p.rect[3]) * 0.5)
	var m := float(sim.city.size) * 0.5
	return maxf(absf(c.x - m), absf(c.y - m))


## Berge und Lagerstaetten nur im Aussenbereich (aeusserer Ring der Karte), nicht in der Stadt.
func _outskirts(p: Dictionary) -> bool:
	return _center_dist(p) >= float(sim.city.size) * 0.5 * OUTSKIRTS


# ------------------------------------------------------------------ Gelaende: Berge auf den Lagerstaetten (Abschnitt 5)
const MOUNTAIN_FROM := 3             # ab diesem Strassenabstand (Felder) beginnt der Berg
const YARD_RADIUS := 3               # Vorplatz fuer das Bergwerk an der strassennaechsten Stelle (Quadrat mit diesem Radius)
const MOUNTAIN_MAX := 11.0           # hoechste Stufe
const MOUNTAIN_MIN_CELLS := 6

## Bergmassive: Hoehe je Zelle waechst mit dem Abstand zur Strasse (plus Rauschen). Bergzellen sind nicht begehbar und tragen keine
## Baeume; die Parzelle wird Bergland (nicht mehr frei bebaubar). Deterministisch aus Stadtsamen und Parzelle, beim Laden neu erzeugt.
func _build_terrain() -> void:
	var city: CityData = sim.city
	var tree_cells := {}
	for pid in _deposits:
		var p: Dictionary = sim.parcels.parcel(pid)
		if p.is_empty() or p.state != "frei":
			continue
		var r := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		var roads: Array = []
		for y in range(r.position.y - 3, r.end.y + 3):
			for x in range(r.position.x - 3, r.end.x + 3):
				var q := Vector2i(x, y)
				if city.inside(q) and city.is_road(q):
					roads.append(q)
		if roads.is_empty():
			continue
		var cells := {}
		var dist := {}
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := Vector2i(x, y)
				if city.building_at[city.idx(c)] >= 0 or city.is_road(c) or city.g(c) == CityData.G.WATER:
					continue
				var d := 999
				for q in roads:
					d = mini(d, absi(q.x - c.x) + absi(q.y - c.y))
				if d < MOUNTAIN_FROM:
					continue
				cells[c] = 1.0
				dist[c] = d
		# Vorplatz: an der strassennaechsten Stelle (nahe der Parzellenmitte) bleibt Platz fuer Foerderanlage und Halde
		var entry := Vector2i(-1, -1)
		var best := INF
		var mid := Vector2(r.position) + Vector2(r.size) * 0.5
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := Vector2i(x, y)
				var d := 999
				for q in roads:
					d = mini(d, absi(q.x - c.x) + absi(q.y - c.y))
				var sc := float(d) * 10.0 + Vector2(c).distance_to(mid)
				if sc < best:
					best = sc
					entry = c
		for c in cells.keys():
			if absi(c.x - entry.x) <= YARD_RADIUS and absi(c.y - entry.y) <= YARD_RADIUS:
				cells.erase(c)
				dist.erase(c)
		if cells.size() < MOUNTAIN_MIN_CELLS:
			continue
		# Gipfelform: Hoehe waechst mit dem Abstand zum Bergrand (naechste Zelle ohne Berg), dazu Rauschen
		for c in cells.keys():
			var edge := 99
			for rr in range(1, 12):
				var hit := false
				for k in [Vector2i(rr, 0), Vector2i(-rr, 0), Vector2i(0, rr), Vector2i(0, -rr)]:
					if not cells.has(c + k):
						hit = true
						break
				if hit:
					edge = rr
					break
			var n := float(absi(hash([city.seed_value, pid, c])) % 100) / 100.0
			cells[c] = clampf(float(edge) * 2.4 - 0.8 + n * 1.6, 1.0, MOUNTAIN_MAX)
		# Abbaufront beginnt am Vorplatz (Foerderhaus) und frisst sich von dort in den Berg
		var order: Array = cells.keys()
		order.sort_custom(func(a, b): return [absi(a.x - entry.x) + absi(a.y - entry.y), -(a.x + a.y)] < [absi(b.x - entry.x) + absi(b.y - entry.y), -(b.x + b.y)])
		terrain[pid] = {"cells": cells, "order": order, "art": _deposits[pid].art, "start": int(_deposits[pid].menge)}
		p.state = "privat_gehalten"
		p.use = "berg"
		for c in cells:
			city.blocked[city.idx(c)] = 1
			sim.nav.walk.set_point_solid(c, true)
			tree_cells[c] = true
	if not tree_cells.is_empty():
		city.trees = city.trees.filter(func(t): return not tree_cells.has(t[0]))


## Abgebauter Anteil eines Bergs (0..1) und Zellen, die als Grube erscheinen (von der Abbaufront her).
func excavated(pid: String) -> Dictionary:
	var t: Dictionary = terrain.get(pid, {})
	if t.is_empty():
		return {}
	var f := clampf(float(mined.get(pid, 0)) / maxf(1.0, float(t.start)), 0.0, 1.0)
	var n := int(ceil(f * float(t.order.size()) * 1.2)) if f > 0.0 else 0
	var pit := {}
	for c in t.order.slice(0, mini(n, t.order.size())):
		pit[c] = true
	return {"anteil": f, "grube": pit}


## Bergwerk auf einer Parzelle (oder leeres Dictionary).
func mine_on(pid: String) -> Dictionary:
	for b in sim.biz.items.values():
		if b.branch == "bergwerk" and str(b.get("parcel", "")) == pid and b.status not in ["geschlossen"]:
			return b
	return {}


## Beste freie Lagerstaette (Art optional; ein Grundstueck "G<n>" optional): viel Vorrat x Qualitaet je Kaufpreis, mit Strassen- und Stromanschluss.
func best_deposit(kind: String, pid: String = "") -> Dictionary:
	if _deposits.is_empty():
		_build_deposits()
	var best := {}
	var best_s := -1.0
	for id in _deposits:
		if pid != "" and id != pid:
			continue
		var p: Dictionary = sim.parcels.parcel(id)
		var d := deposit_of(id)
		var free_land: bool = p.get("state", "") == "frei" or (p.get("state", "") == "privat_gehalten" and str(p.get("use", "")) == "berg")
		if p.is_empty() or not free_land or not Towns.is_public(str(p.owner)) or int(d.menge) <= 0 or (kind != "" and d.art != kind):
			continue
		if not bool(sim.parcels.utilities_of(p).strasse):
			continue
		var sc := float(d.menge) * float(d.qualitaet) / maxf(1.0, float(p.price))
		if sc > best_s:
			best_s = sc
			best = {"grundstueck": id, "art": d.art, "menge": d.menge, "qualitaet": d.qualitaet, "preis": int(p.price)}
	return best


## Guenstigste freie Lagerstaette ohne Strassenanschluss, zu der eine Zufahrt ueber Land moeglich ist (Kuestenort, Etappe B).
## {grundstueck, art, kosten, tage} oder {}; Zufahrten im Bau zaehlen als schon beauftragt.
func remote_deposit(kind: String) -> Dictionary:
	if _deposits.is_empty():
		_build_deposits()
	var best := {}
	for id in _deposits:
		var p: Dictionary = sim.parcels.parcel(id)
		var d := deposit_of(id)
		if p.is_empty() or p.get("state", "") != "frei" or not Towns.is_public(str(p.owner)) or int(d.menge) <= 0 or (kind != "" and d.art != kind):
			continue
		if bool(sim.parcels.utilities_of(p).strasse) or sim.access.jobs.values().any(func(j): return j.parcel == id and j.status in ["antrag", "im_bau"]):
			continue
		var pl: Dictionary = sim.access.plan(id)
		if pl.ok and (best.is_empty() or float(pl.kosten) < float(best.kosten)):
			best = {"grundstueck": id, "art": d.art, "kosten": int(pl.kosten), "tage": int(pl.tage)}
	return best


## Foerderung: Personal x je_person_tag x Qualitaet, begrenzt durch Restvorrat, Ausgangslager und Strom.
func _mine_day(b: Dictionary, spec: Dictionary) -> void:
	var A: Dictionary = spec.abbau
	var acct := "C%d" % int(b.owner)
	var site := int(b.site)
	var staff := _staff_ok(b, spec)
	var item := str(b.deposit.art)
	b["today"] = 0
	if staff < int(spec.personal_min):
		return
	sim.company(int(b.owner)).ledger.book("supplies", -float(A.get("diesel_tag", 0.0)), true, "Diesel %s" % b.id, sim.game_min, "S0", b.id)
	if float(b.energy_kw) > 0.0 and not sim.grid.supplied.has(b.id):
		return
	var left: int = int(deposit_of(str(b.parcel)).get("menge", 0))
	if left <= 0:
		sim.biz.block(b.id, "material", "Lagerstätte erschöpft")
		return
	var room: int = int(A.lager_max) - sim.stock.qty(item, acct, site)
	var q := mini(mini(int(round(float(staff * int(A.je_person_tag)) * float(b.deposit.qualitaet))), left), room)
	if q <= 0:
		sim.biz.block(b.id, "material", "Lager voll: %s wird nicht abgeholt" % item_name(item))
		return
	sim.biz.unblock(b.id, "material")
	mined[str(b.parcel)] = int(mined.get(str(b.parcel), 0)) + q
	sim.stock.add(item, q, acct, site, "Förderung %s" % b.id, sim.game_min)
	sim.mining.royalty(b, item, q)   # Foerderabgabe an die Stadtkasse
	_count("produced", item, q)
	_first_output(b)
	b.today = q
	b["total"] = int(b.get("total", 0)) + q
	# Sprengung etwa jeden dritten Foerdertag: sichtbar am Berg und im Protokoll
	var day := GameCalendar.day_of(sim.game_min)
	if absi(hash([b.id, day])) % 3 == 0:
		blasts[b.id] = sim.game_min
		var cell: Vector2i = terrain.get(str(b.parcel), {}).get("order", [sim.city.building(site).road])[0] if terrain.has(str(b.parcel)) else sim.city.building(site).road
		sim.activity.add(b.name, int(b.owner), "sonstiges", "Sprengung: %s gelöst" % item_name(item), "Abbaufront im %s" % b.name, cell, "Betrieb")
		sim.log_event("Sprengung im %s – %d Einheiten %s gefördert." % [b.name, q, item_name(item)], "info", int(b.owner))


func _seed_need(b: Dictionary, F: Dictionary) -> int:
	return maxi(1, int(ceil(float(b.field.area) / 10.0 * float(F.saatgut_je_10_felder))))


## Wachstum je Tag aus dem Wetter: Regen hilft, Hitze und Frost bremsen.
func growth_factor() -> float:
	var wx = sim.wx
	if wx.is_snow() or wx.is_icy() or wx.is_cold():
		return 0.4
	if wx.is_hot():
		return 0.7
	if wx.is_heavy_rain():
		return 0.9
	if wx.is_rain():
		return 1.1
	return 1.0


func _recipe_day(b: Dictionary, spec: Dictionary) -> void:
	var R: Dictionary = spec.rezept
	var cid := int(b.owner)
	var acct := "C%d" % cid
	var site := int(b.site)
	var staff := _staff_ok(b, spec)
	var today := GameCalendar.day_of(sim.game_min)
	if R.has("mast_tage"):   # fertig gemaestete Tiere verlassen den Stall
		var keep: Array = []
		for m in b.get("pipeline", []):
			if int(m.due) <= today:
				var nq := int(m.n) * int(R.aus.values()[0])
				sim.stock.add(str(R.aus.keys()[0]), nq, acct, site, "Mast %s" % b.id, sim.game_min)
				_count("produced", str(R.aus.keys()[0]), nq)
				_first_output(b)
			else:
				keep.append(m)
		b["pipeline"] = keep
	# Theke (Laden): oeffnet, wenn ueber dem Mindestpersonal eine Verkaufskraft da ist; diese backt dann nicht mit
	var shop: Dictionary = spec.get("laden", {})
	b["counter"] = not shop.is_empty() and staff >= int(spec.get("personal_min", 1)) + int(shop.personal)
	var cap := (staff - (int(shop.personal) if b.counter else 0)) * int(R.chargen_je_person_tag)
	# Verderbliche Ware nach Absatz: Zielbestand = 1,5 Tagesabsaetze (mindestens START_BATCHES Chargen zum Anlaufen);
	# Einkauf und Produktion richten sich danach statt nach der vollen Kapazitaet.
	var out_cap := -1
	var plan := maxi(cap, int(R.chargen_je_person_tag))
	var start := START_BATCHES if bool(b.counter) else int(R.chargen_je_person_tag)   # ohne Theke: Lose fuer Laeden muessen die Fracht tragen
	for item in R.aus:
		if int(art(item).get("haltbar_tage", 0)) > 0:
			var per_batch := int(R.aus[item])
			var target := maxf(float(b.get("sales_avg", 0.0)) * 1.5, float(per_batch * start))
			out_cap = maxi(0, int(ceil((target - float(sim.stock.qty(item, acct, site))) / float(per_batch))))
			plan = mini(plan, maxi(1, int(ceil(maxf(float(b.get("sales_avg", 0.0)), float(per_batch * start)) / float(per_batch)))))
	# Ausgangslager fast voll: keine Rohware nachkaufen, bis wieder Ware abfliesst
	for item in R.aus:
		if sim.stock.qty(item, acct, site) >= int(R.lager_max) * 4 / 5:
			plan = 0
	# Beschaffung fuer die naechsten Tage (auch ohne Personal, damit der Betrieb anlaufen kann)
	for item in R.ein:
		var per_day := plan * int(R.ein[item])
		if per_day > 0:
			_ensure_input(b, item, per_day * int(R.lager_tage), per_day * int(R.lager_tage) / 2, _input_cap(b, R, acct, site))
	b["today"] = 0
	if staff <= 0:
		return
	if float(b.energy_kw) > 0.0 and not sim.grid.supplied.has(b.id):
		return   # Blockade "strom" setzt PowerGrid mit konkretem Grund
	var batches := cap if out_cap < 0 else mini(cap, out_cap)
	if R.has("plaetze"):   # Stallplaetze: Tiere in der Mast und fertige Tiere im Stall
		var used := 0
		for m in b.get("pipeline", []):
			used += int(m.n)
		used += sim.stock.qty(str(R.aus.keys()[0]), acct, site)
		# nach Absatz einstallen: hoechstens 1,2 x gleitender Tagesabsatz, mindestens ein Tier je Tag
		batches = mini(batches, maxi(1, int(ceil(float(b.get("sales_avg", 0.0)) * 1.2))))
		if used >= int(R.plaetze):
			sim.biz.block(b.id, "material", "Stall voll (%d Plätze belegt)" % used)
			return
		batches = mini(batches, int(R.plaetze) - used)
	var short := ""
	if out_cap == 0:
		sim.biz.unblock(b.id, "material")
		return   # genug verderbliche Ware auf Lager fuer den erwarteten Absatz
	for item in R.ein:
		var n: int = sim.stock.available(item, acct, site) / int(R.ein[item])
		if n < batches:
			batches = n
			short = item
	for item in R.aus:
		var room: int = (int(R.lager_max) - sim.stock.qty(item, acct, site)) / int(R.aus[item])
		if room < batches or (batches == 0 and room < int(R.chargen_je_person_tag)):   # volles Lager ist dann der eigentliche Grund
			batches = maxi(0, mini(batches, room))
			short = "lager:" + item
	if batches <= 0:
		if short.begins_with("lager:"):
			sim.biz.block(b.id, "material", "Lager voll: %s wird nicht abgeholt" % item_name(short.trim_prefix("lager:")))
		else:
			sim.biz.block(b.id, "material", "Wartet auf %s" % item_name(short))
			b["waiting_for"] = short
		return
	sim.biz.unblock(b.id, "material")
	b.erase("waiting_for")
	for item in R.ein:
		_use(b, item, batches * int(R.ein[item]), acct, site)
	if R.has("mast_tage"):
		b.pipeline.append({"due": today + int(R.mast_tage), "n": batches})
		sim.biz.note(b.id, "%d Tiere eingestallt, fertig an Tag %d" % [batches, today + int(R.mast_tage)], "Betrieb")
	else:
		for item in R.aus:
			var q := batches * int(R.aus[item])
			sim.stock.add(item, q, acct, site, "Produktion %s" % b.id, sim.game_min)
			_count("produced", item, q)
			_first_output(b)
	b.today = batches
	b["total"] = int(b.get("total", 0)) + batches


## Hoechster sinnvoller Einkaufspreis je Einheit der (einzigen) Rohware: Erloes der Ausgangsware je Einheit Rohware x 0,9.
## Liegt das Ausgangslager halb voll (Absatz stockt, Ueberschuss geht in die Ausfuhr), zaehlt der Exportpreis. Bei mehreren
## Rohwaren (Baeckerei) keine Grenze.
func _input_cap(b: Dictionary, R: Dictionary, acct: String, site: int) -> float:
	if R.ein.size() != 1:
		return INF
	var in_qty := float(R.ein.values()[0])
	var value := 0.0
	for item in R.aus:
		var p := price_of(b, item)
		var ep = art(item).get("exportpreis")
		if ep != null and sim.stock.qty(item, acct, site) >= int(R.lager_max) / 2:
			p = float(ep)
		value += p * float(R.aus[item])
	return value / in_qty * 0.9


func _use(b: Dictionary, item: String, qty: int, acct: String, site: int) -> void:
	var n: int = sim.stock.consume(item, qty, acct, site, "Verbrauch %s" % b.id, sim.game_min)
	_count("consumed", item, n)


func _spoil(b: Dictionary, spec: Dictionary) -> void:
	var out: Array = spec.get("rezept", {}).get("aus", {}).keys()
	if spec.get("laden", {}).get("gerichte", false):
		out = kitchen_items()
	for item in out:
		if int(art(item).get("haltbar_tage", 0)) <= 0:
			continue
		var acct := "C%d" % int(b.owner)
		var rate: float = minf(SPOIL_SHARE, 0.75 / float(art(item).haltbar_tage)) * sim.it.spoil_factor(b.id)   # Brot (3 Tage) 25 %, Gemuese 15 %; IT-Lagerverwaltung senkt
		if bool(art(item).get("kuehlung", false)):   # Kuehlraum: mit Strom langsam, ohne Strom schnell (Kuehlkette)
			var cold: bool = sim.grid.supplied.has(b.id)
			rate = (COLD_SPOIL if cold else WARM_SPOIL) * sim.it.spoil_factor(b.id)
			if not cold and sim.stock.qty(item, acct, int(b.site)) > 0:
				sim.biz.block(b.id, "kuehlung", "Kühlraum ohne Strom: %s verdirbt" % item_name(item))
			else:
				sim.biz.unblock(b.id, "kuehlung")
		var n := int(floor(float(sim.stock.available(item, acct, int(b.site))) * rate))
		if n > 0:
			sim.stock.consume(item, n, acct, int(b.site), "Verdorben %s" % b.id, sim.game_min)
			stats.spoiled = int(stats.spoiled) + n


# ------------------------------------------------------------------ Kueche (Restaurant)
## Zutaten der Gerichte des Restaurants (Retail.KINDS.restaurant).
static func kitchen_items() -> Array:
	return Retail.KINDS.restaurant.goods.duplicate()


## Erwarteter Tagesverbrauch einer Zutat bei `guests` Gaesten (Gerichte gleich verteilt, wie in Retail._kitchen_use).
static func kitchen_use(item: String, guests: float) -> float:
	var dishes: Array = Retail.KINDS.restaurant.dishes
	var per := 0.0
	for dn in dishes:
		per += float(Retail.DISHES[dn].uses.get(item, 0))
	return per / float(dishes.size()) * guests


## Restaurant: Theke (Service) nur mit Servicekraft ueber der Kueche; Zutaten nach erwarteter Gaestezahl (gleitender Durchschnitt).
func _kitchen_day(b: Dictionary, spec: Dictionary) -> void:
	var L: Dictionary = spec.laden
	var staff := _staff_ok(b, spec)
	b["counter"] = staff >= int(spec.get("personal_min", 1)) + int(L.personal) and (float(b.energy_kw) <= 0.0 or sim.grid.supplied.has(b.id))
	b["guests_avg"] = float(b.get("guests_avg", float(L.start_gaeste))) * 0.7 + float(b.get("counter_customers", L.start_gaeste)) * 0.3
	for item in kitchen_items():
		var per_day := maxf(1.0, kitchen_use(item, float(b.guests_avg)))
		_ensure_input(b, item, int(ceil(per_day * float(L.lager_tage))), int(ceil(per_day * float(L.lager_tage) / 2.0)))


func _count(key: String, item: String, n: int) -> void:
	stats[key][item] = int(stats[key].get(item, 0)) + n


## Erste eigene Herstellung eines Betriebs (Ernte, Charge, Mastende) fuer die Rueckzugsregel der KI.
func _first_output(b: Dictionary) -> void:
	if not b.has("first_output_day"):
		b["first_output_day"] = GameCalendar.day_of(sim.game_min)


# ------------------------------------------------------------------ Beschaffung
## Bestand + Unterwegs unter `reorder` -> bis `target` nachbestellen.
func _ensure_input(b: Dictionary, item: String, target: int, reorder: int, max_unit: float = INF) -> void:
	var acct := "C%d" % int(b.owner)
	var have: int = sim.stock.available(item, acct, int(b.site)) + incoming(acct, item, int(b.site))
	if have > reorder and have > 0:
		return
	var want := target - have
	if want <= 0:
		return
	var got := order(acct, int(b.site), b.id, item, want, max_unit, true)
	if got <= 0:
		b["waiting_for"] = item   # Engpass fuer die Kettenlage (Regel-KI gruendet die fehlende Vorstufe)
	if got <= 0 and max_unit < INF:
		sim.biz.block(b.id, "einkauf", "Kein Einkauf von %s unter %s je %s (sonst Verlust)" % [item_name(item), Catalog.money(max_unit), art(item).get("einheit", "Stk")])
	elif got <= 0:
		sim.biz.block(b.id, "einkauf", "Kein Einkauf von %s möglich (Bargeld oder Anbieter fehlt)" % item_name(item))
	else:
		sim.biz.unblock(b.id, "einkauf")


func incoming(buyer: String, item: String, loc: int) -> int:
	var n := 0
	for d in deals.values():
		if d.buyer == buyer and d.item == item and int(d.buyer_loc) == loc and d.status in ["transport", "unterwegs"]:
			n += int(d.qty)
	return n


## Anbieter fuer einen Artikel: laufende Betriebe, deren Ausgang (Rezept/Ernte) der Artikel ist, mit freiem Bestand am Standort.
func sellers(item: String) -> Array:
	var out: Array = []
	for b in sim.biz.items.values():
		if b.status not in Businesses.RUNNING or sim.biz.frozen(int(b.owner)):
			continue
		var spec: Dictionary = Businesses.branches().get(b.branch, {})
		var makes: bool = spec.get("rezept", {}).get("aus", {}).has(item) or (spec.has("feld") and str(spec.feld.get("artikel", "getreide")) == item) or (spec.has("abbau") and str(b.get("deposit", {}).get("art", "")) == item)
		if not makes:
			continue
		var acct := "C%d" % int(b.owner)
		var avail: int = sim.stock.available(item, acct, int(b.site))
		if avail > 0:
			out.append({"biz": b.id, "acct": acct, "cid": int(b.owner), "loc": int(b.site), "avail": avail, "price": price_of(b, item)})
	return out


func price_of(b: Dictionary, item: String) -> float:
	return float(b.get("prices", {}).get(item, art(item).get("basispreis", 0.0)))


func set_price(cid: int, bid: String, item: String, price: float) -> Dictionary:
	var b: Dictionary = sim.biz.get_b(bid)
	if b.is_empty() or int(b.owner) != cid:
		return {"ok": false, "msg": "Betrieb %s gehört dir nicht." % bid}
	if art(item).is_empty() or price <= 0.0:
		return {"ok": false, "msg": "Unbekannter Artikel oder Preis <= 0."}
	if not b.has("prices"):
		b["prices"] = {}
	b.prices[item] = snappedf(price, 0.01)
	b["price_day"] = GameCalendar.day_of(sim.game_min)
	sim.biz.note(bid, "Preis %s: %s" % [item_name(item), Catalog.money(price)], "Unternehmer")
	return {"ok": true, "msg": "Preis für %s auf %s je %s gesetzt." % [item_name(item), Catalog.money(price), art(item).einheit]}


func freight(from_loc: int, to_loc: int, item: String, qty: int) -> float:
	var a: Dictionary = sim.city.building(from_loc)
	var z: Dictionary = sim.city.building(to_loc)
	var dist: int = absi(a.road.x - z.road.x) + absi(a.road.y - z.road.y)
	if item in BULK:
		return freight_dist(dist, item, qty)
	# Einheitlicher Stadtliefertarif wie beim Grosshandel (Retail._freight): kurze Stadtfahrten uebernehmen Transportfirmen kaum
	# (Messung probe_bottlenecks: 0-2 von ueber 100), sonst der Lieferdienst; Erzeuger und Grosshandel liefern zu gleichen Bedingungen.
	return snappedf(Retail.FREIGHT_BASE + float(dist) * (1.0 + float(units(item, qty)) / 8.0), 1.0)


## Massengut (Rohstoffe der Schwerindustrie): Kipper/Ganzzug statt Stadtlieferdienst - je Ladeeinheit und Feld deutlich guenstiger,
## sonst kostete Erz ueber 380 Felder rund 10 EUR Fracht je Einheit (mehr als der Erzpreis) und das Stahlwerk kaufte Import.
const BULK := ["eisenerz", "kohle", "kalkstein", "rohmaterial", "koks", "schlacke"]
func freight_dist(dist: int, item: String, qty: int) -> float:
	if item in BULK:
		return snappedf(Retail.FREIGHT_BASE + float(dist) * (0.3 + float(units(item, qty)) / 30.0), 1.0)
	return snappedf(Retail.FREIGHT_BASE + float(dist) * (1.0 + float(units(item, qty)) / 8.0), 1.0)


## Fracht fuer eine Lieferung (alle Quellen zu gleichen Bedingungen, siehe freight).
func _freight_from(_src_acct: String, from_loc: int, to_loc: int, item: String, qty: int) -> float:
	return freight(from_loc, to_loc, item, qty)


func units(item: String, qty: int) -> int:
	return maxi(1, int(ceil(float(qty) / float(art(item).get("je_ladeeinheit", 1)))))


## Bestellung des Kaeufers (Konto "C<n>" oder "W0") am Standort loc: guenstigste Quellen zuerst (Preis + Fracht je Stueck, eigene Ware
## anderer Standorte ohne Warenpreis), Rest als Import, solange `allow_import`. max_unit begrenzt den Stueckpreis inkl. Fracht.
## Gibt die bestellte Menge zurueck.
func order(buyer: String, loc: int, buyer_biz: String, item: String, qty: int, max_unit: float, allow_import: bool) -> int:
	var cands: Array = []
	for s in sellers(item):
		if s.acct == buyer and int(s.loc) == loc:
			continue
		var q := mini(qty, int(s.avail))
		var own: bool = s.acct == buyer
		var unit := (0.0 if own else float(s.price)) + freight(int(s.loc), loc, item, q) / float(q)
		cands.append({"s": s, "unit": unit, "q": q, "own": own})
	var ip = art(item).get("importpreis")
	var port := import_point(loc)   # Import nur ueber den Hafen der eigenen Stadt; Lieferanten anderer Staedte stehen oben in sellers (Binnenhandel)
	var H := port_of(loc)
	if allow_import and ip != null and port >= 0 and port != loc:
		var avail := qty
		if H.enabled:   # Kuestenort: nur was das Schiff gebracht hat; die Fehlmenge bringt das naechste Schiff
			avail = H.available(item)
			if avail < qty:
				H.demand(item, qty - avail)
		cands.append({"s": {"biz": "", "acct": IMPORT, "cid": -1, "loc": port, "avail": avail, "price": float(ip)}, "unit": float(ip) + _freight_from(IMPORT, port, loc, item, qty) / float(qty), "q": qty, "own": false})
	cands.sort_custom(func(a, b2): return float(a.unit) < float(b2.unit))
	var left := qty
	for cd in cands:
		if left <= 0:
			break
		if float(cd.unit) > max_unit:
			break
		var q := mini(left, int(cd.s.avail))
		if q <= 0:
			continue
		var s: Dictionary = cd.s
		var price := 0.0 if bool(cd.own) else float(s.price)
		var fr := _freight_from(str(s.acct), int(s.loc), loc, item, q)
		# Liquiditaet des Kaeufers (Ware + Fracht werden bei Anlieferung faellig)
		var cash := _cash(buyer)
		while q > 0 and float(q) * price + fr > cash:
			q = q / 2
			fr = _freight_from(str(s.acct), int(s.loc), loc, item, maxi(1, q))
		if q <= 0:
			continue
		if _deal(buyer, loc, buyer_biz, s, item, q, price, fr):
			left -= q
	return qty - left


## Importware (Saatgut, Getreide, Mehl, Backzutaten) wird ueber das Lager des Lebensmittelgrosshandels bezogen.
func import_point(loc: int = -1) -> int:
	var H := port_of(loc)
	return H.building if H.enabled else int(sim.retail.wholesale_building)   # Kuestenort: Hafenlager (Region: der eigenen Stadt)


## Hafen der Stadt, in der ein Standort liegt (Region); sonst der eine Hafen.
func port_of(loc: int) -> Harbor:
	return sim.towns.harbor(sim.towns.of_building(loc)) if loc >= 0 and sim.towns.is_region() else sim.harbor


## Zahlungsfaehigkeit eines Kaeufers. Das Ausland (X0) ist eine Gegenbuchung ohne Kassenlimit: sein Saldo ist meist negativ,
## eine Begrenzung darauf wuerde jede Ausfuhr mit 0 EUR bezahlen.
func _cash(acct: String) -> float:
	if acct == IMPORT:
		return INF
	if acct.begins_with("C"):
		return sim.company(int(acct.substr(1))).ledger.cash
	return maxf(0.0, float(sim.economy.accounts.get(acct, 0.0)))


func _deal(buyer: String, loc: int, buyer_biz: String, s: Dictionary, item: String, q: int, price: float, fr: float) -> bool:
	var id := "D%d" % _next
	_next += 1
	var ref := "deal:" + id
	if s.acct == IMPORT:
		if not port_of(int(s.loc)).enabled:   # Kuestenort: die Ware liegt schon (per Schiff) im Hafenlager
			sim.stock.add(item, q, IMPORT, int(s.loc), "Import %s" % id, sim.game_min)
		_count("imported", item, q)
	if not sim.stock.reserve(ref, item, q, s.acct, int(s.loc)):
		return false
	var d := {"id": id, "item": item, "qty": q, "unit": price, "freight": fr, "seller": s.acct, "seller_biz": s.biz, "seller_loc": int(s.loc),
		"buyer": buyer, "buyer_biz": buyer_biz, "buyer_loc": loc, "status": "transport", "contract": "", "reissued": 0, "day": GameCalendar.day_of(sim.game_min)}
	deals[id] = d
	stats.deals = int(stats.deals) + 1
	_issue_contract(d)
	if s.biz != "":
		sim.biz.note(s.biz, "Verkauf %s: %d × %s an %s" % [id, q, item_name(item), _who(buyer)], "Betrieb")
	if buyer_biz != "":
		sim.biz.note(buyer_biz, "Einkauf %s: %d × %s bei %s (%s/Stk + Fracht %s)" % [id, q, item_name(item), _who(s.acct), Catalog.money(price), Catalog.money(fr)], "Betrieb")
	return true


func _who(acct: String) -> String:
	if acct == IMPORT:
		return "Import"
	if acct == "W0":
		return "Lebensmittelgroßhandel"
	if sim.retail.shops.has(acct):
		return str(sim.retail.shops[acct].name)
	if acct.begins_with("C"):
		return sim.company(int(acct.substr(1))).company_name
	return acct


func _issue_contract(d: Dictionary) -> void:
	var src: Dictionary = sim.city.building(int(d.seller_loc))
	var dst: Dictionary = sim.city.building(int(d.buyer_loc))
	var k := Contract.new()
	k.id = "A%d" % sim.market.next_id
	sim.market.next_id += 1
	k.pickup = int(d.seller_loc)
	k.dropoff = int(d.buyer_loc)
	k.cargo = str(art(d.item).get("ladung", "pakete"))
	k.label = "%d × %s (%s → %s)" % [int(d.qty), item_name(d.item), _who(d.seller), _who(d.buyer)]
	k.qty = units(d.item, int(d.qty))
	k.reward = float(d.freight)
	k.status = "open"
	var payer := str(d.get("payer", d.buyer))
	k.payer = ("firm:" + payer.substr(1)) if payer.begins_with("C") else payer
	k.order_ref = "deal:" + str(d.id)
	k.created = sim.game_min
	k.offer_until = sim.game_min + GameCalendar.days_to_min(float(OFFER_DAYS))
	k.distance = absi(src.road.x - dst.road.x) + absi(src.road.y - dst.road.y)
	# Frist wie auf dem Transportmarkt: Fahrzeit x Puffer + Anfahrt/Laden, gerechnet ab Ende der Ausschreibung
	k.deadline = k.offer_until + float(k.distance) / 2.2 * Catalog.GAME_MIN_PER_SIM_SEC * 3.0 + 240.0
	k.needs_cold = bool(Catalog.CARGO[k.cargo].refrigerated)
	sim.contracts[k.id] = k
	d.contract = k.id
	d.status = "transport"


func _advance_deals() -> void:
	for d in deals.values():
		if d.status not in ["transport", "unterwegs"]:
			continue
		var k: Contract = sim.contracts.get(str(d.contract))
		if k != null and k.status in ["accepted", "assigned", "loading", "in_transit"]:
			d.status = "unterwegs"
			continue
		if k != null and (k.status == "delivered" or (k.status == "open" and sim.game_min <= k.offer_until)):
			continue
		if k != null and k.status == "failed" and int(d.reissued) < 1:   # Transporteur gescheitert: einmal neu ausschreiben
			d.reissued = int(d.reissued) + 1
			_issue_contract(d)
			continue
		_fallback(d, k)   # niemand hat die Ausschreibung angenommen: Lieferdienst (keine zweite Runde, Ware ist oft verderblich)
	_prune()


## Lieferdienst (S0), wenn kein Unternehmen den Transport uebernommen hat: Kaeufer zahlt einen Teil der Fracht, Ware kommt an.
func _fallback(d: Dictionary, k: Contract) -> void:
	var pa := str(d.get("payer", d.buyer))
	var pay := minf(float(d.freight) * FALLBACK_SHARE, maxf(0.0, _cash(pa)))
	_pay(pa, "S0", pay, "trade_expense", "Lieferdienst %s" % d.id, str(d.get("payer_biz", d.buyer_biz)))
	d.freight_paid = pay
	stats.fallback = int(stats.fallback) + 1
	if k != null and k.status in ["open", "expired"]:
		k.status = "cancelled"
	_receive(d)


## Vom Simulationskern nach der Ablieferung durch ein Unternehmen (die Fracht ist dort bereits als Umsatz des Transporteurs gebucht).
func contract_delivered(k: Contract) -> void:
	var d: Dictionary = deals.get(k.order_ref.trim_prefix("deal:"), {})
	if d.is_empty() or d.status not in ["transport", "unterwegs"]:
		return
	var pa := str(d.get("payer", d.buyer))
	if pa.begins_with("C") and k.paid > 0.0:
		var payer = sim.company(int(pa.substr(1)))
		payer.ledger.book("trade_expense", -k.paid, true, "Fracht %s" % d.id, sim.game_min, "C0", str(d.get("payer_biz", d.buyer_biz)))
	d.freight_paid = k.paid
	_receive(d)


## Eigentumsuebergang am Ziel und Bezahlung der Ware (nur zwischen verschiedenen Eigentuemern).
func _receive(d: Dictionary) -> void:
	var moved: int = sim.stock.move_reserved("deal:" + str(d.id), d.buyer, int(d.buyer_loc), "Anlieferung %s" % d.id, sim.game_min)
	var amount := float(moved) * float(d.unit)
	if d.seller != d.buyer and amount > 0.0:
		amount = minf(amount, maxf(0.0, _cash(d.buyer)))
		if d.seller.begins_with("C"):
			var seller = sim.company(int(d.seller.substr(1)))
			if d.buyer.begins_with("C"):
				sim.company(int(d.buyer.substr(1))).ledger.book("trade_expense", -amount, true, "Einkauf %s" % d.id, sim.game_min, "C0", d.buyer_biz)
				seller.ledger.book("trade_income", amount, true, "Verkauf %s" % d.id, sim.game_min, "C0", d.seller_biz)
			else:
				seller.ledger.book("trade_income", amount, true, "Verkauf %s an %s" % [d.id, _who(d.buyer)], sim.game_min, d.buyer, d.seller_biz)
			stats.sold = float(stats.sold) + amount
		else:
			_pay(d.buyer, d.seller, amount, "trade_expense", "Einkauf %s (%s)" % [d.id, _who(d.seller)], d.buyer_biz)
	elif d.seller == d.buyer and d.seller_biz != "" and d.buyer_biz != "" and moved > 0:
		# Interne Lieferung: Verrechnungspreis zwischen den Kostenstellen (ohne Bargeld, kein Umsatz; konsolidiert null)
		var tp := float(moved) * price_of(sim.biz.get_b(d.seller_biz), d.item)
		var L: Ledger = sim.company(int(d.seller.substr(1))).ledger
		L.book("internal", tp, false, "Interne Lieferung %s" % d.id, sim.game_min, "", d.seller_biz)
		L.book("internal", -tp, false, "Interne Lieferung %s" % d.id, sim.game_min, "", d.buyer_biz)
	if d.buyer == IMPORT and moved > 0:
		if port_of(int(d.buyer_loc)).enabled:
			port_of(int(d.buyer_loc)).export_ready(d.item, moved)   # wartet am Kai (Hafen der Verkaeuferstadt) auf das Schiff
		else:
			sim.stock.consume(d.item, moved, IMPORT, int(d.buyer_loc), "Ausfuhr %s" % d.id, sim.game_min)
		_count("exported", d.item, moved)
	if d.seller_biz != "":   # auch interne Lieferungen zaehlen als Absatz des liefernden Betriebs
		var sb: Dictionary = sim.biz.get_b(d.seller_biz)
		if not sb.is_empty():
			sb["sold_today"] = int(sb.get("sold_today", 0)) + moved
	d.qty_received = moved
	d.paid = amount
	d.status = "geliefert"
	d.done = GameCalendar.day_of(sim.game_min)
	if d.buyer_biz != "":
		sim.biz.note(d.buyer_biz, "Angeliefert %s: %d × %s" % [d.id, moved, item_name(d.item)], "Betrieb")


## Zahlung eines Kaeufers an ein Konto ausserhalb der Firmen (Import X0, Lieferdienst S0).
func _pay(from_acct: String, to_acct: String, amount: float, category: String, note: String, cc: String) -> void:
	if amount <= 0.0:
		return
	if from_acct.begins_with("C"):
		sim.company(int(from_acct.substr(1))).ledger.book(category, -amount, true, note, sim.game_min, to_acct, cc)
	else:
		sim.economy.transfer(from_acct, to_acct, amount)


func _prune() -> void:
	if deals.size() <= MAX_DEALS_KEPT:
		return
	var done: Array = deals.values().filter(func(d): return d.status == "geliefert")
	done.sort_custom(func(a, b): return int(a.done) < int(b.done))
	for d in done.slice(0, deals.size() - MAX_DEALS_KEPT):
		deals.erase(d.id)


## Insolvenz: noch nicht abgeholte Liefervertraege eines Kontos stornieren (Reservierung frei, Ausschreibung zurueckgezogen).
## Bereits angenommene Transporte laufen zu Ende und werden aus der Masse bezahlt.
func cancel_deals_of(acct: String) -> void:
	for d in deals.values():
		if d.status != "transport" or (d.buyer != acct and d.seller != acct):
			continue
		var k: Contract = sim.contracts.get(str(d.contract))
		if k != null and k.status != "open":
			continue
		if k != null:
			k.status = "cancelled"
		sim.stock.release("deal:" + str(d.id))
		if d.seller == IMPORT and not port_of(int(d.seller_loc)).enabled:   # Kuestenort: die Ware bleibt im Hafenlager
			sim.stock.consume(d.item, int(d.qty), IMPORT, int(d.seller_loc), "Storno %s" % d.id, sim.game_min)
		d.status = "storniert"


# ------------------------------------------------------------------ Ausfuhr
## Ueberschuesse (Artikel mit Exportpreis) gehen zum Exportpreis frei Verladestelle (Grosshandelslager) hinaus; die Fracht dorthin
## zahlt der Verkaeufer. Nur wenn mindestens EXPORT_MIN_UNITS Ladeeinheiten frei sind und nach Fracht mindestens die Haelfte des
## Exportpreises bleibt und der Ueberschuss EXPORT_WAIT_DAYS Tage unverkauft lag. Eine Ladeeinheit bleibt fuer Kaeufer in der Stadt zurueck.
const EXPORT_MIN_UNITS := 2


## Fehlmenge der Verarbeiter in der Region fuer einen Rohstoff: laufende/blockierte Betriebe mit dem Artikel im Rezept,
## die auf den Artikel warten (Einkauf scheiterte) oder keinen Bestand (inkl. unterwegs) haben.
func regional_need(item: String) -> int:
	var need := 0
	for b in sim.biz.items.values():
		if b.status not in Businesses.RUNNING:
			continue
		var r: Dictionary = Businesses.branches().get(b.branch, {}).get("rezept", {})
		if not r.get("ein", {}).has(item):
			continue
		var acct := "C%d" % int(b.owner)
		var have: int = sim.stock.available(item, acct, int(b.site)) + incoming(acct, item, int(b.site))
		if str(b.get("waiting_for", "")) == item or have <= 0:   # Betrieb wartet bzw. ist leer (belieferte Betriebe halten ihr Lager bewusst klein)
			need += maxi(1, int(r.ein[item]) * 20 - have)
	return need


## Standorthinweise fuer die Modell-Beobachtung, je Spieltag zwischengespeichert: site_hints durchsucht bis zu 2000 Grundstuecke und
## kostete auf der Regionskarte ~570 ms je Beobachtung (Partie 09.11.: Spiel stockte bei jeder Modell- und Dispositionsrunde).
## Hinweise sind nur Vorschlaege; die Gruendung selbst prueft das Grundstueck.
var _hint_cache := {}
func site_hints_cached(branch: String, n: int = 3, town_only: int = -1) -> Array:
	var key := "%s|%d|%d" % [branch, n, town_only]
	var day := GameCalendar.day_of(sim.game_min)
	var hit: Dictionary = _hint_cache.get(key, {})
	if hit.is_empty() or int(hit.day) != day:
		hit = {"day": day, "out": site_hints(branch, n, town_only)}
		_hint_cache[key] = hit
	return hit.out


## 1) Standorthinweise fuer eine Gruendung (die KI entscheidet): freie, erschlossene Grundstuecke nach den Zutatenkosten einer
## Charge (Preis + Fracht von der guenstigsten Quelle: Betrieb der Region - auch im Bau - oder Import ueber den Hafen der Stadt).
## Gibt bis zu `n` Vorschlaege {grundstueck, stadt, zutaten_je_charge, quellen} zurueck, guenstigste zuerst.
func site_hints(branch: String, n: int = 3, town_only: int = -1) -> Array:
	var spec: Dictionary = Businesses.branches().get(branch, {})
	var ein: Dictionary = spec.get("rezept", {}).get("ein", {})
	if ein.is_empty() or spec.has("abbau") or spec.has("feld"):
		return []
	var bsize: Array = CityGenerator.TYPES[str(spec.get("gebaeude", "factory"))]
	var min_area: int = int(bsize[1]) * int(bsize[2]) + 4
	var need_power := float(spec.get("strom_kw", 0.0)) > 0.0
	var sources := {}   # Artikel -> [{name, cell, price}]
	for item in ein:
		sources[item] = []
		for b in sim.biz.items.values():
			if b.status not in Businesses.RUNNING and b.status != "im_bau":
				continue
			var bs: Dictionary = Businesses.branches().get(b.branch, {})
			var makes: bool = bs.get("rezept", {}).get("aus", {}).has(item) or (bs.has("abbau") and str(b.get("deposit", {}).get("art", "")) == item)
			if makes:
				sources[item].append({"name": "%s %s" % [b.id, bs.get("label", b.branch)], "cell": sim.city.building(int(b.site)).road, "price": float(art(item).get("basispreis", 10.0))})
	var zones: Array = ["industrie", "gewerbe"] if branch in Mayor.INDUSTRY else ["industrie", "gewerbe", "mischgebiet"]   # wie Mayor.business_permit
	var cands: Array = sim.parcels.search({"min_area": min_area, "limit": 2000}).filter(func(p): return p.zone in zones \
			and (not need_power or bool(p.get("erschliessung", {}).get("strom", true))))
	if town_only >= 0 and sim.towns.is_region():
		cands = cands.filter(func(p): return sim.towns.of_parcel(str(p.id)) == town_only)   # Endkundenbetriebe gehoeren in ihre Stadt
	cands = cands.filter(func(p): return bool(sim.parcels.utilities_of(p).strasse))   # teure Feldabtastung erst nach den billigen Filtern
	var btype := str(spec.get("gebaeude", "factory"))
	var out: Array = []
	for p in cands.slice(0, 300):
		if not placeable(p, btype):
			continue   # nur Grundstuecke vorschlagen, auf denen die Gruendung das Gebaeude auch setzen kann
		var cell := Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
		var town: int = sim.towns.of_parcel(str(p.id)) if sim.towns.is_region() else 0
		var H: Harbor = sim.towns.harbor(town) if sim.towns.is_region() else sim.harbor
		var port_cell: Vector2i = sim.city.building(H.building if H.enabled else int(sim.retail.wholesale_building)).road
		var total := 0.0
		var notes: Array = []
		for item in ein:
			var q := int(ein[item]) * 20   # 20 Chargen als Liefermenge
			var ip = art(item).get("importpreis")
			var best := INF if ip == null else float(ip) + freight_dist(absi(cell.x - port_cell.x) + absi(cell.y - port_cell.y), item, q) / float(q)
			var from := "Import"
			for src in sources[item]:
				var u: float = float(src.price) + freight_dist(absi(cell.x - src.cell.x) + absi(cell.y - src.cell.y), item, q) / float(q)
				if u < best:
					best = u
					from = str(src.name)
			if best == INF:
				continue
			total += best * float(ein[item])
			notes.append("%s %.1f EUR/E (%s)" % [item_name(item), best, from])
		out.append({"grundstueck": str(p.id), "stadt": sim.towns.name_of(town) if sim.towns.is_region() else "", "zutaten_je_charge": snappedf(total, 0.1), "quellen": ", ".join(notes)})
	out.sort_custom(func(a, b): return float(a.zutaten_je_charge) < float(b.zutaten_je_charge))
	return out.slice(0, n)
const EXPORT_WAIT_DAYS := 3
func _export_surplus() -> void:
	for item in articles():
		var ep = art(item).get("exportpreis")
		if ep == null:
			continue
		var per := int(art(item).get("je_ladeeinheit", 1))
		for s in sellers(item):
			var q := int(s.avail) - per
			var sb: Dictionary = sim.biz.get_b(str(s.biz))
			var key: String = "surplus_since_" + str(item)
			var port := import_point(int(s.loc))   # Ausfuhr ueber den Hafen der eigenen Stadt
			if q < per * EXPORT_MIN_UNITS or int(s.loc) == port:
				sb.erase(key)
				continue
			var today := GameCalendar.day_of(sim.game_min)
			if not sb.has(key):
				sb[key] = today
			if today - int(sb[key]) < EXPORT_WAIT_DAYS:
				continue   # erst den Kaeufern in der Stadt Zeit lassen
			if regional_need(item) > 0:
				continue   # Vorrang fuer die eigene Kette: solange ein Betrieb der Region den Rohstoff braucht, nicht ausfuehren
			sb.erase(key)
			var fr := freight(int(s.loc), port, item, q)
			if float(ep) - fr / float(q) < float(ep) * 0.5:
				continue
			if _deal(IMPORT, port, "", s, item, q, float(ep), fr):
				var d: Dictionary = deals["D%d" % (_next - 1)]
				d["payer"] = s.acct
				d["payer_biz"] = s.biz
				var k: Contract = sim.contracts[d.contract]
				k.payer = "firm:" + s.acct.substr(1)
				k.label += " · Ausfuhr"


# ------------------------------------------------------------------ Grosshandel (Brot)
## Lokale Ware fuer den Grosshandel (W0) bestellen; kein Import (den macht der Einzelhandel selbst). Gibt die bestellte Menge zurueck.
func wholesale_order(item: String, qty: int, loc: int, max_unit: float) -> int:
	if qty <= 0 or art(item).is_empty():
		return 0
	return order("W0", loc, "", item, qty, max_unit, false)


# ------------------------------------------------------------------ Uebersicht und KI
## Kette je Artikel: lokale Erzeugung, Bedarf, Importe (fuer Beobachtung und Ansicht).
func chain_summary() -> Dictionary:
	var out := {}
	for item in articles():
		out[item] = {"lokal_erzeugt": int(stats.produced.get(item, 0)), "verbraucht": int(stats.consumed.get(item, 0)), "importiert": int(stats.imported.get(item, 0)),
			"anbieter": sellers(item).size()}
	return out


## Betriebsdetails fuer Ansicht und Beobachtung (Phase, Bestaende, Unterwegs).
func detail(b: Dictionary) -> Dictionary:
	var spec: Dictionary = Businesses.branches().get(b.branch, {})
	var acct := "C%d" % int(b.owner)
	var e := {}
	if spec.has("feld"):
		var f: Dictionary = b.field
		e = {"phase": f.phase, "tag_in_phase": int(f.day), "flaeche": int(f.area), "ernten": int(f.cycles), "letzte_ernte_dt": int(f.last_yield)}
		var crop := str(spec.feld.get("artikel", "getreide"))
		var seed := str(spec.feld.get("saat", "saatgut"))
		e["bestand"] = {seed: sim.stock.qty(seed, acct, int(b.site)), crop: sim.stock.qty(crop, acct, int(b.site))}
		e["preise"] = {crop: price_of(b, crop)}
		e["absatz_tag"] = int(b.get("sales_avg", 0.0))
	elif spec.has("abbau"):
		var dp := deposit_of(str(b.get("parcel", "")))
		e = {"rohstoff": str(b.deposit.art), "vorrat": int(dp.get("menge", 0)), "qualitaet": float(b.deposit.qualitaet), "foerderung_heute": int(b.get("today", 0)),
			"bestand": {str(b.deposit.art): sim.stock.qty(str(b.deposit.art), acct, int(b.site))}, "preise": {str(b.deposit.art): price_of(b, str(b.deposit.art))}, "absatz_tag": int(b.get("sales_avg", 0.0))}
	elif spec.get("laden", {}).get("gerichte", false):
		var ks := {}
		for item in kitchen_items():
			ks[item] = sim.stock.qty(item, acct, int(b.site))
		e = {"bestand": ks, "gaeste_tag": int(b.get("guests_avg", 0.0)), "absatz_tag": int(b.get("sales_avg", 0.0)),
			"laden": ("offen, %d Gäste gestern" % int(b.get("counter_customers", 0))) if bool(b.get("counter", false)) else "geschlossen (Servicekraft oder Strom fehlt)"}
	elif spec.has("rezept"):
		var bs := {}
		for item in spec.rezept.ein:
			bs[item] = sim.stock.qty(item, acct, int(b.site))
		for item in spec.rezept.aus:
			bs[item] = sim.stock.qty(item, acct, int(b.site))
		var pr := {}
		for item in spec.rezept.aus:
			pr[item] = price_of(b, item)
		e = {"chargen_heute": int(b.get("today", 0)), "chargen_gesamt": int(b.get("total", 0)), "bestand": bs, "preise": pr, "absatz_tag": int(b.get("sales_avg", 0.0))}
		if spec.rezept.has("mast_tage"):
			var n_in := 0
			for m in b.get("pipeline", []):
				n_in += int(m.n)
			e["in_mast"] = n_in
		if spec.has("laden"):
			e["laden"] = ("offen, %d Kunden gestern" % int(b.get("counter_customers", 0))) if bool(b.get("counter", false)) else "geschlossen (Verkaufskraft fehlt)"
	e["alter_tage"] = GameCalendar.day_of(sim.game_min) - GameCalendar.day_of(float(b.founded))
	if b.has("first_output_day"):
		e["produziert_seit_tagen"] = GameCalendar.day_of(sim.game_min) - int(b.first_output_day)
	if b.has("parcel"):
		e["grundstueck"] = b.parcel
	if e.has("preise"):
		e["preis_seit_tagen"] = GameCalendar.day_of(sim.game_min) - int(b.get("price_day", GameCalendar.day_of(float(b.founded))))
	var inc := {}
	for d in deals.values():
		if d.buyer == acct and int(d.buyer_loc) == int(b.site) and d.status in ["transport", "unterwegs"]:
			inc[d.item] = int(inc.get(d.item, 0)) + int(d.qty)
	if not inc.is_empty():
		e["unterwegs"] = inc
	return e


## Lage der Kette fuer die KI-Beobachtung: Betriebe je Stufe und bisherige Importe (= Chance fuer lokale Erzeuger).
func market_obs() -> Dictionary:
	var n := {"feld": 0, "muehle": 0, "baeckerei": 0, "tierhaltung": 0, "schlachthof": 0, "restaurant": 0, "baufirma": 0, "stahlwerk": 0, "elektrostahlwerk": 0, "kokerei": 0, "bergwerk": 0, "brauerei": 0, "moebelwerk": 0, "forst": 0, "it": 0}
	for b in sim.biz.items.values():
		if n.has(b.branch) and b.status in Businesses.RUNNING:
			n[b.branch] = int(n[b.branch]) + 1
	var waiting := {}
	for b in sim.biz.items.values():
		if b.status in Businesses.RUNNING and b.has("waiting_for") and UPSTREAM.has(str(b.waiting_for)):
			waiting[b.waiting_for] = int(waiting.get(b.waiting_for, 0)) + 1
	var access := {}   # Rohstoffe mit Engpass ohne erreichbare Lagerstaette: wohin eine Zufahrt fuehren muesste
	for item in waiting:
		if str(UPSTREAM.get(item, "")) == "bergwerk" and best_deposit(str(item)).is_empty():
			var far := remote_deposit(str(item))
			if not far.is_empty():
				access[item] = far
	return {"bergwerke_gesamt": sim.biz.items.values().filter(func(b): return b.branch == "bergwerk" and b.status != "geschlossen").size(), "bau_wartend": sim.crews.waiting().size(), "bautrupps_frei": sim.crews.crews.values().filter(func(t): return t.state == "frei").size(), "engpaesse": waiting, "zufahrt_noetig": access, "zufahrten_im_bau": sim.access.running(), "felder": n.feld, "muehlen": n.muehle, "baeckereien": n.baeckerei, "tierhaltungen": n.tierhaltung, "schlachthoefe": n.schlachthof, "restaurants": n.restaurant, "baufirmen": n.baufirma, "stahlwerke": n.stahlwerk + n.elektrostahlwerk, "brauereien": n.brauerei, "moebelwerke": n.moebelwerk, "it_betriebe": n.it, "bauvorhaben": sim.construction.projects.values().filter(func(p): return p.status in ["angebote", "erschliessung", "im_bau"]).size(), "brot_import": int(sim.retail.stats.get("bread_import", 0))}


## Marktchancen fuer die KI: wie viel einer Stufe wird importiert statt lokal erzeugt (Brot: Grosshandelsimport).
func opportunities() -> Array:
	var out: Array = []
	var bread_import := int(sim.retail.stats.get("bread_import", 0))
	var bakeries: int = sim.biz.items.values().filter(func(b): return b.branch == "baeckerei" and b.status in Businesses.RUNNING).size()
	var mills: int = sim.biz.items.values().filter(func(b): return b.branch == "muehle" and b.status in Businesses.RUNNING).size()
	var fields: int = sim.biz.items.values().filter(func(b): return b.branch == "feld" and b.status in Businesses.RUNNING).size()
	out.append({"branche": "baeckerei", "hinweis": "Großhandel importiert Brot (bisher %d Stk), lokale Bäckereien: %d" % [bread_import, bakeries]})
	out.append({"branche": "muehle", "hinweis": "Mehl importiert: %d Sack, lokale Mühlen: %d, Bäckereien: %d" % [int(stats.imported.get("mehl", 0)), mills, bakeries]})
	out.append({"branche": "feld", "hinweis": "Getreide importiert: %d dt, lokale Felder: %d, Mühlen: %d" % [int(stats.imported.get("getreide", 0)), fields, mills]})
	return out


func to_dict() -> Dictionary:
	return {"deals": deals, "stats": stats, "next": _next, "mined": mined}


func from_dict(d: Dictionary) -> void:
	deals = d.get("deals", {})
	for x in deals.values():
		for k in ["qty", "seller_loc", "buyer_loc", "reissued", "day"]:
			x[k] = int(x[k])
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]
	_next = int(d.get("next", 1))
	mined = {}
	for k in d.get("mined", {}):
		mined[k] = int(d.mined[k])
