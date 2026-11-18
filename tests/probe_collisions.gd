extends SceneTree
## Messung 18.11.: wie entstehen Unfaelle im Stadtverkehr (Richtungen, Abstand, Felder, Wartezeit)?
func _init() -> void:
	var T = load("res://tests/run_tests.gd").new()
	var s: Simulation = T.new_sim(2)
	var orig := s.collisions.check_accidents
	for i in 1500:
		s.step(0.1)
		for t in s._hash:
			var l: Array = s._hash[t]
			for a in l:
				for b in l:
					if a != b and a.get_instance_id() < b.get_instance_id() and a.pos.distance_to(b.pos) < Collisions.CRASH and not a.arrived() and not b.arrived():
						print("t=%.1f Feld %s d=%.1f  A h=%s next=%s goal=%s wait=%.1f lane=%.0f | B h=%s next=%s goal=%s wait=%.1f  dot=%.2f" % [s.sim_time, str(t), a.pos.distance_to(b.pos),
							str(a.heading.snapped(Vector2(0.1,0.1))), str(a.next_tile()), str(a.goal), a.wait_time, a.lane, str(b.heading.snapped(Vector2(0.1,0.1))), str(b.next_tile()), str(b.goal), b.wait_time, a.heading.dot(b.heading)])
	print("Unfaelle ", s.collisions.stats.unfaelle)
	quit()
