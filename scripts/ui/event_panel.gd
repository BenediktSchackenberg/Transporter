class_name EventPanel
extends PanelContainer
## Ereignisregler fuer Zuschauer: Ereignis waehlen, Parameter und Dauer einstellen, ausloesen.
## Darunter: aktive/vergangene Ereignisse mit gemessenen Veraenderungen je Unternehmen.

var session: GameSession
var type_opt: OptionButton
var ware_opt: OptionButton
var factor_spin: SpinBox
var duration_spin: SpinBox
var info: Label
var list_rt: RichTextLabel
var _refresh := 0.0


func build(s: GameSession) -> void:
	session = s
	theme = UITheme.get_theme()
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -380
	offset_right = 380
	offset_top = 60
	offset_bottom = 560
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UITheme.label("EREIGNISREGLER", 20, UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Schließen"
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	var form := GridContainer.new()
	form.columns = 2
	v.add_child(form)
	form.add_child(UITheme.label("Ereignis:", 12, UITheme.MUTED))
	type_opt = OptionButton.new()
	for k in EventDirector.TYPES:
		type_opt.add_item(EventDirector.TYPES[k])
	form.add_child(type_opt)
	form.add_child(UITheme.label("Ware (Nachfrage):", 12, UITheme.MUTED))
	ware_opt = OptionButton.new()
	for k in Catalog.CARGO:
		ware_opt.add_item(Catalog.CARGO[k].name)
	form.add_child(ware_opt)
	form.add_child(UITheme.label("Faktor (Preis/Nachfrage) bzw. Anteil (Mangel):", 12, UITheme.MUTED))
	factor_spin = SpinBox.new()
	factor_spin.min_value = 0.1
	factor_spin.max_value = 4.0
	factor_spin.step = 0.1
	factor_spin.value = 1.6
	form.add_child(factor_spin)
	form.add_child(UITheme.label("Dauer (Spielminuten):", 12, UITheme.MUTED))
	duration_spin = SpinBox.new()
	duration_spin.min_value = 30
	duration_spin.max_value = 2880
	duration_spin.step = 30
	duration_spin.value = 240
	form.add_child(duration_spin)
	var go := Button.new()
	go.text = "Auslösen"
	go.pressed.connect(_trigger)
	v.add_child(go)
	info = UITheme.label("Straßensperre: wirkt auf den nächsten Straßenabschnitt in der Bildmitte.", 12, UITheme.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	list_rt = RichTextLabel.new()
	list_rt.bbcode_enabled = true
	list_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_rt.add_theme_font_size_override("normal_font_size", 12)
	v.add_child(list_rt)
	visible = false


func _trigger() -> void:
	var typ: String = EventDirector.TYPES.keys()[type_opt.selected]
	var cell := CityData.to_tile(Iso.to_world(session.city_view.camera.get_screen_center_position()))
	var params := {"cell": [cell.x, cell.y], "faktor": factor_spin.value, "anteil": clampf(factor_spin.value, 0.1, 1.0),
		"ware": Catalog.CARGO.keys()[ware_opt.selected]}
	var r: Dictionary = session.trigger_event(typ, params, duration_spin.value)
	info.text = r.msg
	_refresh = 0.0


func _process(delta: float) -> void:
	if not visible or session == null:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 1.0
	var txt := ""
	var evs: Array = session.sim.events.events.duplicate()
	evs.reverse()
	for e in evs:
		txt += "[color=#f2c14e]%s[/color] %s – %s (%s bis %s)\n" % [e.id, Catalog.game_time_short(e.start), e.text,
			e.status, Catalog.game_time_short(e.ende) if float(e.ende) < 90000.0 else "dauerhaft"]
		for line in session.sim.events.impact(e):
			txt += "   [color=#bbb]%s[/color]\n" % line.replace("[", "[lb]")
	list_rt.text = txt if txt != "" else "[color=#999]Noch keine Ereignisse ausgelöst.[/color]"
