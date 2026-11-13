class_name FinanceHistory
extends RefCounted
## Finanzverlauf je Spieltag fuer das Finanzdashboard (keine zweite Buchhaltung): zum Tageswechsel eine Momentaufnahme der
## kumulierten Buchungen (Ledger.totals je Kategorie), Bargeld, Schulden, Vermoegen, Flotte, Personal und Auftragsstatistik je Firma;
## Kasse, Einnahmen/Ausgaben, Einwohner, Zustimmung und Investitionen je Stadt; Kennzahlen der ganzen Region.
## Zeitraumwerte (heute, 7, 30 Tage, gesamt) sind Differenzen zweier Momentaufnahmen - Umsatz, Kosten, Ergebnis, Liquiditaet und
## Vermoegen bleiben getrennte Groessen. Kreditauszahlungen/-tilgungen sind keine Erloese/Kosten (sie bewegen nur Bargeld und Schulden).

const KEEP_DAYS := 400
const COST_GROUPS := {"Löhne": ["wages", "hire_fees", "training"], "Treibstoff": ["fuel", "supplies", "energy", "water"], "Reparaturen": ["repairs"],
	"Fahrzeuge (Abschreibung)": ["depreciation"], "Gebäude, Miete, Büro": ["rent", "office", "property_costs", "security", "insurance"],
	"Kreditzinsen": ["interest"], "Strafen und Schäden": ["penalties", "fines", "sabotage"], "Sonstige Kosten": ["trade_expense", "marketing", "admin", "tax", "internal"]}

var sim
var companies := {}     # Firma -> [Momentaufnahme je Tag]
var towns := {}         # Stadt -> [Momentaufnahme je Tag]
var world: Array = []   # [Momentaufnahme je Tag]
var _town_prev := {}    # Stadt -> {cash, outflow} fuer Tageseinnahmen/-ausgaben


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)


func on_day(day: int) -> void:
	for c in sim.companies:
		var L: Ledger = c.ledger
		var fleet: Array = sim.company_vehicles(c.id)
		var veh_book := 0.0
		for v in fleet:
			veh_book += float(v.book_value)
		_push(companies, c.id, {"day": day, "bargeld": snappedf(L.cash, 0.01), "schulden": snappedf(L.debt, 0.01), "totals": L.totals.duplicate(),
			"vermoegen": snappedf(L.cash + veh_book + float(c.property_book) - L.debt, 0.01), "fahrzeuge": fleet.size(),
			"personal": sim.personnel.employed(c.id).size(), "geliefert": int(c.stats.completed), "puenktlich": int(c.stats.on_time),
			"verspaetet": int(c.stats.late), "gescheitert": int(c.stats.failed), "laufend": sim.executor.active_contracts(c.id), "ruf": snappedf(c.reputation, 0.1)})
	if sim.towns != null:
		for k in sim.towns.count():
			var M: Mayor = sim.towns.mayor(k)
			var acct := Towns.account_of(k)
			var cash := float(sim.economy.accounts.get(acct, 0.0))
			var out := float(sim.economy.outflow.get(acct, 0.0))
			var prev: Dictionary = _town_prev.get(k, {"cash": cash, "out": 0.0})
			var spent := out - float(prev.out) if out >= float(prev.out) else out   # Monatswechsel: Abfluss beginnt neu
			var income := (cash - float(prev.cash)) + spent
			_town_prev[k] = {"cash": cash, "out": out}
			var invest := 0.0
			var running := 0
			for prj in M.projects.values():
				if str(prj.status) == "fertig":
					invest += float(prj.cost)
				elif str(prj.status) in ["beschlossen", "ausgeschrieben", "beauftragt", "laufend", "geplant"]:
					running += 1
			_push(towns, k, {"day": day, "kasse": snappedf(cash, 0.01), "verfuegbar": snappedf(M.available_budget(), 0.01),
				"einnahmen": snappedf(maxf(0.0, income), 0.01), "ausgaben": snappedf(maxf(0.0, spent), 0.01), "einwohner": sim.citizens.population_of(k),
				"zustimmung": snappedf(M.approval, 0.1), "arbeitslos": sim.citizens.unemployed_of(k), "investiert": snappedf(invest, 1.0),
				"projekte_laufend": running, "gebunden": snappedf(M.commitments, 1.0)})
	var delivered := 0
	for c in sim.companies:
		delivered += int(c.stats.completed)
	world.append({"day": day, "einwohner": sim.citizens.population(), "beschaeftigt": sim.citizens.employed_total(),
		"arbeitslos": sim.citizens.unemployed_total(), "firmen": sim.companies.filter(func(c): return c.status not in ["geschlossen", "verwertung"]).size(),
		"insolvent": sim.companies.filter(func(c): return c.status in ["insolvenz", "verwertung", "geschlossen"]).size(), "lieferungen": delivered,
		"betriebe": sim.biz.items.size(), "grosslager_umsatz": float(sim.hub.stats.umsatz) if sim.hub != null and sim.hub.enabled else 0.0,
		"importe": float(sim.hub.stats.import) if sim.hub != null and sim.hub.enabled else 0.0})
	if world.size() > KEEP_DAYS:
		world.pop_front()


func _push(store: Dictionary, key: int, snap: Dictionary) -> void:
	var arr: Array = store.get(key, [])
	arr.append(snap)
	if arr.size() > KEEP_DAYS:
		arr.pop_front()
	store[key] = arr


## Zeitraumwerte einer Firma: days = 0 (gesamte Partie) oder 1/7/30. Umsatz/Kosten aus der Differenz der Buchungskategorien
## (aktueller Stand gegen die Momentaufnahme vor `days` Tagen); Bargeld/Schulden/Vermoegen aktuell.
func company_period(cid: int, days: int) -> Dictionary:
	var c = sim.company(cid)
	if c == null:
		return {}
	var L: Ledger = c.ledger
	var base := {}
	var arr: Array = companies.get(cid, [])
	if days > 0 and not arr.is_empty():
		var target := GameCalendar.day_of(sim.game_min) - days
		for s in arr:
			if int(s.day) <= target:
				base = s.totals
	var delta := {}
	for k in L.totals:
		delta[k] = float(L.totals[k]) - float(base.get(k, 0.0))
	var rev := 0.0
	var cost := 0.0
	for k in delta:
		if k in Ledger.INCOME:
			rev += delta[k]
		else:
			cost -= delta[k]   # Erstattungen mindern die Kosten; Ergebnis = Summe aller Erfolgsbuchungen (= Ledger.profit)
	var groups := {}
	for g in COST_GROUPS:
		var s := 0.0
		for k in COST_GROUPS[g]:
			s += maxf(0.0, -float(delta.get(k, 0.0)))
		if s > 0.5:
			groups[g] = snappedf(s, 0.01)
	var veh_book := 0.0
	for v in sim.company_vehicles(cid):
		veh_book += float(v.book_value)
	return {"umsatz": snappedf(rev, 0.01), "kosten": snappedf(cost, 0.01), "ergebnis": snappedf(rev - cost, 0.01), "kostenstruktur": groups,
		"bargeld": snappedf(L.cash, 0.01), "schulden": snappedf(L.debt, 0.01), "vermoegen": snappedf(L.cash + veh_book + float(c.property_book) - L.debt, 0.01),
		"zeitraum": "gesamte Partie" if days <= 0 else ("heute" if days == 1 else "letzte %d Spieltage" % days)}


## Reihe fuer Diagramme: [[Tag, Wert], ...]. field: bargeld | schulden | vermoegen | umsatz | kosten | ergebnis (je Tag) | ...
func company_series(cid: int, field: String) -> Array:
	var out: Array = []
	var arr: Array = companies.get(cid, [])
	var prev := {}
	for s in arr:
		match field:
			"umsatz", "kosten", "ergebnis":
				var rev := 0.0
				var cost := 0.0
				for k in s.totals:
					var d := float(s.totals[k]) - float(prev.get(k, 0.0))
					if k in Ledger.INCOME:
						rev += d
					else:
						cost -= d
				prev = s.totals
				out.append([int(s.day), rev if field == "umsatz" else (cost if field == "kosten" else rev - cost)])
			_:
				out.append([int(s.day), float(s.get(field, 0.0))])
	return out


func town_series(k: int, field: String) -> Array:
	return (towns.get(k, []) as Array).map(func(s): return [int(s.day), float(s.get(field, 0.0))])


func world_series(field: String) -> Array:
	return world.map(func(s): return [int(s.day), float(s.get(field, 0.0))])


## Trend einer Reihe: +1 steigt, -1 faellt, 0 gleich (letzter Wert gegen den vor `back` Tagen).
static func trend(series: Array, back: int = 3) -> int:
	if series.size() < 2:
		return 0
	var a := float(series[maxi(0, series.size() - 1 - back)][1])
	var b := float(series[-1][1])
	if absf(b - a) < maxf(1.0, absf(a) * 0.02):
		return 0
	return 1 if b > a else -1


func to_dict() -> Dictionary:
	var cs := {}
	for k in companies:
		cs[str(k)] = (companies[k] as Array).slice(-120)
	var ts := {}
	for k in towns:
		ts[str(k)] = (towns[k] as Array).slice(-120)
	return {"companies": cs, "towns": ts, "world": world.slice(-120)}


func from_dict(d: Dictionary) -> void:
	companies = {}
	for k in d.get("companies", {}):
		companies[int(k)] = d.companies[k]
	towns = {}
	for k in d.get("towns", {}):
		towns[int(k)] = d.towns[k]
	world = d.get("world", [])
