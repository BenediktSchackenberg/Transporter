class_name CityData
extends RefCounted
## Reine Kartendaten (ohne Rendering). Wird deterministisch aus dem Seed erzeugt.

enum G { GRASS, PARK, GRAVEL, SIDEWALK, PLAZA, CONCRETE, QUAY, SAND, FIELD, CROP, WATER, RAIL, ROAD, PARKING, RUNWAY, APRON }

var size: int
var seed_value: int
var ground: PackedByteArray
var district: PackedByteArray
var building_at: PackedInt32Array   # Gebaeude-ID je Zelle oder -1
var blocked: PackedByteArray        # 1 = nicht begehbar (Gebaeude, Baum, Wasser)
var buildings: Array = []           # Dictionaries, Index = ID
var trees: Array = []               # [Vector2i, variante]
var lamps: Array = []               # Vector2i
var benches: Array = []             # Vector2i
var intersections: Array = []       # Vector2i
var signals := {}                   # Vector2i -> true: Kreuzungen mit Ampel (Region: nur Vierwege-Kreuzungen nahe der Ortsmitte)
var depot_sites: Array = []         # Gebaeude-IDs der Depotstandorte
var start_depots: Array = []        # Gebaeude-IDs, Reihenfolge = Spieler 0..3
var world := "stadt"                # Weltart: stadt (Rasterstadt) | kueste (Kuestenort, Auftrag 15)
var town_name := ""                 # Fantasiename der Stadt (Kueste)
var gen_params := {}                # Erzeugungsparameter fuer Fehlersuche und Tests
var height := PackedByteArray()     # Gelaendehoehe je Zelle (0 = Flachland; >0 = Berg, nicht begehbar); leer in der Rasterstadt
var lakes: Array = []               # Seemittelpunkte
var river: Array = []               # Flusszellen
var road_count := 0
# Flughafen (Auftrag 16): Startbahn und Vorfeld liegen außerhalb der Baublöcke; die Geometrie ist für die
# Flugbewegung (FlightOps) und die Darstellung (AirView) relevant und wird deterministisch aus dem Seed erzeugt.
var airport: Dictionary = {}        # {rect, run_x0, run_x1, run_y, dir, apron: [[x,y],...], road, walk} (leer, wenn kein Flughafen)
# Region (Auftrag 17): Orte auf derselben Karte. Leer in alten Welten (dann eine Stadt aus town_name, siehe Towns).
var towns: Array = []               # [{id, name, center: [x, y], rect: [x, y, w, h], town_hall, bauhof, harbor, port_office, start_plot, airport}]
var region_roads: Array = []        # Verbindungsstrassen der Startinfrastruktur [{id, von, nach, zellen, laenge, verbunden, eigentum, wartung}]


## Kuestenwelt (Kuestenort oder Region aus Kuestenorten): Hafen, Berge, Zufahrten, Bruecken.
func coastal() -> bool:
	return world in ["kueste", "region"]


## Verwaltungsgebiet: Ort mit dem naechsten Ortszentrum (jede Zelle gehoert genau einem Ort; ohne Orte: 0).
func town_of(cell: Vector2i) -> int:
	if towns.size() <= 1:
		return 0
	var best := 0
	var best_d := 1 << 30
	for t in towns:
		var d := absi(cell.x - int(t.center[0])) + absi(cell.y - int(t.center[1]))
		if d < best_d:
			best_d = d
			best = int(t.id)
	return best


## Ort eines Gebaeudes: beim Erzeugen gesetzt, sonst nach Lage.
func town_of_building(id: int) -> int:
	var b := building(id)
	if b.is_empty():
		return 0
	if b.has("town"):
		return int(b.town)
	return town_of(Vector2i(int(b.x), int(b.y)))


func setup(n: int, s: int) -> void:
	size = n
	seed_value = s
	ground = PackedByteArray()
	ground.resize(n * n)
	district = PackedByteArray()
	district.resize(n * n)
	blocked = PackedByteArray()
	blocked.resize(n * n)
	building_at = PackedInt32Array()
	building_at.resize(n * n)
	building_at.fill(-1)


func idx(c: Vector2i) -> int:
	return c.y * size + c.x


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func g(c: Vector2i) -> int:
	return ground[idx(c)] if inside(c) else G.WATER


func is_road(c: Vector2i) -> bool:
	return inside(c) and ground[idx(c)] == G.ROAD


func road_mask(c: Vector2i) -> int:
	var m := 0
	if is_road(c + Vector2i.UP): m |= 1
	if is_road(c + Vector2i.RIGHT): m |= 2
	if is_road(c + Vector2i.DOWN): m |= 4
	if is_road(c + Vector2i.LEFT): m |= 8
	return m


func district_of(c: Vector2i) -> int:
	return district[idx(c)] if inside(c) else 5


func walkable(c: Vector2i) -> bool:
	return inside(c) and blocked[idx(c)] == 0


func building(id: int) -> Dictionary:
	return buildings[id] if id >= 0 and id < buildings.size() else {}


func tile_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * 32 + 16, c.y * 32 + 16)


static func to_tile(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / 32.0)), int(floor(p.y / 32.0)))
