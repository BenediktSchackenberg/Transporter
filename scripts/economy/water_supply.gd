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
## Abwasser (90 % des Verbrauchs) wird schon erfasst; Kanal und Klaeranlage folgen in Schritt 4.

const L_PER_PERSON := 0.12          # m3 je Einwohner und Spieltag
const BIZ_BASE := 0.4               # m3 je laufendem Betrieb und Tag
const BIZ_PER_KW := 0.01            # zusaetzlich je kW Anschlussleistung
const SEWAGE_SHARE := 0.9           # Anteil des Verbrauchs, der als Abwasser anfaellt
const TARIFF_START := 2.2           # EUR/m3 im ersten Monat
const TARIFF_MIN := 1.5
const TARIFF_MAX := 6.0
const IMPORT_PRICE := 1.8           # Fernwasser je m3 (Stadt ohne eigenes Werk)
const CODE := "WW-01"

var sim
var tariff := {}       # Stadt (str) -> EUR/m3
var by_town := {}      # Stadt (str) -> Summen seit Spielbeginn {m3, abwasser, haushalte_eur, betriebe_eur, kosten, fernwasser_eur, engpass_tage}
var month := {}        # Stadt (str) -> {m3_verkauft, kosten} des laufenden Monats
var last := {}         # Stadt (str) -> letzter Tag {werk, leistung, bedarf, haushalte, einrichtungen, betriebe, versorgt, fehl, abgeschaltet, grund}
var supplied := {}     # Betriebs-ID -> true (heute versorgt)


func setup(simulation) -> void:
	sim = simulation
	if not enabled():
		return
	sim.day_changed.connect(on_day)
	sim.month_changed.connect(func(_m): _month())


func enabled() -> bool:
	return sim != null and sim.towns != null and sim.towns.is_region()


func works_of(k: int) -> Dictionary:
	for f in sim.municipal.of_town(k, "wasser"):
		if str(f.code) == CODE and f.status == "in_betrieb":
			return f
	return {}


func tariff_of(k: int) -> float:
	return float(tariff.get(str(k), TARIFF_START))


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


func _t(k: int) -> Dictionary:
	var key := str(k)
	if not by_town.has(key):
		by_town[key] = {"m3": 0.0, "abwasser": 0.0, "haushalte_eur": 0.0, "betriebe_eur": 0.0, "kosten": 0.0, "fernwasser_eur": 0.0, "engpass_tage": 0}
	if not month.has(key):
		month[key] = {"m3_verkauft": 0.0, "kosten": 0.0}
	return by_town[key]


func on_day(_day: int) -> void:
	supplied.clear()
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
		_supply_town(k, biz_by_town.get(k, []))


func _supply_town(k: int, businesses: Array) -> void:
	var tt := _t(k)
	var acct := Towns.account_of(k)
	var werk := works_of(k)
	var out := output_of(k)
	var avail := float(out.m3)
	var need_h := float(sim.citizens.population_of(k)) * L_PER_PERSON
	var need_f := 0.0
	for f in sim.municipal.facilities.values():
		if int(f.town) == k and f.status == "in_betrieb":
			need_f += facility_need(f)
	var got_h := minf(need_h, avail)
	avail -= got_h
	var got_f := minf(need_f, avail)
	avail -= got_f
	var need_b := 0.0
	var got_b := 0.0
	var off := 0
	var price := tariff_of(k)
	var biz_eur := 0.0
	for b in businesses:
		if not on_net(b):
			sim.biz.unblock(b.id, "wasser")
			continue
		var m3 := biz_need(b)
		need_b += m3
		if not connected(b):
			sim.biz.block(b.id, "wasser", "Kein Wasseranschluss: Grundstück nicht erschlossen")
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
		var cost := minf(m3 * price, maxf(0.0, led.cash))
		if cost > 0.0:
			led.book("water", -cost, true, "Wasser %s (%.1f m³)" % [b.name, m3], sim.game_min, acct, b.id)
			biz_eur += cost
	# Haushalte zahlen ihre Gebuehr an die Stadt; Einrichtungen verbrauchen auf eigene Rechnung der Stadt (keine Buchung)
	var h_eur := got_h * price
	if h_eur > 0.0:
		sim.economy.transfer("H0", acct, h_eur)
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
	tt.m3 = float(tt.m3) + total
	tt.abwasser = float(tt.abwasser) + total * SEWAGE_SHARE
	tt.haushalte_eur = float(tt.haushalte_eur) + h_eur
	tt.betriebe_eur = float(tt.betriebe_eur) + biz_eur
	tt.kosten = float(tt.kosten) + kosten
	month[str(k)].m3_verkauft = float(month[str(k)].m3_verkauft) + got_h + got_b
	month[str(k)].kosten = float(month[str(k)].kosten) + kosten
	last[str(k)] = {"werk": str(werk.get("name", "")), "leistung": snappedf(float(werk.get("capacity", 0.0)), 0.1) if not werk.is_empty() else -1.0,
		"foerderung": snappedf(float(out.m3), 0.1) if not werk.is_empty() else -1.0, "bedarf": snappedf(need_h + need_f + need_b, 0.1),
		"haushalte": snappedf(need_h, 0.1), "einrichtungen": snappedf(need_f, 0.1), "betriebe": snappedf(need_b, 0.1),
		"versorgt": snappedf(total, 0.1), "fehl": snappedf(fehl, 0.1), "abgeschaltet": off, "grund": str(out.grund),
		"abwasser": snappedf(total * SEWAGE_SHARE, 0.1), "tarif": price}


## Monatsende: kostendeckende Gebuehr fuer den naechsten Monat (Kosten / verkaufte m3, begrenzt).
func _month() -> void:
	for key in month:
		var m: Dictionary = month[key]
		if float(m.m3_verkauft) > 1.0:
			tariff[key] = snappedf(clampf(float(m.kosten) / float(m.m3_verkauft), TARIFF_MIN, TARIFF_MAX), 0.01)
		month[key] = {"m3_verkauft": 0.0, "kosten": 0.0}


func summary(k: int = -1) -> Dictionary:
	if k >= 0:
		return {"tarif_eur_m3": tariff_of(k), "heute": last.get(str(k), {}), "gesamt": by_town.get(str(k), {})}
	var out := {}
	for t in sim.towns.list:
		out[str(int(t.id))] = summary(int(t.id))
	return out


func to_dict() -> Dictionary:
	return {"tariff": tariff, "by_town": by_town, "month": month, "last": last}


func from_dict(d: Dictionary) -> void:
	tariff = d.get("tariff", {})
	by_town = d.get("by_town", {})
	month = d.get("month", {})
	last = d.get("last", {})
