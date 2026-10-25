class_name FleetVehicle
extends Mover
## Firmenfahrzeug. Zustandsautomat:
## idle -> to_pickup -> loading -> to_dropoff -> unloading -> (naechster Auftrag | returning) -> idle
## Daneben: to_workshop -> repairing, broken (Panne), wartend auf Fahrer.

const STATE_TEXT := {"idle": "bereit", "to_pickup": "fährt zur Abholung", "loading": "lädt",
	"to_dropoff": "liefert aus", "unloading": "entlädt", "returning": "fährt zum Depot",
	"to_workshop": "fährt zur Werkstatt", "repairing": "in Reparatur", "broken": "Panne", "waiting_bay": "wartet auf Laderampe",
	"washing": "wird gewaschen", "to_fuel": "fährt zur Tankstelle", "waiting_fuel": "wartet auf Zapfsäule",
	"refueling": "tankt", "out_of_fuel": "steht ohne Treibstoff", "fuel_rescue": "wartet auf Kraftstoff-Pannendienst", "waiting_fuel_cargo": "wartet auf Tankwagenbeladung"}

var id: int
var owner: int
var model: String
var purchase_price: float
var book_value: float
var condition := 100.0
var state := "idle"
var contract_id := ""
var queue: Array = []        # weitere zugewiesene Auftrags-IDs
var timer := 0.0             # Restzeit (Spielminuten) fuer Laden/Reparatur/Panne
var odometer := 0
var idle_since := 0.0
var cargo := ""              # sichtbar transportierte Ware
var stops: Array = []        # geplante Stopps {art, contract_id, menge, ort} (siehe Logistics)
var load := {}               # Ladung: Auftrags-ID -> Menge
var parking := ""            # zugeordneter Stellplatz/Halle (Einrichtungs-ID)
var bay_pref := ""           # bevorzugte Laderampe
var clean_until := 0.0       # gepflegt (Waschplatz) bis Spielminute
var operator := -1           # Mieter (Kapazitaetsvermietung); -1 = Halter betreibt selbst
var held_by := ""            # Aufgaben-ID, die das Fahrzeug festhaelt (Reparatur vor Ort)
var resume_state := ""       # Zustand vor einer Panne/Sabotage (wird nach Reparatur fortgesetzt)
var resume_timer := 0.0
var fuel_l := 0.0
var fuel_payer := -1
var fuel_retry_at := 0.0
var refueling := {}


func setup(vid: int, owner_id: int, model_id: String, price: float, p: Vector2) -> void:
	id = vid
	owner = owner_id
	model = model_id
	purchase_price = price
	book_value = price
	pos = p
	speed = Catalog.model(model_id).speed


func tank_capacity() -> float:
	return float(VehicleFuel.CAPACITY.get(model, 120.0))


func spec() -> Dictionary:
	return Catalog.model(model)


func display_name() -> String:
	return "%s #%d" % [spec().name, id]


func to_dict() -> Dictionary:
	return {"id": id, "owner": owner, "model": model, "purchase_price": purchase_price, "book_value": book_value,
		"condition": condition, "state": state, "contract_id": contract_id, "queue": queue, "timer": timer,
		"odometer": odometer, "idle_since": idle_since, "cargo": cargo, "x": pos.x, "y": pos.y,
		"goal": [goal.x, goal.y], "held_by": held_by, "stops": stops, "load": load, "operator": operator, "parking": parking, "bay_pref": bay_pref,
		"clean_until": clean_until, "resume_state": resume_state, "resume_timer": resume_timer, "fuel_l": fuel_l, "fuel_payer": fuel_payer, "fuel_retry_at": fuel_retry_at, "refueling": refueling}


static func from_dict(d: Dictionary) -> FleetVehicle:
	var v := FleetVehicle.new()
	v.setup(int(d.id), int(d.owner), d.model, d.purchase_price, Vector2(d.x, d.y))
	v.book_value = d.book_value
	v.condition = d.condition
	v.state = d.state
	v.contract_id = d.contract_id
	v.queue = d.queue
	v.timer = d.timer
	v.odometer = int(d.odometer)
	v.idle_since = d.idle_since
	v.cargo = d.cargo
	v.goal = Vector2i(int(d.goal[0]), int(d.goal[1]))
	v.held_by = d.get("held_by", "")
	v.stops = d.get("stops", [])
	v.operator = int(d.get("operator", -1))
	v.parking = d.get("parking", "")
	v.bay_pref = d.get("bay_pref", "")
	v.clean_until = float(d.get("clean_until", 0.0))
	for st in v.stops:
		st.menge = int(st.menge)
	for kid in d.get("load", {}):
		v.load[kid] = int(d.load[kid])
	v.resume_state = d.get("resume_state", "")
	v.resume_timer = float(d.get("resume_timer", 0.0))
	v.fuel_l = clampf(float(d.get("fuel_l", 0.0)), 0.0, v.tank_capacity())
	v.fuel_payer = int(d.get("fuel_payer", v.owner))
	v.fuel_retry_at = float(d.get("fuel_retry_at", 0.0))
	v.refueling = d.get("refueling", {})
	if bool(d.get("no_fuel", false)):
		v.state = "out_of_fuel"   # alten Spielstand ohne automatischen Fern-Nachschub migrieren
	return v
