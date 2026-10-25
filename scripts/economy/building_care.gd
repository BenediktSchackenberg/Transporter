class_name BuildingCare
extends RefCounted
## Gebaeudezustand, Instandhaltung, Renovierung und Stadtviertel-Entwicklung (Auftrag 3).
##
## Zustand 0..100. Er sinkt mit der Zeit (schneller bei Regen und Frost) und steigt durch Instandhaltung.
##  - Stadtgebaeude (Kunden): die privaten Eigentuemer pflegen aus dem Haushaltssektor; ist H0 knapp, verwahrlosen sie.
##  - Firmeneinrichtungen: der Unternehmer muss selbst zahlen (fund_maintenance, commission_renovation). Ohne Pflege steigen die
##    Betriebskosten, und ab einem schlechten Zustand wird die Einrichtung baufaellig (sichtbar abgenutzt).
## Sichtbare Zustaende: gepflegt (>= 70), genutzt (40-69), vernachlaessigt (< 40), baufaellig (< 20).

const START_MIN := 55.0
const START_MAX := 95.0
const DECAY_BASE := 1.4               # Punkte je Spielmonat
const FACILITY_DECAY := 2.0
const POINT_COST_RATE := 0.0015       # Kosten je Zustandspunkt = Investition x Rate
const CITY_UPKEEP_PER_BUILDING := 14.0   # EUR je Gebaeude und Monat, wenn die Eigentuemer zahlen koennen
const H0_COMFORT := 150000.0

var sim: Simulation
var condition := {}        # Gebaeude-ID (int) -> Zustand
var spent_city := 0.0      # von Eigentuemern in Stadtgebaeude gesteckt
var district_log: Array = []   # [[Monat, [Mittelwert je Viertel]]]


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)
	for b in s.city.buildings:
		if _tracked(b):
			condition[int(b.id)] = START_MIN + float(absi(hash("%d_%d" % [s.city.seed_value, b.id])) % 100) / 100.0 * (START_MAX - START_MIN)


static func _tracked(b: Dictionary) -> bool:
	return b.type != "plot" and b.get("role", "") in ["customer", "dealer", "workshop", "job_board", "staffing"]


func state_of(c: float) -> String:
	if c >= 70.0:
		return "gepflegt"
	if c >= 40.0:
		return "genutzt"
	if c >= 20.0:
		return "vernachlässigt"
	return "baufällig"


## Farbton fuer die Anzeige: gepflegt = unveraendert, verwahrlost = dunkler und braeunlich.
static func tint(c: float) -> Color:
	var k := clampf((70.0 - c) / 70.0, 0.0, 1.0)
	return Color(1.0 - 0.34 * k, 1.0 - 0.38 * k, 1.0 - 0.46 * k, 1.0)


func get_condition(building_id: int) -> float:
	return float(condition.get(building_id, 70.0))


func on_month(_month: int) -> void:
	var bad_weather := 0.0
	if sim.wx.is_rain() or sim.wx.is_snow():
		bad_weather += 0.5
	if sim.wx.is_cold():
		bad_weather += 0.5
	# Eigentuemer pflegen, solange der Haushaltssektor zahlungskraeftig ist
	var comfort := clampf(float(sim.economy.accounts.H0) / H0_COMFORT, 0.0, 1.0)
	var paid := 0.0
	for id in condition.keys():
		var wobble := 0.6 + float(absi(hash("%d_%d" % [id, _month])) % 80) / 100.0   # 0.6 .. 1.4, je Gebaeude und Monat
		var decay := (DECAY_BASE + bad_weather) * wobble
		var repair := 0.0
		if comfort > 0.0 and float(condition[id]) < 85.0:
			repair = 2.4 * comfort * wobble
			paid += CITY_UPKEEP_PER_BUILDING * comfort
		condition[id] = clampf(float(condition[id]) - decay + repair, 0.0, 100.0)
	if paid > 0.0:
		sim.economy.transfer("H0", "S0", paid)
		spent_city += paid
	# Firmeneinrichtungen verschleissen
	for f in sim.estate.facilities.values():
		if f.status == "fertig":
			f["condition"] = clampf(float(f.get("condition", 100.0)) - FACILITY_DECAY * (1.0 + bad_weather * 0.4), 0.0, 100.0)
			if float(f.condition) < 40.0 and not f.get("warned", false):
				f["warned"] = true
				sim.notify(f.owner, "%s %s ist vernachlässigt (Zustand %d): höhere Betriebskosten, Renovierung nötig (commission_renovation)." % [
					Estate.FACILITIES[f.typ].name, f.id, int(f.condition)])
			elif float(f.condition) >= 55.0:
				f["warned"] = false
	district_log.append([_month, district_means()])
	if district_log.size() > 120:
		district_log.pop_front()


## Mittlerer Gebaeudezustand je Stadtviertel.
func district_means() -> Array:
	var sums := []
	var counts := []
	for i in Catalog.DISTRICTS.size():
		sums.append(0.0)
		counts.append(0)
	for id in condition:
		var d: int = sim.city.building(id).get("district", 0)
		sums[d] += float(condition[id])
		counts[d] += 1
	var out: Array = []
	for i in sums.size():
		out.append(snappedf(sums[i] / maxf(counts[i], 1), 0.1))
	return out


## Kosten, die Einrichtung um 'points' Zustandspunkte zu verbessern.
func facility_cost(f: Dictionary, points: float) -> float:
	return snappedf(maxf(float(f.invest), 500.0) * POINT_COST_RATE * points, 0.01)


## Betriebskostenaufschlag durch schlechten Zustand (1.0 = normal, bis 1.5 bei Zustand 0).
static func upkeep_factor(f: Dictionary) -> float:
	return 1.0 + 0.5 * clampf((70.0 - float(f.get("condition", 100.0))) / 70.0, 0.0, 1.0)


## Instandhaltung: der Unternehmer zahlt einen Betrag, daraus werden Zustandspunkte.
func fund_maintenance(cid: int, fid: String, amount: float) -> Dictionary:
	var f: Dictionary = sim.estate.facilities.get(fid, {})
	if f.is_empty() or int(f.owner) != cid:
		return {"ok": false, "msg": "Einrichtung %s gehört dir nicht." % fid}
	if f.status != "fertig":
		return {"ok": false, "msg": "%s ist noch nicht fertig." % fid}
	var cur := float(f.get("condition", 100.0))
	if cur >= 99.5:
		return {"ok": false, "msg": "%s ist in bestem Zustand." % fid}
	var c := sim.company(cid)
	var per_point := facility_cost(f, 1.0)
	var points := minf(amount / maxf(per_point, 0.01), 100.0 - cur)
	var cost := snappedf(points * per_point, 0.01)
	if cost <= 0.0 or c.ledger.cash < cost:
		return {"ok": false, "msg": "Instandhaltung kostet %s für %.1f Punkte (%s je Punkt)." % [Catalog.money(cost), points, Catalog.money(per_point)]}
	c.ledger.book("property_costs", -cost, true, "Instandhaltung " + fid, sim.game_min)
	f["condition"] = cur + points
	return {"ok": true, "msg": "%s instandgehalten: Zustand %d → %d für %s." % [fid, int(cur), int(f.condition), Catalog.money(cost)]}


## Renovierung: Zustand auf 100, Kosten nach Bedarf (mit 20 % Aufschlag fuer die Baufirma).
func renovate(cid: int, fid: String) -> Dictionary:
	var f: Dictionary = sim.estate.facilities.get(fid, {})
	if f.is_empty() or int(f.owner) != cid:
		return {"ok": false, "msg": "Einrichtung %s gehört dir nicht." % fid}
	var cur := float(f.get("condition", 100.0))
	if cur >= 85.0:
		return {"ok": false, "msg": "%s ist noch in gutem Zustand (%d); Instandhaltung genügt." % [fid, int(cur)]}
	var c := sim.company(cid)
	var cost := snappedf(facility_cost(f, 100.0 - cur) * 1.2, 0.01)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Renovierung kostet %s." % Catalog.money(cost)}
	c.ledger.book("property_costs", -cost, true, "Renovierung " + fid, sim.game_min)
	f["condition"] = 100.0
	f["warned"] = false
	sim.log_event("%s renoviert %s (%s)." % [c.company_name, Estate.FACILITIES[f.typ].name, Catalog.money(cost)], "info", cid)
	return {"ok": true, "msg": "%s renoviert, Zustand 100 für %s." % [fid, Catalog.money(cost)]}


func summary_of(cid: int) -> Array:
	var out: Array = []
	for f in sim.estate.facilities.values():
		if int(f.owner) == cid and f.status == "fertig":
			out.append({"id": f.id, "art": Estate.FACILITIES[f.typ].name, "zustand": int(f.get("condition", 100.0)), "stufe": state_of(float(f.get("condition", 100.0)))})
	return out


func to_dict() -> Dictionary:
	var c := {}
	for id in condition:
		c[str(id)] = snappedf(condition[id], 0.1)
	return {"condition": c, "spent_city": spent_city, "district_log": district_log.slice(-60)}


func from_dict(d: Dictionary) -> void:
	for id in d.get("condition", {}):
		condition[int(id)] = float(d.condition[id])
	spent_city = float(d.get("spent_city", 0.0))
	district_log = d.get("district_log", [])
