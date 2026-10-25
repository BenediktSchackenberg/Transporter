class_name Contract
extends RefCounted
## Transportauftrag. Status: open -> accepted -> assigned -> loading -> in_transit -> delivered
## oder failed (Frist + 4 h ueberschritten) bzw. expired (nie angenommen) / cancelled (Spielende).

var id: String
var pickup: int              # Gebaeude-ID
var dropoff: int
var cargo: String            # Warenkategorie (bestimmt Anforderungen und Symbol)
var label := ""              # konkrete Bezeichnung aus einer Lieferkette, z. B. "Bierfässer"
var qty: int
var reward: float
var created: float
var deadline: float          # Spielminute
var offer_until: float       # solange auf dem Markt
var min_rep := 0.0
var needs_cold := false
var needs_heavy := false
var size_class := "klein"    # klein | mittel | groß
var status := "open"
var owner := -1
var vehicle_id := -1
var exclusive_for := -1
var exclusive_until := 0.0
var distance := 0
var paid := 0.0
var picked := 0              # an der Abholung bereits geladene Menge
var delivered_qty := 0       # am Ziel abgeladene Menge (bezahlt wird erst bei vollstaendiger Lieferung)
var fuel_cost := 0.0         # zurechenbare Treibstoffkosten (Messgroesse fuer Experimente)
var accepted_at := 0.0
var internal := ""           # eigener Materialtransport zur Baustelle (Einrichtungs-ID), erzeugt keinen Umsatz
var done_at := 0.0
var requester := ""          # Kundenfigur (Residents), deren Anliegen dieser Auftrag erfuellt
var concern := ""            # Anliegen im Klartext, z. B. "Getraenke gehen zur Neige"
var cause := ""              # Ereignis-ID, aus der der Auftrag entstand (Ursachenkette)


func cargo_name() -> String:
	return label if label != "" else Catalog.CARGO[cargo].name


func requirement_text() -> String:
	var r: Array = ["Kapazität ≥ %d" % qty]
	if needs_cold:
		r.append("Kühlung")
	if needs_heavy:
		r.append("LKW/Sattelzug")
	return ", ".join(r)


func vehicle_ok(model_id: String) -> bool:
	var m := Catalog.model(model_id)
	return m.capacity >= qty and (not needs_cold or m.refrigerated) and (not needs_heavy or m.heavy)


func to_dict() -> Dictionary:
	return {"id": id, "pickup": pickup, "dropoff": dropoff, "cargo": cargo, "label": label, "qty": qty, "reward": reward,
		"created": created, "deadline": deadline, "offer_until": offer_until, "min_rep": min_rep,
		"needs_cold": needs_cold, "needs_heavy": needs_heavy, "size_class": size_class, "status": status,
		"owner": owner, "vehicle_id": vehicle_id, "exclusive_for": exclusive_for,
		"exclusive_until": exclusive_until, "distance": distance, "paid": paid, "picked": picked,
		"delivered_qty": delivered_qty, "fuel_cost": fuel_cost, "accepted_at": accepted_at, "done_at": done_at, "internal": internal,
		"requester": requester, "concern": concern, "cause": cause}


static func from_dict(d: Dictionary) -> Contract:
	var k := Contract.new()
	for key in d:
		k.set(key, d[key])
	k.picked = int(d.get("picked", 0))
	k.delivered_qty = int(d.get("delivered_qty", 0))
	for key in ["pickup", "dropoff", "qty", "owner", "vehicle_id", "exclusive_for", "distance"]:
		k.set(key, int(d[key]))
	return k
