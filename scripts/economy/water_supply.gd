class_name WaterSupply
extends RefCounted
## Trinkwasser je Stadt (Auftrag 22 Phase 4 Schritt 1, docs/INFRASTRUCTURE.md). Jede Stadt der Region hat ein Wasserwerk (Municipal
## WW-01, Startausstattung). Verbrauch je Spieltag: Einwohner (120 l), kommunale Einrichtungen (TYPES.water, anteilig zur
## Ortsgroesse, siehe facility_need) und laufende Betriebe (Grundbedarf + Anteil an der Anschlussleistung). Das Werk foerdert seine Leistung
## (capacity m3/Tag) mal Besetzungsgrad, ohne Strom nichts. Verteilung: erst Haushalte, dann Einrichtungen, dann Betriebe in
## Reihenfolge ihres Anschlusses; Betriebe ohne Wasser bzw. ohne Wasseranschluss des Grundstuecks sind mit Grund blockiert.
## Gebuehr je m3 (kostendeckend, jeden Monat neu aus Werkskosten / verkauften m3): Haushalte (H0) und Betriebe zahlen an ihre Stadt.
## Stadt ohne Wasserwerk (kein Bauplatz): Fernwasser, voll versorgt, die Stadt zahlt den Bezugspreis an S0.
## Betriebe im Aussenbereich (Zone ohne Anschlusspflicht) haben einen eigenen Brunnen (on_net).
##
## Schritt 2 Leitungsnetz: Leitungen liegen unter den Strassen der Stadt. Druckzonen reichen ZONE_RANGE Strassenfelder weit ab dem
## Wasserwerk und jedem Hochbehaelter (Municipal WT-01, Startausstattung); Gebaeude, deren Strassenfeld nicht im Netz liegt, sind
## unversorgt (Haushalte zaehlen als ohne Anschluss, Betriebe blockiert). Der Hochbehaelter speichert ueberschuessiges Wasser
## (capacity m3) und ueberbrueckt Stromausfaelle des Werks.
## Schritt 3 Rohrbrueche: zufaellig (bei Frost haeufiger) an einer Netzstelle; die Stelle trennt das Netz (dahinter unversorgt), es
## leckt Wasser. Der Wassertrupp der Stadtwerke (CityFleet "wassertrupp") faehrt vom Wasserwerk hin und repariert vor Ort.
## Schritt 4 Kanal und Klaeranlage: Abwasser (90 %) der angeschlossenen Gebaeude laeuft durch denselben Leitungsweg zur gemeinsamen
## Klaeranlage der Region (Municipal KA-01, regionale Startausstattung). Kosten nach Abwassermenge (Anteile monatlich neu),
## Abwassergebuehr je m3 an die Stadt; reicht die Anlage nicht (Strom, Personal, Kapazitaet), laeuft der Rest ungeklaert ueber
## (Abwasserabgabe an das Land).
## Schritt 5 Ausbau: dauerhaft ausgelastetes Wasserwerk, zu kleiner Hochbehaelter oder volle Klaeranlage -> Ausbauprojekt
## "wasserausbau" ueber die Baufirmen (Kapazitaet x1,5 nach Abnahme).

const L_PER_PERSON := 0.12          # m3 je Einwohner und Spieltag
const BIZ_BASE := 0.4               # m3 je laufendem Betrieb und Tag
const BIZ_PER_KW := 0.01            # zusaetzlich je kW Anschlussleistung
const SEWAGE_SHARE := 0.9           # Anteil des Verbrauchs, der als Abwasser anfaellt
const TARIFF_START := 2.2           # EUR/m3 im ersten Monat
const TARIFF_MIN := 1.5
const TARIFF_MAX := 6.0
const IMPORT_PRICE := 1.8           # Fernwasser je m3 (Stadt ohne eigenes Werk)
const CODE := "WW-01"
const TANK_CODE := "WT-01"
const PLANT_CODE := "KA-01"
const ZONE_RANGE := 80              # Druckzone: so viele Strassenfelder ab Werk bzw. Hochbehaelter (40 liess Gewerbegebiete trocken, Messung 14.11.)
const BREAK_P := 0.02               # Rohrbruch je Stadt und Tag
const BREAK_P_FROST := 0.08         # bei Frost
const BREAK_SPAN := 3              # gesperrter Abschnitt um die Bruchstelle (Strassenfelder je Richtung)
const BREAK_LEAK := 4.0             # m3 Wasserverlust je Tag bis zur Reparatur
const REPAIR_MIN := 60.0            # Arbeitszeit des Wassertrupps vor Ort (Spielminuten)
const REPAIR_EUR := 2500.0
const SEWAGE_TARIFF_START := 1.8    # Abwassergebuehr EUR/m3 im ersten Monat
const SEWAGE_TARIFF_MIN := 1.0
const SEWAGE_TARIFF_MAX := 6.0
const OVERFLOW_FEE := 1.5           # Abwasserabgabe je m3 ungeklaert (an das Land, X0)
const EXPAND_RATIO := 0.85          # Auslastung, ab der ausgebaut wird ...
const EXPAND_DAYS := 5              # ... wenn sie so viele Tage in Folge anhaelt
const EXPAND_SHARE := 0.4           # Ausbaukosten als Anteil der Neubaukosten
const EXPAND_FACTOR := 1.5
const EXPAND_BUILD_DAYS := 12

var sim
var tariff := {}       # Stadt (str) -> EUR/m3
var by_town := {}      # Stadt (str) -> Summen seit Spielbeginn {m3, abwasser, haushalte_eur, betriebe_eur, kosten, fernwasser_eur, engpass_tage}
var month := {}        # Stadt (str) -> {m3_verkauft, kosten} des laufenden Monats
var last := {}         # Stadt (str) -> letzter Tag {werk, leistung, bedarf, haushalte, einrichtungen, betriebe, versorgt, fehl, abgeschaltet, grund}
var supplied := {}     # Betriebs-ID -> true (heute versorgt)
var storage := {}      # Stadt (str) -> m3 im Hochbehaelter
var breaks := {}       # Stadt (str) -> {cell: [x, y], since, vehicle}
var sewage_tariff := {}   # Stadt (str) -> EUR/m3 Abwasser
var sewage := {}       # Stadt (str) -> {m3, ueberlauf, gebuehr_eur, abgabe_eur} seit Beginn
var sewage_month := {} # Stadt (str) -> m3 im laufenden Monat
var plant_month := 0.0 # Kosten der Klaeranlage im laufenden Monat
var plant_last := {}   # letzter Tag der Klaeranlage {zulauf, geklaert, ueberlauf, leistung, grund}
var tight := {}        # Einrichtungs-ID -> Tage in Folge ueber EXPAND_RATIO
var expansions := {}   # Projekt-ID -> Einrichtungs-ID
var stats := {"rohrbrueche": 0, "reparaturen": 0, "ausbauten": 0}
var rng := RandomNumberGenerator.new()
var _net := {}         # Stadt -> {Vector2i: true} Strassenfelder mit Leitungsdruck (abgeleitet, taeglich neu)
var _sewage_today := {}
var _fern := {}        # Stadt -> true: ohne Einspeisung (Fernwasser), gehoert zum Netz-Puffer _net


func setup(simulation) -> void:
	sim = simulation
	if not enabled():
		return
	rng.seed = hash([int(sim.city.seed_value), "wasser"])
	sim.day_changed.connect(on_day)
	sim.month_changed.connect(func(_m): _month())


func enabled() -> bool:
	return sim != null and sim.towns != null and sim.towns.is_region()


func works_of(k: int) -> Dictionary:
	for f in sim.municipal.of_town(k, "wasser"):
		if str(f.code) == CODE and f.status == "in_betrieb":
			return f
	return {}


func tanks_of(k: int) -> Array:
	return sim.municipal.of_town(k, "wasser").filter(func(f): return str(f.code) == TANK_CODE and f.status == "in_betrieb")


func plant() -> Dictionary:
	for f in sim.municipal.facilities.values():
		if str(f.code) == PLANT_CODE and f.status == "in_betrieb":
			return f
	return {}


func tariff_of(k: int) -> float:
	return float(tariff.get(str(k), TARIFF_START))


func sewage_tariff_of(k: int) -> float:
	return float(sewage_tariff.get(str(k), SEWAGE_TARIFF_START)) if not plant().is_empty() else 0.0


func tank_capacity(k: int) -> float:
	var c := 0.0
	for f in tanks_of(k):
		c += float(f.capacity)
	return c


## Strom fuer die Pumpen: Stadt am Kraftwerk oder (abgehaengt) Notstrom reicht noch fuer die Grundlast.
func power_ok(k: int) -> bool:
	var tl: Dictionary = sim.grid.last.get("staedte", {}).get(str(k), {})
	if tl.is_empty() or bool(tl.get("netz", true)):
		return true
	return float(sim.grid.last.get("unversorgt_kw", 0.0)) <= 0.0


## Foerderleistung heute (m3) und Grund einer Einschraenkung ("" = volle Leistung).
func output_of(k: int) -> Dictionary:
	var f := works_of(k)
	if f.is_empty():
		return {"m3": INF, "grund": ""}
	if not power_ok(k):
		return {"m3": 0.0, "grund": "Wasserwerk ohne Strom"}
	var st: float = sim.municipal.staffing(f.id)
	var m3 := float(f.capacity) * st
	return {"m3": m3, "grund": "" if st >= 1.0 else "Wasserwerk unterbesetzt (%d %%)" % roundi(st * 100.0)}


func biz_need(b: Dictionary) -> float:
	return BIZ_BASE + BIZ_PER_KW * float(b.get("energy_kw", 0.0))


## Einrichtungen: TYPES.water gilt fuer eine Stadt mit REF_POP Einwohnern; kleinere Orte anteilig (mind. 5 %), davon die Haelfte
## als echter Trinkwasserbezug (Rest Brauch-/Regenwasser). Gemessen 13.11.: ohne diese Skalierung brauchten die Einrichtungen
## eines 57-Einwohner-Orts 47 m3, siebenmal so viel wie die Haushalte.
func facility_need(f: Dictionary) -> float:
	var pop := float(sim.citizens.population_of(int(f.town)))
	return float(f.get("water", 0.0)) * 0.5 * clampf(pop / Municipal.REF_POP, 0.05, 1.0)


## Grundstueck im Bereich des oeffentlichen Netzes: Zone mit Anschlusspflicht "wasser" (Wohnen, Misch-, Gewerbe-, Industriegebiet,
## oeffentlich) oder Bestand ohne Parzelle. Aussenbereich: Hofstellen (Acker, Mast) und Zonen ohne Anschlusspflicht haben einen
## eigenen Brunnen, kein Netzbezug, keine Gebuehr (Hofstellen liegen am Ortsrand oft auf unerschlossenen "oeffentlich"-Parzellen).
const OWN_WELL := ["farm", "pig_farm", "cattle_farm"]


func on_net(b: Dictionary) -> bool:
	if str(sim.city.building(int(b.site)).get("type", "")) in OWN_WELL:
		return false
	var p: Dictionary = sim.parcels.of_building(int(b.site))
	if p.is_empty():
		return true
	return "wasser" in Planning.ZONE_RULES.get(str(p.get("zone", "")), {}).get("needs", [])


## Wasseranschluss des Betriebsgrundstuecks (ohne Parzelle: Bestand gilt als angeschlossen).
func connected(b: Dictionary) -> bool:
	var p: Dictionary = sim.parcels.of_building(int(b.site))
	if p.is_empty():
		return true
	return bool(p.get("erschliessung", {}).get("wasser", true))


## Grundstueck mit ausdruecklich gelegtem Wasseranschluss (Erschliessung "wasser" = true): hat seine eigene Zuleitung.
func erschlossen(b: Dictionary) -> bool:
	var p: Dictionary = sim.parcels.of_building(int(b.site))
	return not p.is_empty() and bool(p.get("erschliessung", {}).get("wasser", false))


# ------------------------------------------------------------------ Schritt 2: Leitungsnetz und Druckzonen
## Einspeisepunkte: Strassenfeld vor dem Wasserwerk und vor jedem Hochbehaelter.
func sources_of(k: int) -> Array:
	var out: Array = []
	var w := works_of(k)
	var fs: Array = tanks_of(k)
	if not w.is_empty():
		fs = [w] + fs
	for f in fs:
		var b: Dictionary = sim.city.building(int(f.building))
		if not b.is_empty():
			out.append(Vector2i(b.road))
	return out


## Strassenfelder mit Leitungsdruck: Breitensuche ueber die Strassen der Stadt ab allen Einspeisepunkten, hoechstens ZONE_RANGE
## Felder weit; eine Bruchstelle sperrt das Netz dahinter.
func compute_net(k: int) -> Dictionary:
	var src := sources_of(k)
	var net := {}
	if src.is_empty():
		return net
	var br: Dictionary = breaks.get(str(k), {})
	var shut := {}   # Rohrbruch: Schieber sperren den Strassenabschnitt um die Bruchstelle (BREAK_SPAN Felder in jede Richtung)
	if not br.is_empty():
		var bq: Array = [Vector2i(int(br.cell[0]), int(br.cell[1]))]
		shut[bq[0]] = 0
		var j := 0
		while j < bq.size():
			var c0: Vector2i = bq[j]
			j += 1
			if int(shut[c0]) >= BREAK_SPAN:
				continue
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n0: Vector2i = c0 + dv
				if not shut.has(n0) and sim.city.inside(n0) and sim.city.is_road(n0):
					shut[n0] = int(shut[c0]) + 1
					bq.append(n0)
	var q: Array = []
	for c in src:
		if not shut.has(c) and not net.has(c):
			net[c] = 0
			q.append(c)
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		var d := int(net[c])
		if d >= ZONE_RANGE:
			continue
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dv
			if net.has(n) or shut.has(n) or not sim.city.inside(n) or not sim.city.is_road(n) or sim.city.town_of(n) != k:
				continue
			net[n] = d + 1
			q.append(n)
	return net


## Gebaeude am Netz: Strassenfeld mit Druck; Stadt ohne Einspeisung (Fernwasser) gilt als voll angeschlossen.
func building_on_net(k: int, building_id: int) -> bool:
	if not _net.has(k):
		_net[k] = compute_net(k)
		_fern[k] = sources_of(k).is_empty()
	if bool(_fern[k]):
		return true
	var b: Dictionary = sim.city.building(building_id)
	return not b.is_empty() and _net[k].has(Vector2i(b.road))


## Anteil der Haushalte (mit Wohnung) je Stadt, deren Haus am Netz liegt.
func _household_shares() -> Dictionary:
	var tot := {}
	var on := {}
	for p in sim.citizens.people:
		var u: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
		if u.is_empty():
			continue
		var bid := int(u.building)
		var k: int = sim.towns.of_building(bid)
		tot[k] = int(tot.get(k, 0)) + 1
		if building_on_net(k, bid):
			on[k] = int(on.get(k, 0)) + 1
	var out := {}
	for k in tot:
		out[k] = float(on.get(k, 0)) / float(maxi(1, int(tot[k])))
	return out


# ------------------------------------------------------------------ Tag
func _t(k: int) -> Dictionary:
	var key := str(k)
	if not by_town.has(key):
		by_town[key] = {"m3": 0.0, "abwasser": 0.0, "haushalte_eur": 0.0, "betriebe_eur": 0.0, "kosten": 0.0, "fernwasser_eur": 0.0, "engpass_tage": 0}
	if not month.has(key):
		month[key] = {"m3_verkauft": 0.0, "kosten": 0.0}
	if not sewage.has(key):
		sewage[key] = {"m3": 0.0, "ueberlauf": 0.0, "gebuehr_eur": 0.0, "abgabe_eur": 0.0}
	return by_town[key]


func on_day(_day: int) -> void:
	supplied.clear()
	_net.clear()
	_sewage_today.clear()
	for t in sim.towns.list:
		_pipe_breaks(int(t.id))
	_net.clear()
	var shares := _household_shares()
	var biz_by_town := {}
	var running: Array = sim.biz.items.values().filter(func(b): return b.status in Businesses.RUNNING and not sim.biz.frozen(int(b.owner)))
	running.sort_custom(func(a, b): return float(a.founded) < float(b.founded) or (float(a.founded) == float(b.founded) and str(a.id) < str(b.id)))
	for b in running:
		var k: int = sim.city.town_of_building(int(b.site))
		if not biz_by_town.has(k):
			biz_by_town[k] = []
		biz_by_town[k].append(b)
	for t in sim.towns.list:
		var k := int(t.id)
		_supply_town(k, biz_by_town.get(k, []), float(shares.get(k, 1.0)))
	_treat()
	_check_expansion()


func _supply_town(k: int, businesses: Array, hh_share: float = 1.0) -> void:
	var tt := _t(k)
	var acct := Towns.account_of(k)
	var werk := works_of(k)
	var out := output_of(k)
	var cap := tank_capacity(k)
	var stored := minf(float(storage.get(str(k), cap)), cap)   # neuer Behaelter startet gefuellt
	var avail := float(out.m3) + stored
	var leak := 0.0
	if breaks.has(str(k)):
		leak = minf(BREAK_LEAK, avail)
		avail -= leak
	var pop := float(sim.citizens.population_of(k))
	var need_h := pop * hh_share * L_PER_PERSON
	var need_f := 0.0
	for f in sim.municipal.facilities.values():
		if int(f.town) == k and f.status == "in_betrieb" and building_on_net(k, int(f.building)):
			need_f += facility_need(f)
	var got_h := minf(need_h, avail)
	avail -= got_h
	var got_f := minf(need_f, avail)
	avail -= got_f
	var need_b := 0.0
	var got_b := 0.0
	var off := 0
	var price := tariff_of(k)
	var sew_price := sewage_tariff_of(k)
	var biz_eur := 0.0
	var sew_eur := 0.0
	for b in businesses:
		if not on_net(b):
			sim.biz.unblock(b.id, "wasser")
			continue
		var m3 := biz_need(b)
		need_b += m3
		if not connected(b):
			sim.biz.block(b.id, "wasser", "Kein Wasseranschluss: Grundstück nicht erschlossen")
			continue
		if not building_on_net(k, int(b.site)) and not erschlossen(b):   # erschlossenes Grundstueck: eigene Zuleitung bei der Erschliessung gelegt
			off += 1
			sim.biz.block(b.id, "wasser", "Keine Wasserleitung: %s" % ("Rohrbruch im Netz" if breaks.has(str(k)) else "außerhalb der Druckzone"))
			continue
		if m3 > avail + 1e-6:
			off += 1
			sim.biz.block(b.id, "wasser", "Kein Wasser: %s" % (str(out.grund) if str(out.grund) != "" else "Wasserwerk ausgelastet"))
			continue
		avail -= m3
		got_b += m3
		supplied[b.id] = true
		sim.biz.unblock(b.id, "wasser")
		var led = sim.company(int(b.owner)).ledger
		var sew := m3 * SEWAGE_SHARE * sew_price
		var cost := minf(m3 * price + sew, maxf(0.0, led.cash))
		if cost > 0.0:
			led.book("water", -cost, true, "Wasser/Abwasser %s (%.1f m³)" % [b.name, m3], sim.game_min, acct, b.id)
			biz_eur += cost
			sew_eur += minf(sew, cost)
	if cap > 0.0:
		storage[str(k)] = clampf(avail, 0.0, cap) if is_finite(avail) else cap
	# Haushalte zahlen Wasser- und Abwassergebuehr an die Stadt; Einrichtungen verbrauchen auf eigene Rechnung der Stadt (keine Buchung)
	var h_eur := got_h * price
	var h_sew := got_h * SEWAGE_SHARE * sew_price
	if h_eur + h_sew > 0.0:
		sim.economy.transfer("H0", acct, h_eur + h_sew)
	var total := got_h + got_f + got_b
	var kosten := 0.0
	if werk.is_empty():   # Fernwasser
		kosten = total * IMPORT_PRICE
		sim.economy.transfer(acct, "S0", kosten)
		tt.fernwasser_eur = float(tt.fernwasser_eur) + kosten
	else:
		kosten = sim.municipal.cost_of(werk)   # Sachkosten/Loehne bucht Municipal selbst; hier nur fuer die Gebuehrenrechnung
	var fehl := (need_h - got_h) + (need_f - got_f)
	if fehl > 0.01 or off > 0:
		tt.engpass_tage = int(tt.engpass_tage) + 1
		if fehl > 0.01 and float(last.get(str(k), {}).get("fehl", 0.0)) <= 0.01:
			sim.log_event("%s: Wasserknappheit – %.0f m³ fehlen (%s)." % [sim.towns.name_of(k), fehl,
				str(out.grund) if str(out.grund) != "" else "Wasserwerk ausgelastet"], "warn")
	var sw := total * SEWAGE_SHARE
	_sewage_today[str(k)] = sw
	tt.m3 = float(tt.m3) + total
	tt.abwasser = float(tt.abwasser) + sw
	tt.haushalte_eur = float(tt.haushalte_eur) + h_eur
	tt.betriebe_eur = float(tt.betriebe_eur) + biz_eur - sew_eur
	tt.kosten = float(tt.kosten) + kosten
	sewage[str(k)].gebuehr_eur = float(sewage[str(k)].gebuehr_eur) + h_sew + sew_eur
	month[str(k)].m3_verkauft = float(month[str(k)].m3_verkauft) + got_h + got_b
	month[str(k)].kosten = float(month[str(k)].kosten) + kosten
	last[str(k)] = {"werk": str(werk.get("name", "")), "leistung": snappedf(float(werk.get("capacity", 0.0)), 0.1) if not werk.is_empty() else -1.0,
		"foerderung": snappedf(float(out.m3), 0.1) if not werk.is_empty() else -1.0, "bedarf": snappedf(need_h + need_f + need_b, 0.1),
		"haushalte": snappedf(need_h, 0.1), "einrichtungen": snappedf(need_f, 0.1), "betriebe": snappedf(need_b, 0.1),
		"versorgt": snappedf(total, 0.1), "fehl": snappedf(fehl, 0.1), "abgeschaltet": off, "grund": str(out.grund),
		"abwasser": snappedf(sw, 0.1), "tarif": price, "abwassertarif": sew_price,
		"ohne_anschluss": roundi(pop * (1.0 - hh_share)), "speicher": snappedf(float(storage.get(str(k), 0.0)), 0.1), "speicher_max": snappedf(cap, 0.1),
		"leck": snappedf(leak, 0.1), "rohrbruch": breaks.has(str(k)), "netz_felder": _net.get(k, {}).size()}


# ------------------------------------------------------------------ Schritt 3: Rohrbrueche
func _pipe_breaks(k: int) -> void:
	var key := str(k)
	if breaks.has(key):   # Spielstand: Trupp neu losschicken, falls er fehlt
		var vid := int(breaks[key].vehicle)
		if not sim.fleet.vehicles.any(func(v): return int(v.id) == vid and v.kind == "wassertrupp"):
			_dispatch(k)
		return
	if sources_of(k).is_empty():
		return
	var p := BREAK_P_FROST if sim.wx != null and sim.wx.is_cold() else BREAK_P
	if rng.randf() < p:
		pipe_break(k)


## Rohrbruch an einer zufaelligen Netzstelle (nicht am Einspeisepunkt).
func pipe_break(k: int, cell: Vector2i = Vector2i(-1, -1)) -> bool:
	if breaks.has(str(k)):
		return false
	if cell.x < 0:
		var net := compute_net(k)
		var src := sources_of(k)
		var cand: Array = net.keys().filter(func(c): return not c in src)
		if cand.is_empty():
			return false
		cell = cand[rng.randi() % cand.size()]
	breaks[str(k)] = {"cell": [cell.x, cell.y], "since": sim.game_min, "vehicle": -1}
	_net.erase(k)
	stats.rohrbrueche = int(stats.rohrbrueche) + 1
	sim.log_event("%s: Rohrbruch in der Wasserleitung – Netzabschnitt ohne Wasser, Wassertrupp ist unterwegs." % sim.towns.name_of(k), "warn")
	_dispatch(k)
	return true


func _dispatch(k: int) -> void:
	var br: Dictionary = breaks[str(k)]
	var src := sources_of(k)
	var home: Vector2i = src[0] if not src.is_empty() else sim.fleet.depot_road()
	var to := Vector2i(int(br.cell[0]), int(br.cell[1]))
	var v: Dictionary = sim.fleet._spawn("wassertrupp", home, to, 0.0, home, "Wassertrupp %s: Rohrbruch" % sim.towns.name_of(k))
	v["town"] = k
	br.vehicle = int(v.id)


## Vom Wassertrupp nach getaner Arbeit gemeldet (CityFleet).
func repaired(k: int) -> void:
	if not breaks.has(str(k)):
		return
	var br: Dictionary = breaks[str(k)]
	breaks.erase(str(k))
	_net.erase(k)
	var pay := minf(REPAIR_EUR, maxf(0.0, float(sim.economy.accounts.get(Towns.account_of(k), 0.0))))
	sim.economy.transfer(Towns.account_of(k), "S0", pay)
	stats.reparaturen = int(stats.reparaturen) + 1
	sim.log_event("%s: Rohrbruch repariert (Ausfall %.0f Spielminuten, %s)." % [sim.towns.name_of(k), sim.game_min - float(br.since), Catalog.money(pay)], "good")


# ------------------------------------------------------------------ Schritt 4: Klaeranlage
## Zulauf aller Staedte, Klaerleistung = Kapazitaet x Besetzung (ohne Strom 0); der Rest laeuft ungeklaert ueber, jede Stadt zahlt
## die Abwasserabgabe fuer ihren Anteil am Ueberlauf.
func _treat() -> void:
	var f := plant()
	if f.is_empty():
		plant_last = {}
		return
	var total := 0.0
	for key in _sewage_today:
		total += float(_sewage_today[key])
		sewage_month[key] = float(sewage_month.get(key, 0.0)) + float(_sewage_today[key])
	var grund := ""
	var cap: float = float(f.capacity) * sim.municipal.staffing(f.id)
	if not power_ok(int(f.town)):
		cap = 0.0
		grund = "Kläranlage ohne Strom"
	elif sim.municipal.staffing(f.id) < 1.0:
		grund = "Kläranlage unterbesetzt"
	var treated := minf(total, cap)
	var over := total - treated
	if over > 0.01 and float(plant_last.get("ueberlauf", 0.0)) <= 0.01:
		sim.log_event("Kläranlage: %.0f m³ Abwasser laufen ungeklärt über (%s)." % [over, grund if grund != "" else "Kapazität erschöpft"], "warn")
	for key in _sewage_today:
		var part := over * float(_sewage_today[key]) / maxf(total, 0.001)
		_t(int(key))
		sewage[key].m3 = float(sewage[key].m3) + float(_sewage_today[key])
		if part > 0.0:
			var fee := minf(part * OVERFLOW_FEE, maxf(0.0, float(sim.economy.accounts.get(Towns.account_of(int(key)), 0.0))))
			sim.economy.transfer(Towns.account_of(int(key)), "X0", fee)
			sewage[key].ueberlauf = float(sewage[key].ueberlauf) + part
			sewage[key].abgabe_eur = float(sewage[key].abgabe_eur) + fee
	plant_month += sim.municipal.cost_of(f)
	plant_last = {"name": str(f.name), "zulauf": snappedf(total, 0.1), "geklaert": snappedf(treated, 0.1), "ueberlauf": snappedf(over, 0.1),
		"leistung": snappedf(float(f.capacity), 0.1), "grund": grund}


# ------------------------------------------------------------------ Schritt 5: Ausbau ueber Baufirmen
func _check_expansion() -> void:
	for t in sim.towns.list:
		var k := int(t.id)
		var h: Dictionary = last.get(str(k), {})
		var w := works_of(k)
		if not w.is_empty() and not h.is_empty():
			_tight(w, float(h.bedarf) > EXPAND_RATIO * float(w.capacity), k)
		var tk: Array = tanks_of(k)
		if not tk.is_empty() and not h.is_empty():   # Vorrat soll einen Tag Bedarf ueberbruecken
			_tight(tk[0], tank_capacity(k) < float(h.bedarf), k)
	var f := plant()
	if not f.is_empty() and not plant_last.is_empty():
		_tight(f, float(plant_last.zulauf) > EXPAND_RATIO * float(f.capacity), int(f.town))


func _tight(f: Dictionary, over: bool, k: int) -> void:
	tight[str(f.id)] = int(tight.get(str(f.id), 0)) + 1 if over else 0
	if int(tight[str(f.id)]) >= EXPAND_DAYS and not expansions.values().has(str(f.id)):
		expand(f, k)


## Ausbauprojekt: Stadt (bzw. bei der Klaeranlage alle Staedte nach Abwasseranteil) schreibt aus, Baufirma baut, Kapazitaet x1,5.
func expand(f: Dictionary, k: int) -> Dictionary:
	if expansions.values().has(str(f.id)):
		return {"ok": false, "msg": "Ausbau läuft schon."}
	var M: Mayor = sim.towns.mayor(k)
	var cost := snappedf(float(Municipal.TYPES[f.code].cost) * EXPAND_SHARE, 1000.0)
	var prj: Dictionary = M.add_works_project("wasserausbau", str(f.id), cost, EXPAND_BUILD_DAYS, {}, "Ausbau %s (Kapazität ×%.1f)" % [f.name, EXPAND_FACTOR])
	if f.has("shares"):   # Klaeranlage: Kosten nach den Anteilen am Abwasser
		M.commitments = maxf(0.0, M.commitments - cost)
		prj["shares"] = {}
		for key in f.shares:
			var amt := snappedf(cost * float(f.shares[key]), 1.0)
			sim.towns.mayor(int(key)).commitments += amt
			prj.shares[str(key)] = amt
	expansions[str(prj.id)] = str(f.id)
	tight[str(f.id)] = 0
	sim.log_event("%s: %s dauerhaft ausgelastet – Ausbau ausgeschrieben als %s (%s)." % [sim.towns.name_of(k), f.name, prj.id, Catalog.money(cost)], "info")
	return {"ok": true, "ref": prj.id}


## Abnahme durch die Baufirma (Construction._finish_public).
func on_expansion_done(prj: Dictionary) -> void:
	var fid := str(expansions.get(str(prj.id), prj.get("ref", "")))
	expansions.erase(str(prj.id))
	var f: Dictionary = sim.municipal.facilities.get(fid, {})
	if f.is_empty():
		return
	f.capacity = int(ceil(float(f.capacity) * EXPAND_FACTOR))
	stats.ausbauten = int(stats.ausbauten) + 1
	sim.log_event("%s: %s ausgebaut – Kapazität jetzt %d m³." % [sim.towns.name_of(int(f.town)), f.name, int(f.capacity)], "good")


# ------------------------------------------------------------------ Monat
## Monatsende: kostendeckende Gebuehr fuer den naechsten Monat (Kosten / verkaufte m3, begrenzt); Abwasser: Anteile der Staedte an der
## Klaeranlage nach Menge und Abwassergebuehr je Stadt = Kostenanteil / eigene m3.
func _month() -> void:
	for key in month:
		var m: Dictionary = month[key]
		if float(m.m3_verkauft) > 1.0:
			tariff[key] = snappedf(clampf(float(m.kosten) / float(m.m3_verkauft), TARIFF_MIN, TARIFF_MAX), 0.01)
		month[key] = {"m3_verkauft": 0.0, "kosten": 0.0}
	var f := plant()
	var total := 0.0
	for key in sewage_month:
		total += float(sewage_month[key])
	if not f.is_empty() and total > 1.0:
		var sh := {}
		for key in sewage_month:
			sh[key] = float(sewage_month[key]) / total
			if float(sewage_month[key]) > 1.0:
				sewage_tariff[key] = snappedf(clampf(plant_month * float(sh[key]) / float(sewage_month[key]), SEWAGE_TARIFF_MIN, SEWAGE_TARIFF_MAX), 0.01)
		f["shares"] = sh
	sewage_month = {}
	plant_month = 0.0


func summary(k: int = -1) -> Dictionary:
	if k >= 0:
		return {"tarif_eur_m3": tariff_of(k), "abwasser_eur_m3": sewage_tariff_of(k), "heute": last.get(str(k), {}), "gesamt": by_town.get(str(k), {}),
			"abwasser": sewage.get(str(k), {}), "rohrbruch": breaks.has(str(k)), "hochbehaelter": tanks_of(k).map(func(f): return f.name),
			"ausbau_laeuft": expansions.values().filter(func(fid): return int(sim.municipal.facilities.get(fid, {}).get("town", -1)) == k).size()}
	var out := {}
	for t in sim.towns.list:
		out[str(int(t.id))] = summary(int(t.id))
	return out


## Kurzfassung fuer die Beobachtung eines Buergermeisters.
func mayor_view(k: int) -> Dictionary:
	var h: Dictionary = last.get(str(k), {})
	if h.is_empty():
		return {}
	return {"bedarf_m3": h.bedarf, "leistung_m3": h.leistung, "fehl_m3": h.fehl, "ohne_anschluss": h.ohne_anschluss, "speicher_m3": h.speicher,
		"rohrbruch": h.rohrbruch, "gebuehr": h.tarif, "abwassergebuehr": h.abwassertarif, "klaeranlage": plant_last.duplicate(),
		"ausbau_laeuft": summary(k).ausbau_laeuft}


func to_dict() -> Dictionary:
	return {"tariff": tariff, "by_town": by_town, "month": month, "last": last, "storage": storage, "breaks": breaks, "sewage_tariff": sewage_tariff,
		"sewage": sewage, "sewage_month": sewage_month, "plant_month": plant_month, "plant_last": plant_last, "tight": tight, "expansions": expansions,
		"stats": stats}


func from_dict(d: Dictionary) -> void:
	tariff = d.get("tariff", {})
	by_town = d.get("by_town", {})
	month = d.get("month", {})
	last = d.get("last", {})
	storage = d.get("storage", {})
	breaks = d.get("breaks", {})
	sewage_tariff = d.get("sewage_tariff", {})
	sewage = d.get("sewage", {})
	sewage_month = d.get("sewage_month", {})
	plant_month = float(d.get("plant_month", 0.0))
	plant_last = d.get("plant_last", {})
	tight = d.get("tight", {})
	expansions = d.get("expansions", {})
	var st0: Dictionary = stats.duplicate()
	st0.merge(d.get("stats", {}), true)
	stats = st0
