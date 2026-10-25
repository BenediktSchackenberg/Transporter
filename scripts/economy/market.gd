class_name Market
extends RefCounted
## Auftragsmarkt. Begrenzt die Geldquellen: begrenzte Zahl offener Auftraege, jeder nur einmal vergebbar,
## Saettigung je Viertel (viele Annahmen im selben Viertel senken die Preise), jede Fahrt kostet Treibstoff.

const SOURCE_WEIGHT := {"airport_cargo": 4, "port_office": 4, "freight_shed": 3, "factory": 3, "warehouse": 5, "farm": 2,
	"office": 2, "shop": 3, "apartment": 2}
const BIG_SOURCES := ["port_office", "freight_shed", "factory", "airport_cargo"]

var sim  # Simulation (untypisiert, um Zyklen zu vermeiden)
var sources: Array = []          # [Gebaeude-ID, Gewicht]
var source_total := 0
var receivers := {}              # Ware -> [Gebaeude-IDs]
var chain_ends: Array = []       # [Quellen, Ziele, Bezeichnung, Ware, min, max]
var saturation := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
var next_id := 1


func setup(simulation) -> void:
	sim = simulation
	refresh()


## Quellen, Empfaenger und Lieferketten (neu) aus den Gebaeuden ableiten (auch nach neuem Gewerbegebiet).
func refresh() -> void:
	sources.clear()
	source_total = 0
	receivers.clear()
	chain_ends.clear()
	for b in sim.city.buildings:
		if b.role not in ["customer", "bank", "workshop"]:
			continue
		var w: int = SOURCE_WEIGHT.get(b.type, 0)
		if w > 0 and not b.out.is_empty():
			sources.append([b.id, w])
			source_total += w
		for cargo in b["in"]:
			if not receivers.has(cargo):
				receivers[cargo] = []
			receivers[cargo].append(b.id)
	for ch in Catalog.CHAINS:
		var srcs: Array = []
		var dsts: Array = []
		for b in sim.city.buildings:
			if _matches(b, ch[0]):
				srcs.append(b.id)
			if _matches(b, ch[1]):
				dsts.append(b.id)
		if not srcs.is_empty() and not dsts.is_empty():
			chain_ends.append([srcs, dsts, ch[2], ch[3], ch[4], ch[5]])


func target_open() -> int:
	return 12 + 6 * sim.companies.size()


func open_contracts() -> Array:
	var out: Array = []
	for k in sim.contracts.values():
		if k.status == "open":
			out.append(k)
	return out


## Wird einmal pro Spielminute aufgerufen.
func tick(now: float) -> void:
	for k in sim.contracts.values():
		if k.status == "open" and now > k.offer_until:
			k.status = "expired"
	for i in saturation.size():
		saturation[i] = minf(1.0, saturation[i] + 0.002)
	var open := open_contracts().size()
	if open < target_open() and sim.rng.randf() < 0.6:
		spawn(now)
	# beendete Auftraege nach einer Weile aus dem Speicher entfernen
	for id in sim.contracts.keys():
		var k: Contract = sim.contracts[id]
		if k.status in ["expired", "delivered", "failed", "cancelled"] and now - k.deadline > 600:
			sim.contracts.erase(id)
			for c in sim.companies:
				c.known.erase(id)


func on_accepted(k: Contract) -> void:
	var d: int = sim.city.district_of(sim.city.building(k.pickup).road)
	saturation[d] = maxf(0.7, saturation[d] - 0.03)


func spawn(now: float) -> Contract:
	var rng: RandomNumberGenerator = sim.rng
	var src_id := -1
	var dst_id := -1
	var cargo := ""
	var label := ""
	var qmin := 2
	var qmax := 8
	if not chain_ends.is_empty() and rng.randf() < 0.7:
		# konkrete Lieferkette, z. B. Brauerei -> Restaurant mit Bierfaessern
		var ch: Array = chain_ends[rng.randi() % chain_ends.size()]
		src_id = ch[0][rng.randi() % ch[0].size()]
		dst_id = _pick_dest(src_id, ch[1], rng.randf_range(20.0, 120.0))
		label = ch[2]
		cargo = ch[3]
		qmin = ch[4]
		qmax = ch[5]
	else:
		var r := rng.randi() % source_total
		for s in sources:
			r -= s[1]
			if r < 0:
				src_id = s[0]
				break
		var src0: Dictionary = sim.city.building(src_id)
		cargo = src0.out[rng.randi() % src0.out.size()]
		# Zielentfernung: kleine Sendungen eher kurz, grosse eher weit
		var big: bool = src0.type in BIG_SOURCES
		dst_id = _pick_dest(src_id, receivers.get(cargo, []), rng.randf_range(40.0, 150.0) if big else rng.randf_range(15.0, 90.0))
		if big:
			qmax = 80
			qmin = 12
		elif src0.type in ["warehouse", "farm"]:
			qmin = 3
			qmax = 24
	if dst_id < 0:
		return null
	return build_contract(src_id, dst_id, cargo, label, qmin, qmax, now)


## Erzeugt einen Auftrag mit allen Regeln des Marktes (Frist, Verguetung, Saettigung, Stammkunden).
## qty > 0 legt die Menge fest, urgent 0/1 erzwingt (Un-)Dringlichkeit; sonst entscheidet der Zufall.
func build_contract(src_id: int, dst_id: int, cargo: String, label: String, qmin: int, qmax: int, now: float,
		qty: int = -1, urgent_flag: int = -1) -> Contract:
	var rng: RandomNumberGenerator = sim.rng
	var src: Dictionary = sim.city.building(src_id)
	var dst: Dictionary = sim.city.building(dst_id)
	var info: Dictionary = Catalog.CARGO[cargo]
	var k := Contract.new()
	k.id = "A%d" % next_id
	next_id += 1
	k.pickup = src_id
	k.dropoff = dst_id
	k.cargo = cargo
	k.label = label
	k.qty = qty if qty > 0 else rng.randi_range(qmin, qmax)
	if info.refrigerated:
		k.qty = mini(k.qty, 14)
	k.needs_cold = info.refrigerated
	k.needs_heavy = k.qty >= int(info.heavy_from)
	k.size_class = "klein" if k.qty <= 8 else ("mittel" if k.qty <= 25 else "groß")
	k.distance = _manhattan(src, dst)
	var urgent := (urgent_flag == 1) if urgent_flag >= 0 else rng.randf() < 0.3
	var slack := rng.randf_range(1.5, 2.0) if urgent else rng.randf_range(2.2, 3.4)
	var travel_min := k.distance / 2.2 * Catalog.GAME_MIN_PER_SIM_SEC
	k.deadline = now + travel_min * slack + 120.0   # inkl. Anfahrt und Laden
	var base := 80.0 + k.distance * 3.2 * (1.0 + k.qty / 8.0) * float(info.value)
	base *= saturation[sim.city.district_of(src.road)]
	if urgent:
		base *= 1.25
	base *= sim.events.demand_factor(cargo)   # Ereignisregler: erhoehte Nachfrage
	if k.size_class == "groß":
		base *= 1.15
		k.min_rep = 55.0 if rng.randf() < 0.5 else 45.0
	k.created = now
	k.offer_until = now + rng.randf_range(90.0, 160.0)
	var loyal: int = sim.loyal_company(src_id)
	if loyal >= 0:
		k.exclusive_for = loyal
		k.exclusive_until = now + 60.0
		base *= 1.1
		sim.companies[loyal].known[k.id] = true   # Stammkunden melden sich direkt
	k.reward = roundf(base / 10.0) * 10.0
	sim.contracts[k.id] = k
	return k


## Bester von 12 zufaelligen Kandidaten, dessen Entfernung nahe an der Wunschentfernung liegt.
func _pick_dest(src_id: int, dests: Array, want: float) -> int:
	if dests.is_empty():
		return -1
	var src: Dictionary = sim.city.building(src_id)
	var best := -1
	var best_err := INF
	for attempt in 12:
		var cand: int = dests[sim.rng.randi() % dests.size()]
		var d := _manhattan(src, sim.city.building(cand))
		if cand != src_id and d >= 12 and absf(d - want) < best_err:
			best_err = absf(d - want)
			best = cand
	return best


static func _matches(b: Dictionary, matcher: String) -> bool:
	var parts := matcher.split("|")
	return b.type == parts[0] and (parts[1] == "" or str(b.name).begins_with(parts[1]))


func _manhattan(a: Dictionary, b: Dictionary) -> int:
	return absi(a.road.x - b.road.x) + absi(a.road.y - b.road.y)


func to_dict() -> Dictionary:
	return {"saturation": saturation, "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	saturation = d.saturation
	next_id = int(d.next_id)
