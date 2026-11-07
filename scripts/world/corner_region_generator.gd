class_name CornerRegionGenerator
extends RegionGenerator
## Neue Partien: eine Landmasse zwischen West- und Ostkueste, mit einem Ort je gewaehlter Eckregion.
## Der bisherige RegionGenerator bleibt fuer Spielstaende mit Generatorversion 2 erhalten.

const CORNERS := ["NW", "NO", "SW", "SO"]
var west_coast := PackedInt32Array()


func generate(seed_value: int, map_size: int = Catalog.MAP_SIZE, reserve_share: float = 0.0) -> CityData:
	var cd := super.generate(seed_value, map_size, reserve_share)
	if report.ok:
		cd.gen_params["generator"] = 3
	return cd


static func selected_corners(seed_value: int, count: int) -> Array:
	if count >= 4:
		return CORNERS.duplicate()
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 43 + 29
	if count == 2:
		return ["NW", "SO"] if r.randi() % 2 == 0 else ["NO", "SW"]
	var omitted: int = r.randi() % 4
	var result: Array = []
	for k in 4:
		if k != omitted:
			result.append(CORNERS[k])
	return result


func _sea() -> void:
	super._sea()
	west_coast.resize(n)
	for y in n:
		west_coast[y] = n - 1 - coast[y]
		for x in range(west_coast[y] + 1):
			var i := c.idx(Vector2i(x, y))
			c.ground[i] = G.WATER if x < west_coast[y] else G.SAND
			c.blocked[i] = 1 if x < west_coast[y] else 0
		for x in range(west_coast[y] + 1, mini(n, west_coast[y] + 3)):
			c.ground[c.idx(Vector2i(x, y))] = G.SAND


func _generate_once(seed_value: int, map_size: int) -> CityData:
	reserve = 0.0
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.035
	n = map_size
	c = CityData.new()
	c.setup(n, seed_value)
	c.world = "region"
	heights = PackedByteArray()
	heights.resize(n * n)
	towns_out = []
	_rects = []
	_air_rects = []
	_sea()
	var chosen := selected_corners(seed_value, town_count)
	var names := town_names(seed_value, town_count)
	for k in chosen.size():
		var corner: String = chosen[k]
		var top := corner.begins_with("N")
		var left := corner.ends_with("W")
		var y := int(n * (0.18 if top else 0.82) + rng.randf_range(-0.025, 0.025) * n)
		y = clampi(y, 62, n - 63)
		var east_x: int = coast[y] - 6
		var x := n - 1 - east_x if left else east_x
		var r := Rect2i(x - 5 if left else x - 40, y - 24, 46, 48)
		_rects.append(r)
		towns_out.append({"id": k, "name": names[k], "center": [x, y], "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "ecke": corner})
	town = Vector2i(int(towns_out[0].center[0]), int(towns_out[0].center[1]))
	town_rect = _rects[0]
	_mountains_corners()
	_lakes_corners()
	_river_corners()
	var chars: Array = CHARACTERS.duplicate()
	for i in range(chars.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = chars[i]
		chars[i] = chars[j]
		chars[j] = tmp
	for k in town_count:
		towns_out[k]["charakter"] = chars[k]
		if str(towns_out[k].ecke).ends_with("W"):
			_build_mirrored_town(k)
		else:
			_build_town(k)
	_connect_towns()
	_land_cover_region()
	c.height = heights
	_finish()
	c.towns = towns_out
	c.town_name = str(towns_out[0].name)
	c.airport = towns_out[0].get("airport", {})
	center = Vector2(town)
	return c


func _mountains_corners() -> void:
	var centers: Array = []
	var tries := 0
	while centers.size() < 4 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(n * 0.36, n * 0.64), rng.randf_range(n * 0.13, n * 0.87))
		if centers.any(func(q): return q.distance_to(p) < n * 0.16):
			continue
		centers.append(p)
	for ctr in centers:
		var rad := n * rng.randf_range(0.045, 0.07)
		for y in range(maxi(1, int(ctr.y - rad)), mini(n - 1, int(ctr.y + rad))):
			for x in range(maxi(1, int(ctr.x - rad)), mini(n - 1, int(ctr.x + rad))):
				var p := Vector2i(x, y)
				var d := Vector2(p).distance_to(ctr) / rad + noise.get_noise_2d(x * 3, y * 3) * 0.2
				if d >= 1.0:
					continue
				var i := c.idx(p)
				heights[i] = maxi(heights[i], clampi(int((1.0 - d) * 11.0), 1, 11))
				c.blocked[i] = 1
	_prune_specks()


func _lakes_corners() -> void:
	var made := 0
	var tries := 0
	while made < 2 and tries < 200:
		tries += 1
		var ctr := Vector2i(rng.randi_range(int(n * 0.34), int(n * 0.66)), rng.randi_range(int(n * 0.28), int(n * 0.72)))
		var clear := true
		for y in range(ctr.y - 8, ctr.y + 9):
			for x in range(ctr.x - 8, ctr.x + 9):
				if heights[c.idx(Vector2i(x, y))] > 0 or c.ground[c.idx(Vector2i(x, y))] == G.WATER:
					clear = false
		if not clear or c.lakes.any(func(q): return q.distance_to(ctr) < 30):
			continue
		for y in range(ctr.y - 7, ctr.y + 8):
			for x in range(ctr.x - 7, ctr.x + 8):
				var d := Vector2(Vector2i(x, y)).distance_to(Vector2(ctr)) + noise.get_noise_2d(x * 5, y * 5) * 2.0
				if d < 6.0:
					var i := c.idx(Vector2i(x, y))
					c.ground[i] = G.WATER
					c.blocked[i] = 1
		c.lakes.append(ctr)
		made += 1


func _river_corners() -> void:
	# Die Muendung liegt zwischen den Nord- und Suedorten; die Landstrassen koennen sie umrunden.
	var y0 := int(n * 0.5)
	for x in range(int(n * 0.58), n):
		var y := y0 + int(round(9.0 * sin(float(x) * 0.045)))
		for dy in 2:
			var p := Vector2i(x, y + dy)
			if c.inside(p) and heights[c.idx(p)] == 0:
				c.ground[c.idx(p)] = G.WATER
				c.blocked[c.idx(p)] = 1
				c.river.append(p)


func _build_mirrored_town(k: int) -> void:
	# Die bewaehrte Orts- und Flughafenplanung wird auf einer leeren Ostkueste ausgefuehrt.
	# Anschliessend werden ihre befahrbaren Zellen und Objekte geometrisch nach Westen gespiegelt.
	var actual := c
	var actual_rect: Rect2i = _rects[k]
	var actual_t: Dictionary = towns_out[k]
	var actual_x: int = int(actual_t.center[0])
	var east_x := n - 1 - actual_x
	var virtual_rect := Rect2i(east_x - 40, int(actual_t.center[1]) - 24, 46, 48)
	var temp := CityData.new()
	temp.setup(n, int(actual.seed_value))
	for y in n:
		for x in range(coast[y] - 2, n):
			var i := temp.idx(Vector2i(x, y))
			temp.ground[i] = G.WATER if x >= coast[y] else G.SAND
			temp.blocked[i] = 1 if x >= coast[y] else 0
	c = temp
	_rects[k] = virtual_rect
	towns_out[k]["center"] = [east_x, int(actual_t.center[1])]
	towns_out[k]["rect"] = [virtual_rect.position.x, virtual_rect.position.y, 46, 48]
	_build_town(k)
	var offset := actual.buildings.size()
	for b0 in temp.buildings:
		var b: Dictionary = b0.duplicate(true)
		b["id"] = offset + int(b.id)
		b["x"] = n - int(b.x) - int(b.w)
		if b.has("parent") and int(b.parent) >= 0:
			b["parent"] = offset + int(b.parent)
		actual.buildings.append(b)
	for y in range(maxi(0, int(actual_t.center[1]) - 56), mini(n, int(actual_t.center[1]) + 57)):
		for x in range(int(n * 0.65), n):
			var src := temp.idx(Vector2i(x, y))
			var dst := actual.idx(Vector2i(n - 1 - x, y))
			actual.ground[dst] = temp.ground[src]
			actual.district[dst] = temp.district[src]
			actual.blocked[dst] = temp.blocked[src]
			actual.building_at[dst] = offset + temp.building_at[src] if temp.building_at[src] >= 0 else temp.building_at[src]
	for sid in temp.start_depots:
		actual.start_depots.append(offset + sid)
	if not temp.start_depots.is_empty():
		towns_out[k]["start_plot"] = offset + int(temp.start_depots[0])
	for key in ["town_hall", "bauhof", "harbor", "port_office"]:
		if int(towns_out[k].get(key, -1)) >= 0:
			towns_out[k][key] = offset + int(towns_out[k][key])
	var air: Dictionary = towns_out[k].get("airport", {}).duplicate(true)
	if not air.is_empty():
		for key in ["terminal", "tower", "hangar", "fire", "cargo"]:
			if air.has(key):
				air[key] = offset + int(air[key])
		air.rect[0] = n - int(air.rect[0]) - int(air.rect[2])
		var lo := int(air.run_x0)
		air.run_x0 = n - 1 - int(air.run_x1)
		air.run_x1 = n - 1 - lo
		air.dir = -1
		for apron in air.apron:
			apron[0] = n - 1 - int(apron[0])
		towns_out[k]["airport"] = air
		actual.airport = air
		_air_rects[-1] = Rect2i(n - airport_rect.end.x, airport_rect.position.y, airport_rect.size.x, airport_rect.size.y)
	c = actual
	_rects[k] = actual_rect
	towns_out[k]["center"] = [actual_x, int(actual_t.center[1])]
	towns_out[k]["rect"] = [actual_rect.position.x, actual_rect.position.y, 46, 48]
	town = Vector2i(actual_x, int(actual_t.center[1]))
	town_rect = actual_rect


func validate(cd: CityData) -> Dictionary:
	var out := super.validate(cd)
	var errs: Array = out.fehler
	for t in cd.towns:
		var corner: String = str(t.get("ecke", ""))
		var x := int(t.center[0])
		var y := int(t.center[1])
		if (corner.begins_with("N") != (y < cd.size / 2)) or (corner.ends_with("W") != (x < cd.size / 2)):
			errs.append("%s liegt nicht in %s" % [t.name, corner])
		var shore := west_coast[y] if corner.ends_with("W") else coast[y]
		if absi(x - shore) > 10:
			errs.append("%s hat keinen Kuestenzugang" % t.name)
	out.ok = errs.is_empty()
	return out
