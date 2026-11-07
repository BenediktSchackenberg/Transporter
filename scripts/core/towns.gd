class_name Towns
extends RefCounted
## Stadtregister der Region (Auftrag 17, docs/REGION.md). Eine gemeinsame Simulation und Karte; je Ort eine eigene Verwaltung:
## Buergermeisteramt (Mayor), Stadtkasse (Konto), oeffentliches Grundeigentum, Zentrallager (CityDepot), Hafen (Harbor) und Flughafen
## (Airport). Ort 0 nutzt die bisherigen Kennungen (Konto "P0", Eigentuemer Parcels.CITY), dadurch laden alte Einzelstadt-Spielstaende
## unveraendert als Region mit einer Stadt. Ort k > 0: Konto "P<k>", Eigentuemer "stadt<k>".
## Zustaendigkeit: Verwaltungsgebiet = Ort mit dem naechsten Zentrum (CityData.town_of), unabhaengig vom Eigentum.

const START_BUDGET := 200000.0     # Startbudget weiterer Orte (Landeszuweisung X0 -> P<k>, wie der Seed von P0)

var sim
var list: Array = []               # [{id, name, center: Vector2i, rect: Rect2i, town_hall, bauhof, harbor, start_plot}]
var mayors: Array = []             # Mayor je Ort; [0] ist sim.mayor
var depots: Array = []             # CityDepot je Ort; [0] ist sim.city_depot
var harbors: Array = []            # Harbor je Ort; [0] ist sim.harbor
var airports: Array = []           # Airport je Ort; [0] ist sim.airport


static func account_of(k: int) -> String:
	return "P0" if k <= 0 else "P%d" % k


static func owner_of(k: int) -> String:
	return Parcels.CITY if k <= 0 else "%s%d" % [Parcels.CITY, k]


## Oeffentliches Grundeigentum irgendeines Orts?
static func is_public(owner: String) -> bool:
	return owner == Parcels.CITY or (owner.begins_with(Parcels.CITY) and owner.substr(Parcels.CITY.length()).is_valid_int())


static func town_of_owner(owner: String) -> int:
	if owner == Parcels.CITY:
		return 0
	if is_public(owner):
		return int(owner.substr(Parcels.CITY.length()))
	return -1


## Ort eines oeffentlichen Kontos ("P0", "P1", ...) oder -1.
static func town_of_account(acct: String) -> int:
	if acct.length() >= 2 and acct.begins_with("P") and acct.substr(1).is_valid_int():
		return int(acct.substr(1))
	return -1


## Projekt-/Plan-IDs je Ort eindeutig: Ort 0 wie bisher ("P12"), Ort k "T<k>P12".
static func prefixed(k: int, prefix: String, n: int) -> String:
	return "%s%d" % [prefix, n] if k <= 0 else "T%d%s%d" % [k, prefix, n]


static func town_of_id(id: String) -> int:
	if not id.begins_with("T"):
		return 0
	var digits := ""
	for ch in id.substr(1):
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	return int(digits) if digits != "" else 0


## Aufbau aus den Kartendaten. Mehrere Orte nur in der Weltart "region"; sonst genau ein Ort (bisheriges Spiel).
func setup(simulation) -> void:
	sim = simulation
	list = []
	var cd: CityData = sim.city
	if cd.towns.size() > 1:
		for t in cd.towns:
			list.append({"id": int(t.id), "name": str(t.name), "center": Vector2i(int(t.center[0]), int(t.center[1])),
				"rect": Rect2i(int(t.rect[0]), int(t.rect[1]), int(t.rect[2]), int(t.rect[3])), "town_hall": int(t.get("town_hall", -1)),
				"bauhof": int(t.get("bauhof", -1)), "harbor": int(t.get("harbor", -1)), "start_plot": int(t.get("start_plot", -1))})
	else:
		var th := -1
		for b in cd.buildings:
			if b.role == "town_hall":
				th = int(b.id)
				break
		var ctr := Vector2i(cd.size / 2, cd.size / 2)
		if th >= 0:
			ctr = Vector2i(int(cd.building(th).x), int(cd.building(th).y))
		list.append({"id": 0, "name": cd.town_name if cd.town_name != "" else "Stadt", "center": ctr, "rect": Rect2i(0, 0, cd.size, cd.size),
			"town_hall": th, "bauhof": -1, "harbor": -1, "start_plot": -1})
	mayors = [sim.mayor]
	depots = [sim.city_depot]
	harbors = [sim.harbor]
	airports = [sim.airport]


func count() -> int:
	return list.size()


func is_region() -> bool:
	return list.size() > 1


func name_of(k: int) -> String:
	return str(list[k].name) if k >= 0 and k < list.size() else "Region"


func get_t(k: int) -> Dictionary:
	return list[k] if k >= 0 and k < list.size() else {}


func mayor(k: int) -> Mayor:
	return mayors[clampi(k, 0, mayors.size() - 1)]


func depot(k: int) -> CityDepot:
	return depots[clampi(k, 0, depots.size() - 1)]


func harbor(k: int) -> Harbor:
	return harbors[clampi(k, 0, harbors.size() - 1)]


func airport(k: int) -> Airport:
	return airports[clampi(k, 0, airports.size() - 1)]


# ------------------------------------------------------------------ Zustaendigkeit
func of_cell(c: Vector2i) -> int:
	return sim.city.town_of(c) if is_region() else 0


func of_building(id: int) -> int:
	return sim.city.town_of_building(id) if is_region() else 0


func of_parcel(pid: String) -> int:
	if not is_region():
		return 0
	var p: Dictionary = sim.parcels.parcel(pid)
	if p.is_empty():
		return 0
	return of_cell(Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2))


## Verwaltung, die ein Projekt (Plan/Projekt-ID) fuehrt.
func mayor_of_project(id: String) -> Mayor:
	return mayor(town_of_id(id))


## Projekt aus der zustaendigen Verwaltung (leer, wenn unbekannt).
func project(id: String) -> Dictionary:
	return mayor_of_project(id).projects.get(id, {})


## Heimatstadt einer Firma (Registrierung). Startfirmen: Ort ihres Startgrundstuecks; sonst gespeichert in Company.home_town.
func home_of(cid: int) -> int:
	var c = sim.company(cid)
	if c == null:
		return 0
	return int(c.home_town)


func summary() -> Array:
	var out: Array = []
	for t in list:
		var k := int(t.id)
		var M: Mayor = mayor(k)
		out.append({"id": k, "name": t.name, "buergermeister": M.name, "partei": M.party, "kasse": int(float(sim.economy.accounts.get(account_of(k), 0.0))),
			"verfuegbar": int(M.available_budget()), "zustimmung": int(M.approval)})
	return out
