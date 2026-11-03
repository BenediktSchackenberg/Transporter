extends SceneTree
## Godot --headless --path . -s res://tests/test_entrepreneur_hud.gd

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FEHLER: ", description)


func _run() -> void:
	var configured: Array = []
	for i in 2:
		configured.append({"slot": i, "player_name": "Spieler%d" % i, "company_name": "Firma%d" % i,
			"color_idx": i, "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i],
			"provider": "demo", "model": "demo", "interval": 30.0, "max_requests": 20, "max_tokens": 10000})
	var game := GameSession.new()
	root.add_child(game)
	game.start({"seed": 4242, "duration_min": 5, "map_size": 128, "weather": "sim", "players": configured})
	await process_frame
	_check(game.hud.cards.size() == 2, "ein Porträt pro Unternehmer")
	_check(game.hud.left_box.get_child_count() == 3, "Bürgermeister-Karte plus ein Porträt je Unternehmer, keine Detailkarten")
	_check(game.hud.left_box.get_child(0) == game.hud.mayor_card.panel, "Bürgermeister steht als erste Karte oben")
	_check(game.hud.left_scroll.size.x <= 220, "schmale Porträtleiste")
	game.controllers[0].goal = "Neue Kunden gewinnen"
	game.sim.plans.set_plan(0, {"ziel": "Aufträge erweitern", "schritte": [{"id": "S1", "text": "Offene Aufträge prüfen"}]})
	game.hud._open_entrepreneur(game.hud.cards[0].cid)
	_check(game.hud.entrepreneur_window.visible, "Porträt öffnet das Detailfenster")
	_check(game.hud.entrepreneur_title.text.contains("Firma0"), "gewähltes Unternehmen im Fenster")
	_check(game.hud.entrepreneur_business.text.contains("Bargeld"), "Unternehmensdaten im Fenster")
	_check(game.hud.entrepreneur_ai.text.contains("Neue Kunden gewinnen"), "selbst formuliertes Ziel im Fenster")
	_check(game.hud.entrepreneur_ai.text.contains("Offene Aufträge prüfen"), "Planschritte im Fenster")
	game.hud._close_entrepreneur()
	# Bürgermeister: Karte zeigt Modus und Tun, Klick öffnet Entscheidungen
	game.sim.mayor.decisions.append({"day": 1, "action": "designate_quarter", "ok": true, "reason": "Wohnraum knapp", "msg": "Quartier beschlossen"})
	game.mayor_agent.summaries.append({"t": 10.0, "text": "Ich weise ein Wohnquartier aus.", "source": "KI"})
	game.hud._update_cards()
	_check(game.hud.mayor_card.mode.text == "Regeln", "Karte nennt die Steuerung (%s)" % game.hud.mayor_card.mode.text)
	_check(game.hud.mayor_card.act.text.contains("designate_quarter"), "Karte zeigt die letzte Aktion (%s)" % game.hud.mayor_card.act.text)
	game.hud._open_entrepreneur(game.hud.MAYOR_VIEW)
	_check(game.hud.entrepreneur_window.visible and game.hud.entrepreneur_title.text.contains("Bürgermeister"), "Klick auf die Karte öffnet die Bürgermeister-Ansicht")
	_check(not game.hud.entrepreneur_actions.visible, "Unternehmer-Schaltflächen sind im Bürgermeister-Fenster ausgeblendet")
	_check(game.hud.entrepreneur_ai.text.contains("Wohnraum knapp") and game.hud.entrepreneur_ai.text.contains("Ich weise ein Wohnquartier aus."), "Entscheidungen mit Begründung im Fenster")
	_check(game.hud.entrepreneur_business.text.contains("Stadtkasse"), "Lage der Stadt im Fenster")
	_check(game.hud.entrepreneur_business.text.contains("RATHAUS") and game.hud.entrepreneur_business.text.contains("Bauamt"), "Rathaus mit Abteilungen im Fenster")
	game.hud._close_entrepreneur()
	game.hud._open_entrepreneur(game.hud.cards[0].cid)
	_check(game.hud.entrepreneur_actions.visible, "Unternehmer-Fenster zeigt seine Schaltflächen wieder")
	game.hud._close_entrepreneur()
	_check(not game.hud.entrepreneur_window.visible, "Fenster lässt sich schließen")
	game.free()
	print("%d Prüfungen, %d Fehler" % [checks, failures])
	quit(1 if failures > 0 else 0)
