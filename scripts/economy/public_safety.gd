class_name PublicSafety
extends RefCounted
## Sicherheit und Gesundheit (Auftrag 10, Etappe 3, docs/RESIDENTS.md). Baut auf den Buergern aus `Citizens` auf (gleiche Datensaetze):
##  - Gesundheit: Buerger erkranken (eher bei Unglueck und im Alter). Leichte Faelle gehen zur Arztpraxis und fehlen ein paar Tage;
##    schwere Faelle (oder wenn die Praxen ueberlastet sind) holt der Krankenwagen ins Krankenhaus. Behandlungskosten zahlt die
##    Stadtkasse (Ressort Gesundheit) an die Dienstleister (P0 -> S0).
##  - Kriminalitaet: Geldnot, Arbeitslosigkeit und Unglueck machen Ladendiebstahl wahrscheinlicher (Beute S0 -> Konto des Taeters).
##    Die Polizei findet Taeter abhaengig von ihrer Personalstaerke; Festnahme mit Streifenwagen, Beute wird erstattet (R0 -> S0),
##    Haft 30-90 Tage: Arbeit weg; Mieter verlieren bei langer Haft die Wohnung, Eigentuemer mit Steuerrueckstand ihr Haus.
##  - Streifenwagen sichern gesperrte Strassen ab (stehen an der Sperrung) und fahren sonst Streife.
## Personal: Arbeitgeber "polizei" und "gesundheit" in Citizens (Loehne aus der Stadtkasse, das Personal wohnt in der Stadt).
## Zufall: zustandslos aus Buerger-ID und Tag (Citizens.roll), damit Speichern/Laden und Wiederholung exakt bleiben.

const DEFAULTS := {"krankheit_je_tag": 0.004, "schwer_anteil": 0.25, "kriminalitaet_je_tag": 0.0006, "haft_tage_min": 30, "haft_tage_max": 90,
	"wohnung_weg_ab_tagen": 60, "arzt_patienten_je_kraft_tag": 3.0, "kosten_arzt": 60.0, "kosten_krankenhaus_tag": 250.0,
	"aufklaerung_je_polizist": 0.025, "streifenwagen": 2, "krankenwagen": 1}
const ICON_CRIME := "verbrechen"

var sim
var police := -1                         # Gebaeude-IDs
var prison := -1
var doctors: Array = []
var hospital := -1
var vehicles: Array = []                 # {kind, mover, task, home}
var stats := {"erkrankt": 0, "arzt": 0, "krankenhaus": 0, "straftaten": 0, "festnahmen": 0, "haft_wohnung_verloren": 0, "haus_verloren": 0, "kosten": 0.0}
var month_stats := {}
var _day := -1


static func cfg() -> Dictionary:
	var c: Dictionary = DEFAULTS.duplicate()
	var p: Dictionary = Population.cfg().get("sicherheit_gesundheit", {})
	for k in p:
		c[k] = p[k]
	return c


func setup(simulation) -> void:
	sim = simulation
	police = _first("police")
	prison = _first("prison")
	doctors = sim.city.buildings.filter(func(b): return b.role == "doctor").map(func(b): return int(b.id))
	hospital = -1
	for b in sim.city.buildings:
		if b.type == "clinic":
			hospital = int(b.id)
			break
	vehicles.clear()
	var c := cfg()
	if police >= 0:
		for i in int(c.streifenwagen):
			vehicles.append(_vehicle("polizei", police))
	if hospital >= 0:
		for i in int(c.krankenwagen):
			vehicles.append(_vehicle("krankenwagen", hospital))
	if not sim.day_changed.is_connected(on_day):
		sim.day_changed.connect(on_day)


func _first(role: String) -> int:
	for b in sim.city.buildings:
		if b.role == role:
			return int(b.id)
	return -1


func _vehicle(kind: String, home: int) -> Dictionary:
	var m := Mover.new()
	m.speed = 3.4
	var road: Vector2i = sim.city.building(home).road
	m.pos = sim.city.tile_center(road)
	return {"kind": kind, "mover": m, "task": {}, "home": home}


func today() -> int:
	return GameCalendar.day_of(sim.game_min)


static func in_prison(p: Dictionary, day: int) -> bool:
	return int(p.get("prison_until", -1)) > day


static func absent(p: Dictionary, day: int) -> bool:
	return int(p.get("sick_until", -1)) > day or in_prison(p, day)


# ------------------------------------------------------------------ Tag
func on_day(day: int) -> void:
	if day == _day:
		return
	_day = day
	var c := cfg()
	var police_n: int = sim.citizens.employed_count("polizei")
	var doc_n: int = sim.citizens.employed_count("gesundheit")
	var doc_capacity := float(doc_n) * float(c.arzt_patienten_je_kraft_tag)
	var doc_today := 0
	var costs := 0.0
	for p in sim.citizens.people:
		var pid := int(p.id)
		# Entlassung aus der Haft
		if int(p.get("prison_until", -1)) == day:
			p.prison_until = -1
			sim.activity.add("stadt", -1, "polizei", "%s wird aus der Haft entlassen" % p.name, "Haft verbüßt", _cell(prison))
		if in_prison(p, day):
			continue
		# Gesundheit
		if int(p.get("sick_until", -1)) <= day:
			var glueck := float(p.get("needs", {}).get("glueck", 60.0))
			var age := int(p.get("age", 40))
			var risk := float(c.krankheit_je_tag) * (1.0 + (100.0 - glueck) / 100.0) * (1.0 + maxf(0.0, float(age - 45)) / 40.0)
			if Citizens.roll(pid, day, 71) < risk:
				stats.erkrankt += 1
				var severe := Citizens.roll(pid, day, 72) < float(c.schwer_anteil) or float(doc_today) >= doc_capacity
				if severe and sim.rescue != null and sim.rescue.enabled():   # Region: Rettungsdienst (Auftrag 20 Etappe 5)
					var days := 3 + int(Citizens.roll(pid, day, 73) * 8.0)
					p.sick_until = day + days
					p.in_hospital = false   # Aufnahme erst bei der Uebergabe in der Klinik
					costs += float(c.kosten_krankenhaus_tag) * days
					stats.krankenhaus += 1
					sim.rescue.emergency(p, sim.rescue.home_road(p))
				elif severe and hospital >= 0:
					var days := 3 + int(Citizens.roll(pid, day, 73) * 8.0)
					p.sick_until = day + days
					p.in_hospital = true
					costs += float(c.kosten_krankenhaus_tag) * days
					stats.krankenhaus += 1
					_send("krankenwagen", _home_cell(p), {"patient": pid, "back": hospital})
					sim.activity.add("stadt", -1, "gesundheit", "Krankenwagen holt %s ins Krankenhaus" % p.name, "schwer erkrankt, %d Tage stationär" % days, _home_cell(p))
				else:
					var days := 1 + int(Citizens.roll(pid, day, 74) * 3.0)
					p.sick_until = day + days
					p.in_hospital = false
					doc_today += 1
					costs += float(c.kosten_arzt)
					stats.arzt += 1
		elif bool(p.get("in_hospital", false)) and int(p.get("sick_until", -1)) == day + 1:
			p.in_hospital = false
		# Kriminalitaet (wer schon gesucht wird, faellt nicht erneut auf)
		if bool(p.get("wanted", false)):
			continue
		var needs: Dictionary = p.get("needs", {})
		var f := 1.0
		if float(needs.get("geld", 50.0)) < 30.0:
			f *= 3.0
		if p.employer == "":
			f *= 2.0
		if float(needs.get("glueck", 50.0)) < 35.0:
			f *= 2.0
		if Citizens.roll(pid, day, 75) < float(c.kriminalitaet_je_tag) * f:
			_crime(p, day)
	if costs > 0.0:
		sim.economy.transfer("P0", "S0", costs)
		sim.public_sector.departments.Gesundheit = float(sim.public_sector.departments.get("Gesundheit", 0.0)) + costs
		stats.kosten += costs
	_police_work(day, police_n)


## Ladendiebstahl: Beute aus dem Handel (S0) auf das Konto des Taeters; Tatort ist ein Geschaeft.
func _crime(p: Dictionary, day: int) -> void:
	var shops: Array = sim.city.buildings.filter(func(b): return b.type in ["shop", "supermarket"])
	if shops.is_empty():
		return
	var shop: Dictionary = shops[int(Citizens.roll(int(p.id), day, 76) * shops.size()) % shops.size()]
	var loot := snappedf(50.0 + 350.0 * Citizens.roll(int(p.id), day, 77), 1.0)
	sim.population.pay_in("S0", [[p, loot]])
	p.wanted = true
	p.loot = float(p.get("loot", 0.0)) + loot
	p.crime_day = day
	p.crime_cell = [shop.walk.x, shop.walk.y]
	stats.straftaten += 1
	sim.activity.add("stadt", -1, ICON_CRIME, "Diebstahl in %s (%s EUR)" % [shop.name, str(int(loot))], "Täter unbekannt – die Polizei ermittelt", shop.walk)
	sim.log_event("Polizeibericht: Diebstahl in %s (%s)." % [shop.name, Catalog.money(loot)], "warn")


## Ermittlung: je Tag und Gesuchtem eine Chance aus der Personalstaerke der Polizei; Festnahme mit Streifenwagen.
func _police_work(day: int, police_n: int) -> void:
	var chance := clampf(0.1 + float(police_n) * float(cfg().aufklaerung_je_polizist), 0.1, 0.9)
	for p in sim.citizens.people:
		if not bool(p.get("wanted", false)) or in_prison(p, day):
			continue
		if Citizens.roll(int(p.id), day, 78) < chance:
			_arrest(p, day)


func _arrest(p: Dictionary, day: int) -> void:
	var c := cfg()
	var length := int(c.haft_tage_min) + int(Citizens.roll(int(p.id), day, 79) * float(int(c.haft_tage_max) - int(c.haft_tage_min)))
	var where := _home_cell(p)
	if p.has("crime_cell"):
		where = Vector2i(int(p.crime_cell[0]), int(p.crime_cell[1]))
	# Beute erstatten, soweit noch vorhanden
	sim.population.pay_out("S0", [[p, float(p.get("loot", 0.0))]])
	p.loot = 0.0
	p.wanted = false
	p.prison_until = day + length
	p.employer = ""
	p.wage = 0.0
	stats.festnahmen += 1
	_send("polizei", where, {"arrest": int(p.id), "back": prison if prison >= 0 else police})
	var lost := ""
	var u: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
	if not u.is_empty():
		var own := str(u.owner) == Population.OWNER_PREFIX + str(int(p.id))
		if not own and length >= int(c.wohnung_weg_ab_tagen):
			p.home = ""
			stats.haft_wohnung_verloren += 1
			lost = ", Wohnung gekündigt"
			if sim.citizens.people.filter(func(q): return str(q.get("home", "")) == str(u.id)).is_empty():
				u.tenant = ""
				u.arrears = 0
		elif own and float(p.get("tax_arrears", 0.0)) > 0.0 and length >= int(c.haft_tage_max) - 10:
			_forced_sale(p, u)
			lost = ", Haus zwangsversteigert"
	sim.activity.add("stadt", -1, "polizei", "Polizei nimmt %s fest" % p.name, "Diebstahl aufgeklärt, %d Tage Haft, Arbeit verloren%s" % [length, lost], where)
	sim.log_event("Polizei: %s festgenommen (%d Tage Haft%s)." % [p.name, length, lost], "info")


## Zwangsversteigerung: der Vermietersektor uebernimmt die Wohnung; der Erloes (60 % des Werts) deckt zuerst den Steuerrueckstand.
func _forced_sale(p: Dictionary, u: Dictionary) -> void:
	var value := Population.unit_value(u) * 0.6
	sim.economy.transfer(Housing.LANDLORD, Population.ACCOUNT, value)
	p.balance = float(p.balance) + value
	var arrears := float(p.get("tax_arrears", 0.0))
	sim.population.pay_out(Towns.account_of(sim.towns.of_building(int(u.building))), [[p, arrears]])
	p.tax_arrears = 0.0
	u.owner = Housing.LANDLORD
	u.owner_occupied = false
	stats.haus_verloren += 1


# ------------------------------------------------------------------ Fahrzeuge
func _send(kind: String, cell: Vector2i, task: Dictionary) -> void:
	for v in vehicles:
		if v.kind == kind and v.task.is_empty():
			v.task = task.duplicate()
			v.task["phase"] = "hin"
			v.task["cell"] = [cell.x, cell.y]
			sim.route(v.mover, _road_near(cell))
			return


func _road_near(cell: Vector2i) -> Vector2i:
	if sim.city.is_road(cell):
		return cell
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := cell + Vector2i(dx, dy)
				if sim.city.is_road(q) and not sim.nav.is_blocked_road(q):
					return q
	return cell


## Bewegung je Simulationsschritt: Einsatz hin -> zurueck zur Basis. Freie Streifenwagen sichern Sperrungen ab (stehen daneben),
## sonst fahren sie Streife; freie Krankenwagen warten am Krankenhaus.
func update(dt: float) -> void:
	var guards := _closures()
	var gi := 0
	for v in vehicles:
		var m: Mover = v.mover
		if v.task.is_empty() and v.kind == "polizei":
			if gi < guards.size():
				var g: Vector2i = guards[gi]
				gi += 1
				if m.goal != g:
					sim.route(m, g)
			elif m.arrived():
				sim.route(m, sim._random_road())   # Streife
		if not m.arrived():
			if sim.nav.is_blocked_road(m.next_tile()) and m.next_tile() != m.goal:
				sim.route(m, m.goal)
			else:
				m.advance(dt, 1.2)
			continue
		if v.task.is_empty():
			continue
		if v.task.phase == "hin":
			v.task.phase = "zurueck"
			sim.route(m, sim.city.building(int(v.task.back)).road)
		else:
			v.task = {}


## Strassenzellen neben aktiven Sperrungen (Polizei sichert die Sperrstelle ab).
func _closures() -> Array:
	var out: Array = []
	for p in sim.nav.roadworks.keys():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if sim.city.is_road(q) and not sim.nav.is_blocked_road(q):
				out.append(q)
				break
	return out


# ------------------------------------------------------------------ Hilfen
func _cell(bid: int) -> Vector2i:
	return sim.city.building(bid).walk if bid >= 0 else Vector2i(sim.city.size / 2, sim.city.size / 2)


func _home_cell(p: Dictionary) -> Vector2i:
	var u: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
	if u.is_empty():
		return _cell(police)
	return sim.city.building(int(u.building)).walk


func summary() -> Dictionary:
	var day := today()
	var sick := 0
	var hosp := 0
	var jail := 0
	var wanted := 0
	for p in sim.citizens.people:
		if int(p.get("sick_until", -1)) > day:
			sick += 1
			if bool(p.get("in_hospital", false)):
				hosp += 1
		if in_prison(p, day):
			jail += 1
		if bool(p.get("wanted", false)):
			wanted += 1
	return {"krank": sick, "im_krankenhaus": hosp, "haeftlinge": jail, "gesucht": wanted, "polizei_personal": sim.citizens.employed_count("polizei"),
		"aerzte_pflege": sim.citizens.employed_count("gesundheit"), "gesamt": stats.duplicate(),
		"aufklaerungschance_je_tag": snappedf(clampf(0.1 + float(sim.citizens.employed_count("polizei")) * float(cfg().aufklaerung_je_polizist), 0.1, 0.9), 0.01)}


func to_dict() -> Dictionary:
	return {"stats": stats.duplicate(), "day": _day, "tasks": vehicles.map(func(v): return v.task)}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	stats = d.get("stats", stats)
	_day = int(d.get("day", -1))
