class_name Logistics
extends RefCounted
## Allgemeines Stopp-Modell fuer Fahrzeuge. Daraus lassen sich Geschaeftsmodelle frei kombinieren:
## Teilmengen (aufteilen), Zwischenlager (lager:<Depot>), Umladen (abladen im Lager, anderes Fahrzeug laedt dort),
## Sammeltouren (mehrere Ladungen gleichzeitig) und Rueckfahrten (Ladung auf dem Rueckweg).
##
## Stopp = {art: "laden"|"abladen", contract_id, menge, ort: "abholung"|"ziel"|"lager:<Depot-ID>"}
## Bezahlt wird ein Auftrag erst, wenn die gesamte Menge am Ziel abgeladen ist.

const PICKUP := "abholung"
const DROP := "ziel"

var sim


func setup(simulation) -> void:
	sim = simulation


static func store_site(place: String) -> int:
	return place.trim_prefix("lager:").to_int() if place.begins_with("lager:") else -1


func storage_cap(site: int) -> int:
	if sim.estate.is_plot(site):
		return sim.estate.storage_cap(site) if sim.estate.plots[site].owner >= 0 else 0
	return Catalog.DEPOT_STORAGE if sim.depot_owner.has(site) else 0


func stored(site: int, kid: String) -> int:
	return int(sim.storage.get(site, {}).get(kid, 0))


func storage_used(site: int) -> int:
	var s := 0
	for kid in sim.storage.get(site, {}):
		s += int(sim.storage[site][kid])
	return s


func place_cell(k: Contract, place: String) -> Vector2i:
	if place == PICKUP:
		return sim.city.building(k.pickup).road
	if place == DROP:
		return sim.city.building(k.dropoff).road
	var site := store_site(place)
	return sim.city.building(site).road if site >= 0 else Vector2i(-1, -1)


func place_building(k: Contract, place: String) -> int:
	if place == PICKUP:
		return k.pickup
	if place == DROP:
		return k.dropoff
	return store_site(place)


## Geplante, noch nicht ausgefuehrte Lade-/Abladestopps aller Fahrzeuge (Reservierungen).
func _reserved(kid: String, place: String, art: String, exclude: FleetVehicle = null) -> int:
	var n := 0
	for v in sim.vehicles.values():
		if v == exclude:
			continue
		for st in v.stops:
			if st.contract_id == kid and st.ort == place and st.art == art:
				n += int(st.menge)
	return n


func _reserved_store_in(site: int, exclude: FleetVehicle = null) -> int:
	var n := 0
	for v in sim.vehicles.values():
		if v == exclude:
			continue
		for st in v.stops:
			if st.art == "abladen" and st.ort == "lager:%d" % site:
				n += int(st.menge)
	return n


## Physisch verfuegbare und noch nicht verplante Menge an einem Ort.
func available(k: Contract, place: String, exclude: FleetVehicle = null) -> int:
	if place == PICKUP:
		return k.qty - k.picked - _reserved(k.id, PICKUP, "laden", exclude)
	var site := store_site(place)
	if site >= 0:
		return stored(site, k.id) - _reserved(k.id, place, "laden", exclude)
	return 0


## Prueft eine Stoppfolge fuer ein Fahrzeug (inkl. bereits geplanter Stopps und aktueller Ladung).
## Gibt "" zurueck oder eine verstaendliche Fehlermeldung.
func validate(v: FleetVehicle, new_stops: Array) -> String:
	var cap: int = v.spec().capacity
	var load := v.load.duplicate()
	var op: int = v.operator if v.operator >= 0 else v.owner
	var quota := {}      # fremde Auftraege (Unterauftrag): noch ladbare Menge
	var used := {}       # Mengen, die diese Tour an Orten bereits verplant
	var store_in := {}   # zusaetzliche Lagerbelegung durch diese Tour
	var all_stops: Array = v.stops + new_stops
	for i in all_stops.size():
		var st: Dictionary = all_stops[i]
		var is_new := i >= v.stops.size()
		var k: Contract = sim.contracts.get(str(st.contract_id))
		if k == null or k.status not in ["accepted", "assigned", "in_transit"]:
			return "Stopp %d: Auftrag %s ist nicht aktiv." % [i + 1, st.contract_id]
		if k.owner != op:
			if not quota.has(k.id):
				quota[k.id] = sim.social.split_quota(op, k.id) - _reserved_by(op, k.id, v)
			if quota[k.id] <= 0 and is_new and st.art == "laden":
				return "Stopp %d: Auftrag %s gehört dir nicht (kein Unterauftrag mit freier Menge)." % [i + 1, k.id]
		var q := int(st.menge)
		if q <= 0:
			return "Stopp %d: Menge muss positiv sein." % (i + 1)
		var place := str(st.ort)
		if place not in [PICKUP, DROP] and store_site(place) < 0:
			return "Stopp %d: Ort muss 'abholung', 'ziel' oder 'lager:<Depot-ID>' sein." % (i + 1)
		var site := store_site(place)
		if site >= 0 and sim.depot_owner.get(site, -1) != op and sim.social.storage_rights(op, site) <= 0:
			return "Stopp %d: Lager %d gehört dir nicht (und keine Mitbenutzung vereinbart)." % [i + 1, site]
		var key := "%s|%s" % [k.id, place]
		if st.art == "laden":
			if place == DROP:
				return "Stopp %d: Am Ziel wird nicht geladen." % (i + 1)
			if (k.needs_cold and not v.spec().refrigerated) or (k.needs_heavy and not v.spec().heavy):
				return "Stopp %d: #%d erfüllt die Anforderungen von %s nicht (%s)." % [i + 1, v.id, k.id, k.requirement_text()]
			if is_new:
				var free := available(k, place, v) - int(used.get(key, 0))
				# eigene, schon geplante Ladestopps an diesem Ort sind in available() nicht abgezogen
				for j in v.stops.size():
					var o: Dictionary = v.stops[j]
					if o.contract_id == k.id and o.ort == place and o.art == "laden":
						free -= int(o.menge)
				if q > free:
					return "Stopp %d: Bei %s sind von %s nur noch %d Einheiten verfügbar." % [i + 1, place, k.id, maxi(0, free)]
				if k.owner != op:
					if q > int(quota[k.id]):
						return "Stopp %d: Unterauftrag erlaubt nur noch %d Einheiten von %s." % [i + 1, maxi(0, int(quota[k.id])), k.id]
					quota[k.id] = int(quota[k.id]) - q
				used[key] = int(used.get(key, 0)) + q
			load[k.id] = int(load.get(k.id, 0)) + q
			var total := 0
			for x in load:
				total += int(load[x])
			if total > cap:
				return "Stopp %d: Kapazität von #%d überschritten (%d/%d)." % [i + 1, v.id, total, cap]
		elif st.art == "abladen":
			if int(load.get(k.id, 0)) < q:
				return "Stopp %d: #%d hätte dann nur %d Einheiten von %s geladen." % [i + 1, v.id, int(load.get(k.id, 0)), k.id]
			if place == PICKUP:
				return "Stopp %d: Zurück zur Abholung abladen ist nicht vorgesehen." % (i + 1)
			if site >= 0 and is_new and k.needs_cold and sim.estate.is_plot(site):
				var cold := 0
				for kid in sim.storage.get(site, {}):
					var kk: Contract = sim.contracts.get(kid)
					if kk and kk.needs_cold:
						cold += int(sim.storage[site][kid])
				if cold + q > sim.estate.storage_cap(site, true):
					return "Stopp %d: Kühlware braucht freien Kühllagerplatz (%d/%d)." % [i + 1, cold, sim.estate.storage_cap(site, true)]
			if site >= 0 and is_new:
				var free_store := storage_cap(site) - storage_used(site) - _reserved_store_in(site, v) - int(store_in.get(site, 0))
				if sim.depot_owner.get(site, -1) != op:
					free_store = mini(free_store, sim.social.storage_rights(op, site) - _company_stored(op, site))
				for o in v.stops:
					if o.art == "abladen" and o.ort == place:
						free_store -= int(o.menge)
				if q > free_store:
					return "Stopp %d: Lager %d hat nur noch %d Plätze frei." % [i + 1, site, maxi(0, free_store)]
				store_in[site] = int(store_in.get(site, 0)) + q
			load[k.id] = int(load[k.id]) - q
		else:
			return "Stopp %d: art muss 'laden' oder 'abladen' sein." % (i + 1)
	return ""


## Bereits durch eine Firma verplante oder geladene Menge eines (fremden) Auftrags.
func _reserved_by(cid: int, kid: String, exclude: FleetVehicle) -> int:
	var n := 0
	for veh in sim.vehicles.values():
		var op: int = veh.operator if veh.operator >= 0 else veh.owner
		if op != cid or veh == exclude:
			continue
		for st in veh.stops:
			if st.contract_id == kid and st.art == "laden":
				n += int(st.menge)
	return n


func _company_stored(cid: int, site: int) -> int:
	var n := 0
	for kid in sim.storage.get(site, {}):
		var k: Contract = sim.contracts.get(kid)
		if k and k.owner == cid:
			n += int(sim.storage[site][kid])
	return n


func add_stops(v: FleetVehicle, new_stops: Array) -> void:
	for st in new_stops:
		v.stops.append({"art": str(st.art), "contract_id": str(st.contract_id), "menge": int(st.menge), "ort": str(st.ort)})
		var k: Contract = sim.contracts[str(st.contract_id)]
		if k.status == "accepted":
			k.status = "assigned"
			k.vehicle_id = v.id
	sync_view(v)


## Fuehrt den ersten Stopp aus (nach Ablauf der Lade-/Abladezeit). Gibt eine Meldung zurueck.
func apply_stop(v: FleetVehicle) -> String:
	var st: Dictionary = v.stops.pop_front()
	var k: Contract = sim.contracts.get(st.contract_id)
	var q := int(st.menge)
	var msg := ""
	if k == null or k.status not in ["assigned", "in_transit", "accepted"]:
		msg = "Stopp übersprungen: Auftrag %s ist nicht mehr aktiv." % st.contract_id
	elif st.art == "laden":
		if st.ort == PICKUP:
			q = mini(q, k.qty - k.picked)
			k.picked += q
			var g: Dictionary = sim.social.agreement_for_delivery(v.operator if v.operator >= 0 else v.owner, k.id)
			if not g.is_empty() and k.owner != (v.operator if v.operator >= 0 else v.owner):
				g.geladen = int(g.geladen) + q
		else:
			var site := store_site(st.ort)
			q = mini(q, stored(site, k.id))
			sim.storage[site][k.id] = stored(site, k.id) - q
		v.load[k.id] = int(v.load.get(k.id, 0)) + q
		if q > 0:
			k.status = "in_transit"
		msg = "#%d hat %d × %s (%s) geladen." % [v.id, q, k.cargo_name(), k.id]
	else:
		q = mini(q, int(v.load.get(k.id, 0)))
		v.load[k.id] = int(v.load.get(k.id, 0)) - q
		if int(v.load[k.id]) <= 0:
			v.load.erase(k.id)
		if st.ort == DROP:
			k.delivered_qty += q
			var op: int = v.operator if v.operator >= 0 else v.owner
			if k.owner != op:
				var g: Dictionary = sim.social.agreement_for_delivery(op, k.id)
				if not g.is_empty():
					g.geliefert = int(g.geliefert) + q
			msg = "#%d hat %d × %s am Ziel abgeladen (%d/%d)." % [v.id, q, k.cargo_name(), k.delivered_qty, k.qty]
			if k.delivered_qty >= k.qty:
				sim.deliver_contract(v, k)
		else:
			var site := store_site(st.ort)
			if not sim.storage.has(site):
				sim.storage[site] = {}
			sim.storage[site][k.id] = stored(site, k.id) + q
			msg = "#%d hat %d × %s ins Lager %d gebracht." % [v.id, q, k.cargo_name(), site]
	sync_view(v)
	return msg


## Auftrag beendet/gescheitert: Stopps und Restware entfernen (Ware gilt als zurueckgegeben).
func close_contract(k: Contract) -> void:
	for v in sim.vehicles.values():
		var before: int = v.stops.size()
		v.stops = v.stops.filter(func(st): return st.contract_id != k.id)
		v.load.erase(k.id)
		if v.stops.size() != before or v.contract_id == k.id:
			sync_view(v)
	for site in sim.storage:
		sim.storage[site].erase(k.id)


## Abgeleitete Anzeigefelder (aktueller Auftrag, Warteschlange, sichtbare Ladung).
func sync_view(v: FleetVehicle) -> void:
	v.contract_id = str(v.stops[0].contract_id) if not v.stops.is_empty() else ""
	var q: Array = []
	for st in v.stops:
		if st.contract_id not in q and st.contract_id != v.contract_id:
			q.append(st.contract_id)
	v.queue = q
	v.cargo = ""
	for kid in v.load:
		var k: Contract = sim.contracts.get(kid)
		if k and int(v.load[kid]) > 0:
			v.cargo = k.cargo
			break


func load_total(v: FleetVehicle) -> int:
	var s := 0
	for kid in v.load:
		s += int(v.load[kid])
	return s


## Standardstopps fuer "ganzen Auftrag direkt fahren" (oder eine Teilmenge).
func direct_stops(k: Contract, qty: int, from: String = PICKUP, to: String = DROP) -> Array:
	return [{"art": "laden", "contract_id": k.id, "menge": qty, "ort": from},
		{"art": "abladen", "contract_id": k.id, "menge": qty, "ort": to}]
