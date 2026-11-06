class_name Production
extends RefCounted
## Produktionsketten der Unternehmer (Auftrag 14, Etappe 2: Getreide -> Mehl -> Brot; docs/ENTREPRENEURS.md).
##
## Betriebe (Businesses) mit Feld oder Rezept arbeiten einmal je Spieltag:
##   Feld:     Vorbereitung -> Aussaat (verbraucht Saatgut) -> Wachstum (Wetter, Pflege) -> Ernte -> Getreide liegt am Feld.
##   Rezept:   Eingangswaren am Standort + Personal + Strom -> Ausgangswaren am Standort (Muehle, Baeckerei).
## Beschaffung: Fehlt Eingangsware, bestellt der Betrieb beim guenstigsten Anbieter (Ware + Fracht je Stueck): andere Betriebe mit
## freiem Bestand oder Import am Importterminal (Lieferzeit = Transport). Ein Liefervertrag ("D<n>") reserviert die Ware beim
## Verkaeufer und schreibt einen echten Transportauftrag aus (Zahler = Kaeufer). Bei Anlieferung wechselt das Eigentum und der
## Kaeufer zahlt. Interne Lieferungen (gleiche Company) kosten keinen Warenpreis und erzeugen keinen Umsatz.
## Der Lebensmittelgrosshandel (W0) kauft Brot zuerst bei lokalen Baeckereien (Retail._stock_wholesale), nur der Rest ist Import.
## Ware entsteht nur durch Ernte, Rezeptausgang oder Import (StockBook.add) und verschwindet nur durch Verbrauch/Verderb (consume).

const ARTICLES_PATH := "res://config/articles.json"
const IMPORT := "X0"
const FREIGHT_BASE := 18.0
const OFFER_DAYS := 1
const FALLBACK_SHARE := 0.7          # Lieferdienst, wenn niemand den Transport uebernimmt (wie im Einzelhandel)
const SPOIL_SHARE := 0.25            # Anteil verderblicher Ware am Produktionsstandort, der taeglich verdirbt
const MAX_DEALS_KEPT := 300

static var _articles := {}

var sim
var deals := {}                      # "D<n>" -> Liefervertrag
var stats := {"produced": {}, "consumed": {}, "imported": {}, "sold": 0.0, "deals": 0, "fallback": 0, "spoiled": 0}
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


# ------------------------------------------------------------------ Gruendung
## Produktionsbetrieb gruenden. params: grundstueck (Parzelle "G<n>", nur Feld; sonst die guenstigste passende), modus ("pachten"|"kaufen").
## Ausstattung (Maschinen, Ofen, Traktor) ist eine Investition mit Abschreibung je Tag (Kostenstelle des Betriebs).
func found(cid: int, branch: String, params: Dictionary, reason: String) -> Dictionary:
	var spec: Dictionary = Businesses.branches().get(branch, {})
	var c = sim.company(cid)
	var equip := float(spec.get("ausstattung", 0.0))
	var site := -1
	var parcel := {}
	var land := 0.0
	var mode := str(params.get("modus", "pachten"))
	var cands: Array = []
	if spec.has("feld"):
		cands = _parcel_candidates(str(params.get("grundstueck", "")), int(spec.feld.min_flaeche))
		if cands.is_empty():
			return {"ok": false, "msg": "Kein freies Grundstück mit Straßenzugang und mindestens %d Feldern verfügbar." % int(spec.feld.min_flaeche)}
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
	if not parcel.is_empty():
		var bld := {}
		for p in cands:   # erstes Grundstueck, auf dem das Hofgebaeude Strassenzugang hat
			if mode == "kaufen" and c.ledger.cash < equip + float(p.price):
				continue
			bld = _place_field(p, "%s %s" % [spec.label, c.company_name])
			if not bld.is_empty():
				parcel = p
				land = float(p.price) if mode == "kaufen" else 0.0
				break
		if bld.is_empty():
			return {"ok": false, "msg": "Auf %s ist kein Platz mit Straßenzugang." % ("Grundstück " + str(parcel.id) if cands.size() == 1 else "den freien Grundstücken")}
		site = int(bld.id)
		parcel.owner = "C%d" % cid
		parcel["lease_by"] = cid if mode != "kaufen" else -1
		if mode == "kaufen":
			c.ledger.invest(land, "P0")
			c.land_book += land
			parcel["book"] = land
		sim.parcels.touch(parcel.id)
	var b: Dictionary = sim.biz.create(cid, branch, site, "", "aktiv")
	if c.ledger.cost_center == "":
		c.ledger.cost_center = b.id
	if equip > 0.0:
		c.ledger.invest(equip, "S0")
		c.property_book += equip
		b["book"] = equip
		b["equip"] = equip
	b["prices"] = {}
	if spec.has("feld"):
		b["parcel"] = parcel.id
		b["field"] = {"area": int(parcel.area), "phase": "brache", "day": 0, "growth": 0.0, "grow_days": 0, "cycles": 0, "last_yield": 0,
			"mode": "kauf" if mode == "kaufen" else "pacht", "lease_day": float(parcel.lease_month) / 30.0 if mode != "kaufen" else 0.0}
	sim.biz.note(b.id, "Gegründet: %s" % (reason if reason != "" else spec.label), "Unternehmer")
	sim.log_event("%s gründet %s%s." % [c.company_name, b.name, " auf Grundstück %s (%d Felder, %s)" % [parcel.id, int(parcel.area), "gekauft" if mode == "kaufen" else "gepachtet"] if not parcel.is_empty() else ""], "info", cid)
	return {"ok": true, "msg": "%s gegründet (%s). Personal zuordnen (assign_staff), sonst ruht der Betrieb." % [b.name, b.id], "ref": b.id}


## Grundstuecke fuer ein Feld: das genannte oder freie Grundstuecke mit Strassenanschluss, Aecker bevorzugt ausserhalb von Wohn-
## und Mischgebiet, dann nach Preis je Feld.
func _parcel_candidates(pid: String, min_area: int) -> Array:
	if pid != "":
		var p: Dictionary = sim.parcels.parcel(pid)
		return [p] if not p.is_empty() and p.state == "frei" and p.owner == Parcels.CITY and int(p.area) >= min_area and sim.parcels.is_buildable(p) else []
	var out: Array = sim.parcels.search({"min_area": min_area, "limit": 400}).filter(func(p): return bool(sim.parcels.utilities_of(p).strasse))
	out.sort_custom(func(a, b): return [a.zone in ["wohnen", "mischgebiet"], float(a.price) / float(a.area)] < [b.zone in ["wohnen", "mischgebiet"], float(b.price) / float(b.area)])
	return out.slice(0, 40)


## Hofgebaeude des Feldes (3x3, Kartenbild "farm") an einer Stelle der Parzelle mit Strassenzugang.
func _place_field(p: Dictionary, name: String) -> Dictionary:
	var r0 := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
	for y in range(r0.position.y, r0.end.y - 2):
		for x in range(r0.position.x, r0.end.x - 2):
			var r := Rect2i(x, y, 3, 3)
			if not sim.events._free(r):
				continue
			var b: Dictionary = sim.events._add_building("farm", r, name)
			if not b.is_empty():
				sim.market.refresh()
				sim.events.buildings_added.emit([b.id])
				return b
	return {}


# ------------------------------------------------------------------ Tageslauf
func on_day(day: int) -> void:
	for b in sim.biz.items.values():
		var spec: Dictionary = Businesses.branches().get(b.branch, {})
		if not (spec.has("feld") or spec.has("rezept")) or b.status not in Businesses.RUNNING or sim.biz.frozen(int(b.owner)):
			continue
		_costs(b)
		if spec.has("feld"):
			_field_day(b, spec)
		else:
			_recipe_day(b, spec)
		_spoil(b, spec)
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
	var f: Dictionary = b.get("field", {})
	if float(f.get("lease_day", 0.0)) > 0.0:
		c.ledger.book("rent", -float(f.lease_day), true, "Pacht %s" % b.get("parcel", ""), sim.game_min, "P0", b.id)


func _staff_ok(b: Dictionary, spec: Dictionary) -> int:
	var n: int = sim.biz.staff_of(b.id).size()
	if n < int(spec.get("personal_min", 1)):
		sim.biz.block(b.id, "personal", "Kein Personal: mindestens %d Mitarbeiter zuordnen (assign_staff)" % int(spec.get("personal_min", 1)))
	else:
		sim.biz.unblock(b.id, "personal")
	return n


func _field_day(b: Dictionary, spec: Dictionary) -> void:
	var F: Dictionary = spec.feld
	var f: Dictionary = b.field
	var cid := int(b.owner)
	var acct := "C%d" % cid
	var site := int(b.site)
	var staff := _staff_ok(b, spec)
	var days: Dictionary = F.tage
	match str(f.phase):
		"brache", "vorbereitung":
			_ensure_input(b, "saatgut", _seed_need(b, F), _seed_need(b, F))
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
			if sim.stock.available("saatgut", acct, site) < need:
				sim.biz.block(b.id, "material", "Wartet auf Saatgut (%d Sack nötig)" % need)
				_ensure_input(b, "saatgut", need, need)
				return
			sim.biz.unblock(b.id, "material")
			if staff <= 0:
				return
			f.day = int(f.day) + 1
			if int(f.day) >= int(days.aussaat):
				_use(b, "saatgut", need, acct, site)
				f.phase = "wachstum"
				f.day = 0
				f.growth = 0.0
				f.grow_days = 0
				sim.biz.note(b.id, "Aussaat abgeschlossen (%d Sack Saatgut)" % need, "Betrieb")
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
					sim.stock.add("getreide", y, acct, site, "Ernte %s" % b.id, sim.game_min)
					_count("produced", "getreide", y)
				f.last_yield = y
				f.cycles = int(f.cycles) + 1
				f.phase = "brache"
				f.day = 0
				sim.biz.note(b.id, "Ernte: %d dt Getreide (Wachstum %.0f %%) liegen am Feld zum Abtransport" % [y, avg * 100.0], "Betrieb")
				sim.log_event("%s erntet %d dt Getreide." % [b.name, y], "good", cid)


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
	var cap := staff * int(R.chargen_je_person_tag)
	# Beschaffung fuer die naechsten Tage (auch ohne Personal, damit der Betrieb anlaufen kann)
	var plan := maxi(cap, int(R.chargen_je_person_tag))
	for item in R.ein:
		var per_day := plan * int(R.ein[item])
		_ensure_input(b, item, per_day * int(R.lager_tage), per_day * int(R.lager_tage) / 2)
	b["today"] = 0
	if staff <= 0:
		return
	if float(b.energy_kw) > 0.0 and not sim.grid.supplied.has(b.id):
		return   # Blockade "strom" setzt PowerGrid mit konkretem Grund
	var batches := cap
	var short := ""
	for item in R.ein:
		var n: int = sim.stock.available(item, acct, site) / int(R.ein[item])
		if n < batches:
			batches = n
			short = item
	for item in R.aus:
		var room: int = (int(R.lager_max) - sim.stock.qty(item, acct, site)) / int(R.aus[item])
		if room < batches:
			batches = maxi(0, room)
			short = "lager:" + item
	if batches <= 0:
		if short.begins_with("lager:"):
			sim.biz.block(b.id, "material", "Lager voll: %s wird nicht abgeholt" % item_name(short.trim_prefix("lager:")))
		else:
			sim.biz.block(b.id, "material", "Wartet auf %s" % item_name(short))
		return
	sim.biz.unblock(b.id, "material")
	for item in R.ein:
		_use(b, item, batches * int(R.ein[item]), acct, site)
	for item in R.aus:
		var q := batches * int(R.aus[item])
		sim.stock.add(item, q, acct, site, "Produktion %s" % b.id, sim.game_min)
		_count("produced", item, q)
	b.today = batches
	b["total"] = int(b.get("total", 0)) + batches


func _use(b: Dictionary, item: String, qty: int, acct: String, site: int) -> void:
	var n: int = sim.stock.consume(item, qty, acct, site, "Verbrauch %s" % b.id, sim.game_min)
	_count("consumed", item, n)


func _spoil(b: Dictionary, spec: Dictionary) -> void:
	var out: Dictionary = spec.get("rezept", {}).get("aus", {})
	for item in out:
		if int(art(item).get("haltbar_tage", 0)) <= 0:
			continue
		var acct := "C%d" % int(b.owner)
		var n := int(floor(float(sim.stock.available(item, acct, int(b.site))) * SPOIL_SHARE))
		if n > 0:
			sim.stock.consume(item, n, acct, int(b.site), "Verdorben %s" % b.id, sim.game_min)
			stats.spoiled = int(stats.spoiled) + n


func _count(key: String, item: String, n: int) -> void:
	stats[key][item] = int(stats[key].get(item, 0)) + n


# ------------------------------------------------------------------ Beschaffung
## Bestand + Unterwegs unter `reorder` -> bis `target` nachbestellen.
func _ensure_input(b: Dictionary, item: String, target: int, reorder: int) -> void:
	var acct := "C%d" % int(b.owner)
	var have: int = sim.stock.available(item, acct, int(b.site)) + incoming(acct, item, int(b.site))
	if have > reorder and have > 0:
		return
	var want := target - have
	if want <= 0:
		return
	var got := order(acct, int(b.site), b.id, item, want, INF, true)
	if got <= 0:
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
		var makes: bool = spec.get("rezept", {}).get("aus", {}).has(item) or (spec.has("feld") and item == "getreide")
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
	sim.biz.note(bid, "Preis %s: %s" % [item_name(item), Catalog.money(price)], "Unternehmer")
	return {"ok": true, "msg": "Preis für %s auf %s je %s gesetzt." % [item_name(item), Catalog.money(price), art(item).einheit]}


func freight(from_loc: int, to_loc: int, item: String, qty: int) -> float:
	var a: Dictionary = sim.city.building(from_loc)
	var z: Dictionary = sim.city.building(to_loc)
	var dist: int = absi(a.road.x - z.road.x) + absi(a.road.y - z.road.y)
	return snappedf(FREIGHT_BASE + float(dist) * (1.0 + float(units(item, qty)) / 8.0), 1.0)


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
	var port: int = sim.city_depot.port
	if allow_import and ip != null and port >= 0 and port != loc:
		cands.append({"s": {"biz": "", "acct": IMPORT, "cid": -1, "loc": port, "avail": qty, "price": float(ip)}, "unit": float(ip) + freight(port, loc, item, qty) / float(qty), "q": qty, "own": false})
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
		var fr := freight(int(s.loc), loc, item, q)
		# Liquiditaet des Kaeufers (Ware + Fracht werden bei Anlieferung faellig)
		var cash := _cash(buyer)
		while q > 0 and float(q) * price + fr > cash:
			q = q / 2
			fr = freight(int(s.loc), loc, item, maxi(1, q))
		if q <= 0:
			continue
		if _deal(buyer, loc, buyer_biz, s, item, q, price, fr):
			left -= q
	return qty - left


func _cash(acct: String) -> float:
	if acct.begins_with("C"):
		return sim.company(int(acct.substr(1))).ledger.cash
	return maxf(0.0, float(sim.economy.accounts.get(acct, 0.0)))


func _deal(buyer: String, loc: int, buyer_biz: String, s: Dictionary, item: String, q: int, price: float, fr: float) -> bool:
	var id := "D%d" % _next
	_next += 1
	var ref := "deal:" + id
	if s.acct == IMPORT:
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
	k.payer = ("firm:" + d.buyer.substr(1)) if d.buyer.begins_with("C") else str(d.buyer)
	k.order_ref = "deal:" + str(d.id)
	k.created = sim.game_min
	k.offer_until = sim.game_min + GameCalendar.days_to_min(float(OFFER_DAYS))
	k.deadline = sim.game_min + GameCalendar.days_to_min(float(OFFER_DAYS + 2))
	k.distance = absi(src.road.x - dst.road.x) + absi(src.road.y - dst.road.y)
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
		if int(d.reissued) < 1 and k != null and k.status in ["open", "expired", "failed"]:
			d.reissued = int(d.reissued) + 1
			if k.status == "open":
				k.status = "expired"
			_issue_contract(d)
			continue
		_fallback(d, k)
	_prune()


## Lieferdienst (S0), wenn kein Unternehmen den Transport uebernommen hat: Kaeufer zahlt einen Teil der Fracht, Ware kommt an.
func _fallback(d: Dictionary, k: Contract) -> void:
	var pay := minf(float(d.freight) * FALLBACK_SHARE, maxf(0.0, _cash(d.buyer)))
	_pay(d.buyer, "S0", pay, "trade_expense", "Lieferdienst %s" % d.id, d.buyer_biz)
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
	if d.buyer.begins_with("C") and k.paid > 0.0:
		var payer = sim.company(int(d.buyer.substr(1)))
		payer.ledger.book("trade_expense", -k.paid, true, "Fracht %s" % d.id, sim.game_min, "C0", d.buyer_biz)
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
		e = {"phase": f.phase, "tag_in_phase": int(f.day), "flaeche": int(f.area), "ernten": int(f.cycles), "letzte_ernte_dt": int(f.last_yield), "grundstueck": b.get("parcel", "")}
		e["bestand"] = {"saatgut": sim.stock.qty("saatgut", acct, int(b.site)), "getreide": sim.stock.qty("getreide", acct, int(b.site))}
	elif spec.has("rezept"):
		var bs := {}
		for item in spec.rezept.ein:
			bs[item] = sim.stock.qty(item, acct, int(b.site))
		for item in spec.rezept.aus:
			bs[item] = sim.stock.qty(item, acct, int(b.site))
		e = {"chargen_heute": int(b.get("today", 0)), "chargen_gesamt": int(b.get("total", 0)), "bestand": bs}
	var inc := {}
	for d in deals.values():
		if d.buyer == acct and int(d.buyer_loc) == int(b.site) and d.status in ["transport", "unterwegs"]:
			inc[d.item] = int(inc.get(d.item, 0)) + int(d.qty)
	if not inc.is_empty():
		e["unterwegs"] = inc
	return e


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
	return {"deals": deals, "stats": stats, "next": _next}


func from_dict(d: Dictionary) -> void:
	deals = d.get("deals", {})
	for x in deals.values():
		for k in ["qty", "seller_loc", "buyer_loc", "reissued", "day"]:
			x[k] = int(x[k])
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]
	_next = int(d.get("next", 1))
