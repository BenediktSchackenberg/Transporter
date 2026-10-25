class_name EndScreen
extends Control
## Endauswertung: Platzierung, Gewinn, Umsatz, Kosten, Auftraege, Reputation und wichtige Ereignisse.

signal menu_pressed


func show_results(sim: Simulation, reason: String, controllers: Array) -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1180, 680)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var rank := sim.ranking()
	v.add_child(UITheme.label("ENDAUSWERTUNG", 32, UITheme.ACCENT))
	v.add_child(UITheme.label("%s · %s · Sieger: %s (%s)" % [reason, Catalog.game_minutes_to_text(sim.game_min),
		rank[0].company_name, rank[0].player_name], 16))
	var grid := GridContainer.new()
	var heads := ["Platz", "Firma", "Gewinn", "Umsatz", "Kosten", "Aufträge (pünktl./versp./gesch.)", "Ruf", "Bargeld",
		"Schulden", "Geschäfte", "Sabotage (ok/erwischt)", "Steuerung"]
	grid.columns = heads.size()
	grid.add_theme_constant_override("h_separation", 14)
	v.add_child(grid)
	for h in heads:
		grid.add_child(UITheme.label(h, 12, UITheme.MUTED))
	for i in rank.size():
		var c: Company = rank[i]
		var L := c.ledger
		var ctl: AgentController = controllers[c.id]
		var mode := "DEMO" if ctl.is_demo() else str(ctl.config.get("model", "KI"))
		if ctl.stats.ok == 0 and not ctl.is_demo():
			mode += " (nur Ersatzmodus)"
		var cells := ["%d." % (i + 1), c.company_name, Catalog.money(L.profit()), Catalog.money(L.revenue()),
			Catalog.money(L.costs()), "%d (%d/%d/%d)" % [c.stats.completed, c.stats.on_time, c.stats.late, c.stats.failed],
			"%d" % int(c.reputation), Catalog.money(L.cash), Catalog.money(L.debt), str(c.stats.deals),
			"%d/%d" % [c.stats.sabotage_ok, c.stats.sabotage_caught], mode]
		for k in cells.size():
			var col := c.color.lightened(0.3) if k == 1 else (UITheme.ACCENT if i == 0 else UITheme.TEXT)
			if k == 2:
				col = UITheme.GOOD if L.profit() >= 0.0 else UITheme.BAD
			grid.add_child(UITheme.label(cells[k], 15 if k < 3 else 13, col))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 12)
	var txt := "[color=#999]Wertung: kumulierter Nettogewinn = Erlöse − laufende Kosten − Abschreibungen − Zinsen − Vertragsstrafen − sonstige Aufwendungen. Startkapital und Kredite zählen nicht. Bei Spielende wurden überfällige Aufträge bestraft und unvollständige nicht vergütet. Gleichstand: Reputation, dann erledigte Aufträge.[/color]\n\n"
	for c in rank:
		txt += "[color=#%s][b]%s[/b][/color]\n" % [c.color.lightened(0.3).to_html(false), c.company_name]
		for e in c.key_events:
			txt += "  • %s\n" % e.replace("[", "[lb]")
		if c.key_events.is_empty():
			txt += "  • (keine besonderen Ereignisse)\n"
	rt.text = txt
	v.add_child(rt)
	var buttons := HBoxContainer.new()
	v.add_child(buttons)
	var menu := Button.new()
	menu.text = "Neue Partie"
	menu.pressed.connect(func(): menu_pressed.emit())
	buttons.add_child(menu)
	var close := Button.new()
	close.text = "Weiter zuschauen (Stadt bleibt stehen)"
	close.pressed.connect(func(): visible = false)
	buttons.add_child(close)
	var quit := Button.new()
	quit.text = "Beenden"
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)
