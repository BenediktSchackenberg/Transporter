class_name CityData
extends RefCounted
## Reine Kartendaten (ohne Rendering). Wird deterministisch aus dem Seed erzeugt.

enum G { GRASS, PARK, GRAVEL, SIDEWALK, PLAZA, CONCRETE, QUAY, SAND, FIELD, CROP, WATER, RAIL, ROAD, PARKING }

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
var depot_sites: Array = []         # Gebaeude-IDs der Depotstandorte
var start_depots: Array = []        # Gebaeude-IDs, Reihenfolge = Spieler 0..3
var road_count := 0


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
