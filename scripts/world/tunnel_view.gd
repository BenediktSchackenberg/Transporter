class_name TunnelView
extends Node2D
## Sichtbare Portale fuer Tunnelbau und freigegebene Unterquerungen.

var sim: Simulation
var _nodes := {} # Tunnel-ID -> zwei PortalNode
var _clock := 0.0


func setup(simulation: Simulation) -> void:
	sim = simulation
	y_sort_enabled = true


func update_view(delta: float) -> void:
	_clock += delta
	for id in sim.tunnels.items:
		var j: Dictionary = sim.tunnels.items[id]
		if str(j.status) == "abgelehnt":
			continue
		if not _nodes.has(id):
			var portals: Array = []
			for k in 2:
				var n := PortalNode.new()
				n.primary = k == 0
				add_child(n)
				portals.append(n)
			_nodes[id] = portals
		var point: Array = j.from
		var other: Array = j.to
		for k in 2:
			var n: PortalNode = _nodes[id][k]
			var p: Vector2i = Vector2i(int(point[0]), int(point[1])) if k == 0 else Vector2i(int(other[0]), int(other[1]))
			n.position = Iso.to_screen(sim.city.tile_center(p))
			n.status = str(j.status)
			n.progress = sim.tunnels.progress(j)
			n.working = sim.construction.public_running(str(j.project)) if n.status == "im_bau" else false
			n.label = str(j.id)
			n.clock = _clock
			n.queue_redraw()
	for id in _nodes.keys():
		if not sim.tunnels.items.has(id) or str(sim.tunnels.items[id].status) == "abgelehnt":
			for n in _nodes[id]:
				n.queue_free()
			_nodes.erase(id)


func pick(world: Vector2) -> String:
	var cell := CityData.to_tile(world)
	for id in sim.tunnels.items:
		var j: Dictionary = sim.tunnels.items[id]
		if str(j.status) == "abgelehnt":
			continue
		if Vector2i(int(j.from[0]), int(j.from[1])) == cell or Vector2i(int(j.to[0]), int(j.to[1])) == cell:
			return id
	return ""


func center_of(id: String) -> Vector2:
	var j: Dictionary = sim.tunnels.items.get(id, {})
	if j.is_empty():
		return Vector2(-9999, -9999)
	return sim.city.tile_center(Vector2i(int(j.from[0]), int(j.from[1])))


class PortalNode extends Node2D:
	var primary := false
	var status := ""
	var progress := 0.0
	var working := false
	var label := ""
	var clock := 0.0

	func _draw() -> void:
		var open := status == "freigegeben"
		var shell := Color("8f8170") if open else Color("b7a58c")
		var dark := Color("18242b") if open else Color("404143")
		draw_colored_polygon(PackedVector2Array([Vector2(-20, -8), Vector2(-18, -24), Vector2(-11, -33), Vector2(11, -33), Vector2(18, -24), Vector2(20, -8), Vector2(20, 3), Vector2(-20, 3)]), shell)
		draw_colored_polygon(PackedVector2Array([Vector2(-14, -7), Vector2(-13, -22), Vector2(-8, -28), Vector2(8, -28), Vector2(13, -22), Vector2(14, -7), Vector2(14, 1), Vector2(-14, 1)]), dark)
		draw_rect(Rect2(-23, 1, 46, 5), Color("72685e"))
		draw_line(Vector2(-18, -24), Vector2(-11, -33), Color("d2c3ae"), 2.0)
		draw_line(Vector2(11, -33), Vector2(18, -24), Color("d2c3ae"), 2.0)
		if open:
			draw_circle(Vector2(-12, -10), 2.5, Color("ffdc76"))
			draw_circle(Vector2(12, -10), 2.5, Color("ffdc76"))
			draw_line(Vector2(-10, 2), Vector2(10, 2), Color("ded9b9"), 1.2)
		else:
			draw_line(Vector2(-13, -4), Vector2(13, -4), Color("e98c38"), 4.0)
			draw_line(Vector2(-12, -4), Vector2(-7, -4), Color("f6d96f"), 2.0)
			draw_line(Vector2(0, -4), Vector2(5, -4), Color("f6d96f"), 2.0)
			if primary:
				draw_rect(Rect2(-21, 10, 42, 4), Color("413c36"))
				draw_rect(Rect2(-21, 10, 42 * progress, 4), Color("e4a642"))
				if working:
					var x := -23.0 + sin(clock * 2.1) * 4.0
					draw_circle(Vector2(x, -1), 3.0, Color("f3c394"))
					draw_rect(Rect2(x - 3, 2, 6, 7), Color("e2782c"))
					draw_line(Vector2(x + 2, 6), Vector2(x + 8, 0), Color("8b6d4f"), 1.5)
