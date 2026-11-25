extends SceneTree
## Strassenverbindung zwischen zwei Feldern (nur Strassenfelder, 4er-Nachbarschaft): Laenge und Staedte unterwegs.
##   godot --headless --path . -s tests/probe_road_link.gd -- <spielstand.json> x1,y1 x2,y2
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var d = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var p1 := Vector2i(int(a[1].split(",")[0]), int(a[1].split(",")[1]))
	var p2 := Vector2i(int(a[2].split(",")[0]), int(a[2].split(",")[1]))
	print("Siedlungen: %s" % str(s.settlements.keys().map(func(k): return [k, s.settlements[k].get("rect", [])])))
	print("Umspannwerk U0: %s" % str(s.grid.net.nodes.get("U0", {}).get("cell", "?")))
	var nav: Array = s.nav.road_path(p1, p2)
	print("Navigation road_path: %d Felder%s" % [nav.size(), "" if nav.is_empty() else ", Nicht-Strassenfelder unterwegs: %s" % str(nav.filter(func(c): return not s.city.is_road(c)).slice(0, 12))])
	print("road_link Stadt 0: %s" % JSON.stringify(s.eko.settle.road_link(0)))
	var parent := {p1: p1}
	var q: Array = [p1]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		if c == p2:
			break
		for dv in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var n: Vector2i = c + dv
			if not parent.has(n) and s.city.inside(n) and s.city.is_road(n):
				parent[n] = c
				q.append(n)
	if not parent.has(p2):
		print("keine Strassenverbindung (%d Felder erreichbar)" % parent.size())
		# Luecke: kuerzester Abstand zwischen den beiden Strassennetzen
		var other := {p2: true}
		var q2: Array = [p2]
		var j := 0
		while j < q2.size():
			var c2: Vector2i = q2[j]
			j += 1
			for dv in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var n2: Vector2i = c2 + dv
				if not other.has(n2) and s.city.inside(n2) and s.city.is_road(n2):
					other[n2] = true
					q2.append(n2)
		var best := 1 << 30
		var pair := []
		for c in parent:
			for o in other:
				var dd: int = absi(c.x - o.x) + absi(c.y - o.y)
				if dd < best:
					best = dd
					pair = [c, o]
		print("zweites Netz %d Felder; kuerzeste Luecke %d Felder zwischen %s und %s" % [other.size(), best, str(pair[0]), str(pair[1])])
		quit()
		return
	var path: Array = [p2]
	while path[-1] != p1:
		path.append(parent[path[-1]])
	path.reverse()
	var runs: Array = []
	for c in path:
		var tag := "%d%s" % [s.city.town_of(c), "" if s.serves_town(c, 0) else "!"]
		if runs.is_empty() or runs[-1][0] != tag:
			runs.append([tag, c, 0])
		runs[-1][2] += 1
	print("Weg %d Felder: %s" % [path.size(), str(runs.map(func(r): return "%s ab %s x%d" % r))])
	quit()
