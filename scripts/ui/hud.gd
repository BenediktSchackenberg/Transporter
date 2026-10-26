class_name HUD
extends Control
## Zuschaueroberflaeche: Restzeit/Spielzeit/Geschwindigkeit, Firmenvergleich mit API-Status,
## Ereignis- und Dialogprotokoll, Auftrags-/Fahrzeuglisten, Finanzen mit Gewinnformel, KI-Statistik,
## Minimap und Auswahlinfo mit Kamera-Folgen.

var session: GameSession
var sim: Simulation
var lbl_remaining: Label
var lbl_clock: Label
var lbl_speed: Label
var wx_icon: TextureRect
var wx_summary: Label
var wx_field: PanelContainer
var pause_btn: Button
var speed_btns: Array = []
var cards: Array = []            # Portraet-Schaltflaechen der Unternehmer
var entrepreneur_window: ColorRect
var entrepreneur_title: Label
var entrepreneur_subtitle: Label
var entrepreneur_portrait: TextureRect
var entrepreneur_business: RichTextLabel
var entrepreneur_ai: RichTextLabel
var entrepreneur_company := -1
var tabs: TabContainer
var activity_rt: RichTextLabel
var situation_rt: RichTextLabel
var events_rt: RichTextLabel
var dialog_rt: RichTextLabel
var contracts_tree: Tree
var vehicles_tree: Tree
var chart: ProfitChart
var finance_rt: RichTextLabel
var ai_rt: RichTextLabel
var staff_rt: RichTextLabel
var decisions_rt: RichTextLabel
var decision_filter: OptionButton
var event_panel: EventPanel
const DECISION_FILTERS := [["Alle", ""], ["Strategie (API-Modell)", "api"], ["Planschritte", "plan"], ["Ersatzmodus/Demo", "fallback"],
	["Vorarbeiter", "foreman"], ["Simulation", "auto"], ["Zuschauer", "spectator"], ["Stadt (Ereignisse)", "world"], ["nur abgelehnt", "abgelehnt"]]
var minimap: Minimap
var sel_title: Label
var sel_text: RichTextLabel
var follow_btn: Button
var toast: Label
var left_box: VBoxContainer
var left_scroll: ScrollContainer
var economy_rt: RichTextLabel
var economy_view := 0
const ECONOMY_VIEWS := ["Rangliste", "Banken", "Firmen", "Bauhof", "Haushalte", "Staat", "Bürger"]
var decision_company := -1
var decision_company_opt: OptionButton
var sel_panel: PanelContainer
var _events_shown := 0
var _msgs_shown := 0
var _refresh := 0.0
var _toast_time := 0.0


func build(s: GameSession) -> void:
	session = s
	sim = s.sim
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_left()
	_build_right()
	_build_bottom()
	event_panel = EventPanel.new()
	add_child(event_panel)
	event_panel.build(session)
	toast = UITheme.label("", 20, UITheme.ACCENT)
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -330
	toast.offset_right = 330
	toast.offset_top = 52
	toast.offset_bottom = 84
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 5)
	add_child(toast)
	_build_entrepreneur_window()


func _build_top() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = 40
	add_child(top)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	top.add_child(h)
	h.add_child(_icon("i_clock"))
	lbl_remaining = UITheme.label("", 20, UITheme.ACCENT)
	lbl_remaining.tooltip_text = "Verbleibende Partiedauer in aktiver Echtzeit (Pausen und Menüs zählen nicht)."
	lbl_remaining.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(lbl_remaining)
	h.add_child(VSeparator.new())
	lbl_clock = UITheme.label("", 16)
	lbl_clock.tooltip_text = "Spielzeit (Tag/Uhrzeit in der Stadt)"
	lbl_clock.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(lbl_clock)
	h.add_child(VSeparator.new())
	h.add_child(_build_weather_field())
	h.add_child(VSeparator.new())
	pause_btn = Button.new()
	pause_btn.text = "Pause"
	pause_btn.pressed.connect(func(): session.toggle_pause())
	h.add_child(pause_btn)
	var group := ButtonGroup.new()
	for i in GameSession.SPEEDS.size():
		var b := Button.new()
		b.text = "%dx" % GameSession.SPEEDS[i]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func(): session.set_speed_idx(i))
		h.add_child(b)
		speed_btns.append(b)
	lbl_speed = UITheme.label("", 16, UITheme.MUTED)
	lbl_speed.tooltip_text = "Simulationsgeschwindigkeit: beschleunigt nur die Spielwelt, nicht die Partiedauer."
	lbl_speed.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(lbl_speed)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	for spec in [["Ereignisse", func(): event_panel.visible = not event_panel.visible], ["Speichern", func(): session.save_game()], ["Laden", func(): session.load_requested.emit()],
			["Partie beenden", Callable()], ["Menü", func(): session.back_to_menu()]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE   # Leertaste/Enter loesen keine Leistenknoepfe aus
		if spec[0] == "Partie beenden":
			b.pressed.connect(func(): _confirm_end(b))
		else:
			b.pressed.connect(spec[1])
		h.add_child(b)


## Partie erst nach zweitem Klick innerhalb von 4 Sekunden beenden (Schutz vor Fehlklicks).
func _confirm_end(b: Button) -> void:
	if b.text == "Wirklich beenden?":
		session.end_match("vom Zuschauer beendet")
		return
	b.text = "Wirklich beenden?"
	get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(b): b.text = "Partie beenden")


func _icon(name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/gfx/%s.png" % name)
	t.custom_minimum_size = Vector2(24, 24)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return t


## Stadtansicht [Tab]: blendet alle Panels ausser der Kopfleiste aus.
func toggle_panels() -> void:
	if entrepreneur_window.visible:
		_close_entrepreneur()
		return
	for n in [left_scroll, tabs, minimap, sel_panel]:
		n.visible = not n.visible


func _build_left() -> void:
	left_scroll = ScrollContainer.new()
	left_scroll.anchor_bottom = 1.0
	left_scroll.offset_left = 6
	left_scroll.offset_top = 46
	left_scroll.offset_right = 92
	left_scroll.offset_bottom = -234   # ueber der Minimap
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(left_scroll)
	var box := VBoxContainer.new()
	left_box = box
	box.custom_minimum_size = Vector2(78, 0)
	box.add_theme_constant_override("separation", 8)
	left_scroll.add_child(box)
	for c in sim.companies:
		var p := PanelContainer.new()
		var sb := UITheme.box(UITheme.PANEL, c.color, 3, 3)
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cid := c.id
		var bt := TextureButton.new()
		bt.texture_normal = UITheme.portrait(c.avatar_style)
		bt.texture_hover = bt.texture_normal
		bt.texture_pressed = bt.texture_normal
		bt.ignore_texture_size = true
		bt.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		bt.custom_minimum_size = Vector2(70, 70)
		bt.focus_mode = Control.FOCUS_NONE
		bt.tooltip_text = "%s · %s\nDetails öffnen" % [c.player_name, c.company_name]
		bt.pressed.connect(func(): _open_entrepreneur(cid))
		p.add_child(bt)
		box.add_child(p)
		cards.append({"panel": p, "button": bt})


func _card_action(kind: String, cid: int) -> void:
	_close_entrepreneur()
	match kind:
		"Folgen":
			session.follow({"kind": "avatar", "id": cid})
		"Betriebshof":
			for p in sim.estate.plot_of(cid):
				if int(p.parent) < 0:
					session.camera_to(Vector2((p.x + p.w * 0.5) * 32.0, (p.y + p.h * 0.5) * 32.0))
					break
		"Verlauf":
			decision_company = cid
			decision_company_opt.select(cid + 1)
			for i in tabs.get_tab_count():
				if tabs.get_tab_control(i).name == "Entscheidungen":
					tabs.current_tab = i


## Kompakter Wetterindikator in der Kopfleiste; Details stehen im Tooltip.
func _build_weather_field() -> PanelContainer:
	var p := PanelContainer.new()
	wx_field = p
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	p.add_child(row)
	wx_icon = TextureRect.new()
	wx_icon.custom_minimum_size = Vector2(24, 24)
	wx_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wx_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wx_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wx_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wx_icon)
	wx_summary = UITheme.label("", 14)
	wx_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wx_summary)
	return p


func _update_weather() -> void:
	var w: Weather = sim.wx
	var c: Dictionary = w.cur
	var now := Time.get_unix_time_from_system()
	var st := w.status(now)
	wx_icon.texture = load("res://assets/gfx/i_w_%s.png" % Weather.icon_of(c))
	wx_summary.text = "Mainz %.0f° · %s" % [float(c.temp), str(c.text).left(18)]
	var data_t: String = str(c.obs_time).right(5) if str(c.obs_time) != "" else "–"
	var fetched := "–"
	if w.fetched_unix > 0.0:
		fetched = Time.get_time_string_from_unix_time(int(w.fetched_unix + Time.get_time_zone_from_system().bias * 60.0)).left(5)
	var source := ("Daten %s · Abruf %s · %s" % [data_t, fetched, st.to_upper() if st != "aktuell" else st]) if c.source == "open-meteo" else ("Ersatzwetter ohne Live-Daten" if c.source == "simuliert" else "Wiederholung (aufgezeichnet)")
	wx_field.tooltip_text = "Wetter für Mainz (Open-Meteo-Modelldaten)\nRegen %.1f mm/h · Wind %.0f km/h (Böen %.0f)\n%s%s" % [float(c.precip_mm_h), float(c.wind), float(c.gust), source, ("\n" + w.last_error) if w.last_error != "" and st != "aktuell" else ""]
	var col := UITheme.GOOD if st == "aktuell" else (UITheme.WARN if st in ["veraltet", "wiederholung", "simuliert"] else UITheme.BAD)
	wx_summary.add_theme_color_override("font_color", col)


func _build_right() -> void:
	tabs = TabContainer.new()
	tabs.anchor_left = 1.0
	tabs.anchor_right = 1.0
	tabs.anchor_bottom = 1.0
	tabs.offset_left = -440
	tabs.offset_right = -6
	tabs.offset_top = 46
	tabs.offset_bottom = -6
	add_child(tabs)
	activity_rt = _rt("Aktivitäten")
	situation_rt = _rt("Lage")
	_build_economy_tab()
	activity_rt.scroll_following = false
	situation_rt.scroll_following = false
	events_rt = _rt("Ereignisse")
	dialog_rt = _rt("Dialoge")
	contracts_tree = _tree("Aufträge", ["Firma", "Auftrag", "Ware", "Status", "EUR", "Frist"])
	vehicles_tree = _tree("Fahrzeuge", ["Firma", "#", "Modell", "Status", "Zust.", "Auftrag"])
	var fin := VBoxContainer.new()
	fin.name = "Finanzen"
	tabs.add_child(fin)
	var switch := HBoxContainer.new()
	fin.add_child(switch)
	for spec in [["Gewinn", 1], ["Bargeld (Liquidität)", 2]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(func(): chart.series = spec[1]; chart.queue_redraw())
		switch.add_child(b)
	chart = ProfitChart.new()
	chart.sim = sim
	chart.custom_minimum_size = Vector2(0, 200)
	fin.add_child(chart)
	finance_rt = RichTextLabel.new()
	finance_rt.bbcode_enabled = true
	finance_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	finance_rt.add_theme_font_size_override("normal_font_size", 12)
	fin.add_child(finance_rt)
	ai_rt = _rt("KI-Spieler")
	staff_rt = _rt("Personal")
	staff_rt.scroll_following = false
	var dec := VBoxContainer.new()
	dec.name = "Entscheidungen"
	tabs.add_child(dec)
	var frow := HBoxContainer.new()
	dec.add_child(frow)
	decision_filter = OptionButton.new()
	for f in DECISION_FILTERS:
		decision_filter.add_item(f[0])
	frow.add_child(decision_filter)
	decision_company_opt = OptionButton.new()
	decision_company_opt.add_item("Alle Unternehmen")
	for c in sim.companies:
		decision_company_opt.add_item(c.company_name)
	decision_company_opt.item_selected.connect(func(i): decision_company = i - 1)
	frow.add_child(decision_company_opt)
	decisions_rt = RichTextLabel.new()
	decisions_rt.bbcode_enabled = true
	decisions_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	decisions_rt.add_theme_font_size_override("normal_font_size", 12)
	dec.add_child(decisions_rt)


## Ein Reiter "Wirtschaft" mit Umschalter (Rangliste, Banken, Unternehmen, Bauhof) statt vieler einzelner Reiter.
func _build_economy_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Wirtschaft"
	tabs.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	for i in ECONOMY_VIEWS.size():
		var bt := Button.new()
		bt.text = ECONOMY_VIEWS[i]
		bt.toggle_mode = true
		bt.button_pressed = i == 0
		bt.focus_mode = Control.FOCUS_NONE
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.pressed.connect(func():
			economy_view = i
			for j in row.get_child_count():
				(row.get_child(j) as Button).button_pressed = j == i
			_refresh = 0.0)
		row.add_child(bt)
	economy_rt = RichTextLabel.new()
	economy_rt.bbcode_enabled = true
	economy_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	economy_rt.scroll_following = false
	economy_rt.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(economy_rt)


## Reiter nach Name oeffnen (Sichtpruefung per Kommandozeile: --tab=Wirtschaft --econ=2).
func show_tab(tab_name: String, view: int = 0) -> void:
	_close_entrepreneur()
	for i in tabs.get_tab_count():
		if tabs.get_tab_control(i).name == tab_name:
			tabs.current_tab = i
	economy_view = view
	_refresh = 0.0
	if economy_rt != null:
		var row := economy_rt.get_parent().get_child(0)
		for j in row.get_child_count():
			(row.get_child(j) as Button).button_pressed = j == view


func _economy_text() -> String:
	match economy_view:
		1: return LiveText.banks(sim)
		2: return LiveText.firms(sim)
		3: return LiveText.trader(sim)
		4: return LiveText.households(sim)
		5: return LiveText.public_sector(sim)
		6: return LiveText.citizens(sim)
	return LiveText.standings(sim)


func _rt(title: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.name = title
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.add_theme_font_size_override("normal_font_size", 12)
	tabs.add_child(rt)
	return rt


func _tree(title: String, cols: Array) -> Tree:
	var t := Tree.new()
	t.name = title
	t.columns = cols.size()
	t.hide_root = true
	t.column_titles_visible = true
	for i in cols.size():
		t.set_column_title(i, cols[i])
		t.set_column_expand(i, i in [0, 3])
	t.add_theme_font_size_override("font_size", 12)
	t.item_activated.connect(func():
		var it := t.get_selected()
		if it and it.get_metadata(0) is Dictionary:
			session.follow(it.get_metadata(0)))
	tabs.add_child(t)
	return t


func _build_bottom() -> void:
	minimap = Minimap.new()
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = 6
	minimap.offset_top = -226
	minimap.offset_right = 226
	minimap.offset_bottom = -6
	minimap.build(sim, session.city_view.camera)
	minimap.jump.connect(func(p): session.camera_to(p))
	add_child(minimap)
	var sel := PanelContainer.new()
	sel.anchor_top = 1.0
	sel.anchor_bottom = 1.0
	sel.anchor_right = 1.0
	sel.offset_left = 234
	sel.offset_right = -450
	sel.offset_top = -128
	sel.offset_bottom = -6
	add_child(sel)
	sel_panel = sel
	var v := VBoxContainer.new()
	sel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	sel_title = UITheme.label("Auswahl: Linksklick auf Figur, Fahrzeug oder Gebäude", 16, UITheme.ACCENT)
	sel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sel_title)
	follow_btn = Button.new()
	follow_btn.text = "Folgen"
	follow_btn.toggle_mode = true
	follow_btn.toggled.connect(func(on): session.set_follow(on))
	head.add_child(follow_btn)
	sel_text = RichTextLabel.new()
	sel_text.bbcode_enabled = true
	sel_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sel_text.add_theme_font_size_override("normal_font_size", 12)
	v.add_child(sel_text)


func show_toast(text: String) -> void:
	toast.text = text
	_toast_time = 3.0


## Ein zentrales, live aktualisiertes Fenster fuer die angeklickte Person.
func _build_entrepreneur_window() -> void:
	entrepreneur_window = ColorRect.new()
	entrepreneur_window.color = Color(0.04, 0.05, 0.08, 0.88)
	entrepreneur_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	entrepreneur_window.mouse_filter = Control.MOUSE_FILTER_STOP
	entrepreneur_window.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_entrepreneur())
	add_child(entrepreneur_window)
	var dialog := PanelContainer.new()
	dialog.anchor_left = 0.10
	dialog.anchor_right = 0.90
	dialog.anchor_top = 0.07
	dialog.anchor_bottom = 0.93
	dialog.offset_left = 0
	dialog.offset_right = 0
	dialog.offset_top = 0
	dialog.offset_bottom = 0
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_theme_stylebox_override("panel", UITheme.box(UITheme.BG, UITheme.ACCENT, 3, 14))
	entrepreneur_window.add_child(dialog)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	dialog.add_child(layout)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	layout.add_child(head)
	entrepreneur_portrait = TextureRect.new()
	entrepreneur_portrait.custom_minimum_size = Vector2(76, 76)
	entrepreneur_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	entrepreneur_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(entrepreneur_portrait)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	entrepreneur_title = UITheme.label("", 26, UITheme.ACCENT)
	heading.add_child(entrepreneur_title)
	entrepreneur_subtitle = UITheme.label("", 16, UITheme.MUTED)
	entrepreneur_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(entrepreneur_subtitle)
	var close_btn := Button.new()
	close_btn.text = "Schließen  ×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_entrepreneur)
	head.add_child(close_btn)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	layout.add_child(columns)
	entrepreneur_business = _entrepreneur_column(columns)
	entrepreneur_ai = _entrepreneur_column(columns)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	layout.add_child(actions)
	for kind in ["Folgen", "Betriebshof", "Verlauf"]:
		var b := Button.new()
		b.text = kind
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 38)
		b.pressed.connect(func(): _card_action(kind, entrepreneur_company))
		actions.add_child(b)
	entrepreneur_window.visible = false


func _entrepreneur_column(parent: HBoxContainer) -> RichTextLabel:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, UITheme.BORDER, 1, 12))
	parent.add_child(panel)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_following = false
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 17)
	panel.add_child(rt)
	return rt


func _open_entrepreneur(cid: int) -> void:
	entrepreneur_company = cid
	entrepreneur_window.visible = true
	entrepreneur_business.get_v_scroll_bar().value = 0
	entrepreneur_ai.get_v_scroll_bar().value = 0
	_update_entrepreneur()


func _close_entrepreneur() -> void:
	entrepreneur_window.visible = false
	entrepreneur_company = -1


func _input(event: InputEvent) -> void:
	if entrepreneur_window != null and entrepreneur_window.visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_close_entrepreneur()
		get_viewport().set_input_as_handled()


func _set_entrepreneur_text(rt: RichTextLabel, value: String) -> void:
	if rt.text == value:
		return
	var scroll := rt.get_v_scroll_bar().value
	rt.text = value
	rt.get_v_scroll_bar().value = scroll


func _update_entrepreneur() -> void:
	if entrepreneur_company < 0 or entrepreneur_company >= sim.companies.size():
		return
	var c: Company = sim.company(entrepreneur_company)
	var ctl: AgentController = session.controllers[c.id]
	var L: Ledger = c.ledger
	var plan: Dictionary = sim.plans.summary(c.id)
	var dec: Dictionary = LiveText.last_decision(sim, c)
	var state: Dictionary = LiveText.company_state(sim, ctl, c)
	var rank := sim.ranking().find(c) + 1
	var mode := "Demo · simulierte Antworten" if ctl.is_demo() else "%s · %s" % [str(ctl.config.get("provider", "KI")), str(ctl.config.get("model", ""))]
	if ctl.fallback_active:
		mode += " · regelbasierter Ersatzmodus"
	entrepreneur_title.text = "%s · %s" % [c.player_name, c.company_name]
	entrepreneur_title.add_theme_color_override("font_color", c.color.lightened(0.35))
	entrepreneur_subtitle.text = "Rang %d  ·  %s  ·  %s" % [rank, Catalog.PERSONALITIES[c.personality].name, mode]
	entrepreneur_portrait.texture = UITheme.portrait(c.avatar_style)
	var left := "[color=#f2c14e][b]UNTERNEHMEN[/b][/color]\n"
	left += "Gewinn [b]%s[/b]  ·  Bargeld %s\nSchulden %s  ·  Vermögen %s\n" % [Catalog.money(L.profit()), Catalog.money(L.cash), Catalog.money(L.debt), Catalog.money(sim.net_worth(c.id))]
	left += "Ruf %d  ·  Fahrzeuge %d/%d  ·  Personal %d\n" % [int(c.reputation), c.vehicle_ids.size(), c.fleet_limit(), sim.personnel.employed(c.id).size()]
	left += "Aufträge erledigt %d  ·  gescheitert %d\nBüro %d  ·  Netz %d  ·  Auftragskapazität %d/%d\n" % [c.stats.completed, c.stats.failed, maxi(c.office_level, c.plot_office_level), c.internet_level, sim.executor.active_contracts(c.id), c.contract_capacity()]
	left += "Sicherheit %d  ·  %s\n\n" % [c.security_level, "versichert" if c.insurance else "nicht versichert"]
	left += "[color=#f2c14e][b]AKTUELLER ZUSTAND[/b][/color]\n"
	left += "[color=#%s][b]%s[/b][/color]%s\n" % [state.farbe.to_html(false), _esc(state.zustand), (" · " + _esc(state.grund)) if state.grund != "" else ""]
	var av: Avatar = sim.avatars[c.id]
	var area: String = Catalog.DISTRICTS[sim.city.district_of(av.tile())]
	left += "Figur in %s: %s\n" % [_esc(area), _esc(LiveText.figure_text(sim, c.id))]
	left += "Betrieb: %s\n" % _esc(LiveText.company_activity(sim, c))
	var staff: Array = sim.personnel.employed(c.id)
	var busy := 0
	for w in staff:
		var task: WorkerTask = sim.personnel.tasks.get(w.task_id)
		if (task != null and not task.is_final() and task.kind != "gehen") or w.vehicle_id >= 0:
			busy += 1
	left += "Personal im Einsatz %d  ·  verfügbar %d\n\n" % [busy, staff.size() - busy]
	left += "[color=#f2c14e][b]LAUFENDE AUFTRÄGE[/b][/color]\n"
	var contracts: Array = sim.contracts.values().filter(func(k): return k.owner == c.id and k.status in ["accepted", "assigned", "loading", "in_transit"])
	contracts.sort_custom(func(x, y): return x.reward > y.reward)
	if contracts.is_empty():
		left += "Keine laufenden Aufträge.\n"
	else:
		for k in contracts.slice(0, 4):
			left += "• %s  ·  %s  ·  %s\n" % [_esc(k.id), _esc(k.cargo_name()), Catalog.money(k.reward)]
		if contracts.size() > 4:
			left += "… und %d weitere\n" % (contracts.size() - 4)
	_set_entrepreneur_text(entrepreneur_business, left)
	var right := "[color=#f2c14e][b]KI-ZIEL UND ANLASS[/b][/color]\n"
	right += "[b]Selbst formuliertes Ziel:[/b] %s\n" % (_esc(ctl.goal) if ctl.goal != "" else "Noch keines formuliert.")
	if not dec.is_empty():
		if not dec.wahrgenommen.is_empty():
			right += "[b]Zuletzt berücksichtigte Ereignisse:[/b] %s\n" % _esc("; ".join(dec.wahrgenommen))
		if dec.ziel != "" and dec.ziel != ctl.goal:
			right += "[b]Ziel bei letzter Entscheidung:[/b] %s\n" % _esc(dec.ziel)
		right += "[b]Letzte dokumentierte Begründung:[/b] %s\n" % (_esc(dec.begruendung) if dec.begruendung != "" else "Keine angegeben.")
	else:
		right += "Noch keine Entscheidung dokumentiert.\n"
	right += "\n[color=#f2c14e][b]WORAN DIE KI ARBEITET[/b][/color]\n"
	if plan.has("ziel"):
		var done: int = plan.schritte.filter(func(step): return step.status in ["erledigt", "uebersprungen"]).size()
		right += "[b]Plan %s:[/b] %s\nStatus %s  ·  %d/%d Schritte erledigt\n" % [_esc(plan.id), _esc(plan.ziel), _esc(plan.status), done, plan.schritte.size()]
		if plan.nutzen != "":
			right += "Erwarteter Nutzen: %s\n" % _esc(plan.nutzen)
		if plan.risiken != "":
			right += "Risiken: %s\n" % _esc(plan.risiken)
		if plan.hinweis != "":
			right += "[color=#ffb347]Hinweis: %s[/color]\n" % _esc(plan.hinweis)
		for step in plan.schritte:
			var mark := "✓" if step.status in ["erledigt", "uebersprungen"] else ("→" if step.id in plan.jetzt_ausfuehrbar else "·")
			right += "%s [b]%s[/b] %s [color=#9a98a8](%s)[/color]%s\n" % [mark, _esc(step.id), _esc(step.text), _esc(step.status), (" – " + _esc(step.ergebnis)) if step.ergebnis != "" else ""]
	else:
		right += "Noch kein Plan angelegt.\n"
	right += "[b]Nächster Schritt:[/b] %s\n\n" % _esc(LiveText.next_step(sim, c))
	right += "[color=#f2c14e][b]LETZTE AKTION UND KI-STATUS[/b][/color]\n"
	if not dec.is_empty():
		right += "%s · %s\n%s → %s\n" % [_esc(dec.id), Catalog.game_time_short(dec.t), _esc(dec.aktion), _esc(dec.ergebnis)]
	else:
		right += "Noch keine Aktion.\n"
	right += "Status: %s\nAnfragen %d  ·  OK %d  ·  Fehler %d  ·  Token %s\n" % [_esc(ctl.status), ctl.stats.requests, ctl.stats.ok, ctl.stats.errors, _k(ctl.stats.tokens, false)]
	if ctl.last_error != "":
		right += "[color=#ff6b5e]Letzter Fehler: %s[/color]\n" % _esc(ctl.last_error)
	_set_entrepreneur_text(entrepreneur_ai, right)


func update_hud(delta: float) -> void:
	_toast_time -= delta
	toast.visible = _toast_time > 0.0
	var rem := session.remaining_seconds()
	if session.is_endless():
		var act := session.active_seconds
		lbl_remaining.text = "Endlos · aktiv %02d:%02d" % [int(act) / 60, int(act) % 60]
	else:
		lbl_remaining.text = "Restzeit %02d:%02d" % [int(rem) / 60, int(rem) % 60]
	lbl_clock.text = GameCalendar.long_text(sim.game_min)
	lbl_clock.tooltip_text = GameCalendar.explain(float(session.speed()))
	pause_btn.text = "Weiter" if session.paused else "Pause"
	lbl_speed.text = "Simulation %dx%s" % [session.speed(), "  (PAUSIERT)" if session.paused else ""]
	for i in speed_btns.size():
		speed_btns[i].set_pressed_no_signal(i == session.speed_idx)
	minimap.queue_redraw()
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.3
	_update_cards()
	_update_weather()
	_append_events()
	_append_messages()
	_update_selection()
	match tabs.get_current_tab_control().name:
		"Aktivitäten": _update_scroll(activity_rt, LiveText.activities(sim, session.controllers))
		"Wirtschaft": _update_scroll(economy_rt, _economy_text())
		"Lage": _update_scroll(situation_rt, LiveText.situation(sim, session.remaining_seconds() / 60.0))
		"Aufträge": _update_contracts()
		"Fahrzeuge": _update_vehicles()
		"Finanzen": _update_finance()
		"KI-Spieler": _update_ai()
		"Personal": _update_staff()
		"Entscheidungen": _update_decisions()


func _update_cards() -> void:
	if entrepreneur_window.visible:
		_update_entrepreneur()


static func _k(v: float, eur := true) -> String:
	var s := ("%.1fk" % (v / 1000.0)) if absf(v) >= 1000.0 else "%.0f" % v
	return s + (" €" if eur else "")


const KIND_COLORS := {"report": "#9fd8ff", "foreman": "#9fd8ff", "money": "#6fd08c", "bad": "#ff6b5e", "warn": "#ffb347", "good": "#8fe0a0", "deal": "#7fc8ff",
	"ai": "#e8d9a8", "system": "#f2c14e", "info": "#c9c4b4"}


func _append_events() -> void:
	var fresh := sim.log_total - _events_shown
	if fresh <= 0:
		return
	var entries := sim.log_entries
	for e in entries.slice(maxi(0, entries.size() - fresh)):
		var col: String = KIND_COLORS.get(e.kind, "#c9c4b4")
		var who := ""
		if e.company >= 0:
			who = "[color=#%s]■[/color] " % sim.company(e.company).color.to_html(false)
		events_rt.append_text("[color=#777]%s[/color] %s[color=%s]%s[/color]
" % [
			Catalog.game_time_short(e.t), who, col, _esc(e.text)])
	_events_shown = sim.log_total


func _append_messages() -> void:
	var total: int = sim.social.next_msg - 1
	var fresh := total - _msgs_shown
	if fresh <= 0:
		return
	var msgs: Array = sim.social.messages
	for m in msgs.slice(maxi(0, msgs.size() - fresh)):
		var from := sim.company(m.from)
		var to := "alle" if m.to == -1 else sim.company(m.to).player_name
		var tag := "[color=#b48cff][vertraulich][/color] " if m.private else ""
		dialog_rt.append_text("[color=#777]%s[/color] %s[color=#%s]%s[/color] → %s: %s
" % [
			Catalog.game_time_short(m.t), tag, from.color.lightened(0.3).to_html(false), from.player_name,
			to, _esc(m.text)])
	_msgs_shown = total


static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


func _update_contracts() -> void:
	var t := contracts_tree
	t.clear()
	var root := t.create_item()
	var list: Array = sim.contracts.values().filter(func(k): return k.owner >= 0 and k.status in ["accepted", "assigned", "loading", "in_transit"])
	list.sort_custom(func(a, b): return a.owner < b.owner)
	for k in list:
		var it := t.create_item(root)
		var c := sim.company(k.owner)
		it.set_text(0, c.player_name)
		it.set_custom_color(0, c.color.lightened(0.3))
		it.set_text(1, k.id)
		it.set_text(2, "%d %s" % [k.qty, Catalog.CARGO[k.cargo].name])
		it.set_text(3, {"accepted": "angenommen", "assigned": "disponiert", "loading": "wird geladen", "in_transit": "unterwegs"}[k.status])
		it.set_text(4, str(int(k.reward)))
		var left: float = k.deadline - sim.game_min
		it.set_text(5, "%d min" % int(left))
		if left < 0:
			it.set_custom_color(5, UITheme.BAD)
		if k.vehicle_id >= 0:
			it.set_metadata(0, {"kind": "vehicle", "id": k.vehicle_id})
	var open := sim.market.open_contracts().size()
	var info := t.create_item(root)
	info.set_text(0, "Markt")
	info.set_text(1, "%d offen" % open)


func _update_vehicles() -> void:
	var t := vehicles_tree
	t.clear()
	var root := t.create_item()
	for c in sim.companies:
		for v in sim.company_vehicles(c.id):
			var it := t.create_item(root)
			it.set_text(0, c.player_name)
			it.set_custom_color(0, c.color.lightened(0.3))
			it.set_text(1, str(v.id))
			it.set_text(2, v.spec().name)
			var st: String = FleetVehicle.STATE_TEXT.get(v.state, v.state)
			if sim.driver_of(v) == null:
				st += " (ohne Fahrer)"
			it.set_text(3, st)
			it.set_text(4, "%d%%" % int(v.condition))
			it.set_text(5, v.contract_id)
			it.set_metadata(0, {"kind": "vehicle", "id": v.id})


func _update_finance() -> void:
	chart.queue_redraw()
	var txt := "[color=#f2c14e]Gewinnwertung[/color] = Erlöse − laufende Kosten − Abschreibungen − Zinsen − Vertragsstrafen − sonstige Aufwendungen.\n"
	txt += "[color=#999]Startkapital und Kredite sind kein Gewinn, Tilgung ist kein Aufwand. Fahrzeugkäufe sind Investitionen (Abschreibung linear 3 %/Spieltag bis 20 % Restwert); Verkäufe buchen Erlös − Buchwert. Prüfsumme: Bargeld + Buchwert (Fahrzeuge + Büros) − Schulden = Startkapital + Gewinn.[/color]\n\n"
	for c in sim.ranking():
		var L: Ledger = c.ledger
		txt += "[color=#%s]%s[/color]: Gewinn [b]%s[/b] · Umsatz %s · Kosten %s · Bargeld %s · Schulden %s · Buchwert Fahrzeuge %s, Büros %s\n" % [
			c.color.lightened(0.3).to_html(false), c.company_name, Catalog.money(L.profit()), Catalog.money(L.revenue()),
			Catalog.money(L.costs()), Catalog.money(L.cash), Catalog.money(L.debt), Catalog.money(sim.fleet_book_value(c.id)), Catalog.money(c.property_book)]
		var parts: Array = []
		var keys: Array = L.totals.keys()
		keys.sort_custom(func(a, b): return absf(L.totals[a]) > absf(L.totals[b]))
		for k in keys:
			if absf(L.totals[k]) >= 1.0:
				parts.append("%s %s" % [Ledger.LABELS.get(k, k), _k(L.totals[k])])
		txt += "   [color=#aaa]" + " · ".join(parts) + "[/color]\n"
	finance_rt.text = txt


func _update_ai() -> void:
	var txt := ""
	for c in sim.companies:
		var ctl: AgentController = session.controllers[c.id]
		var cfg := ctl.config
		txt += "[color=#%s][b]%s[/b][/color] – %s\n" % [c.color.lightened(0.3).to_html(false), c.player_name,
			"DEMO (simulierte Antworten, keine KI)" if ctl.is_demo() else "%s @ %s" % [cfg.get("model"), cfg.get("base_url")]]
		txt += "Status: %s%s\n" % [ctl.status, "  [color=#ffb347][ERSATZMODUS – regelbasiert][/color]" if ctl.fallback_active else ""]
		txt += "Anfragen %d/%d · Token %d/%d · OK %d · Fehler %d · ungültig %d · Aktionen ok %d / abgelehnt %d\n" % [
			ctl.stats.requests, int(cfg.get("max_requests", 0)), ctl.stats.tokens, int(cfg.get("max_tokens", 0)),
			ctl.stats.ok, ctl.stats.errors, ctl.stats.invalid, ctl.stats.actions_ok, ctl.stats.actions_rejected]
		if ctl.last_error != "":
			txt += "[color=#ff6b5e]Letzter Fehler: %s[/color]\n" % _esc(ctl.last_error)
		for s in ctl.summaries.slice(-4):
			txt += "  [color=#777]%s[/color] %s%s\n" % [Catalog.game_time_short(s.t),
				"[color=#ffb347][Ersatz][/color] " if s.source == "Ersatzmodus" else "", _esc(s.text)]
		txt += "\n"
	ai_rt.text = txt


## Text ersetzen, ohne die Bildlaufposition zu verlieren (Zuschauer liest gerade).
func _update_scroll(rt: RichTextLabel, text: String) -> void:
	if rt.text == text:
		return
	var pos := rt.get_v_scroll_bar().value
	rt.text = text
	rt.get_v_scroll_bar().value = pos


## Entscheidungsprotokoll: neueste zuerst; Herkunft farbig; Folgen werden aus dem aktuellen Zustand berechnet.
func _update_decisions() -> void:
	var flt: String = DECISION_FILTERS[decision_filter.selected][1]
	var cols := {"api": "#7fc8ff", "plan": "#b48cff", "fallback": "#ffb347", "foreman": "#9fd8ff", "auto": "#999999", "spectator": "#f2c14e", "world": "#8fd0c0"}
	var txt := ""
	var n := 0
	for i in range(sim.decisions.entries.size() - 1, -1, -1):
		var e: Dictionary = sim.decisions.entries[i]
		if decision_company >= 0 and e.company != decision_company:
			continue
		if flt == "abgelehnt" and e.pruefung != "abgelehnt":
			continue
		if flt != "" and flt != "abgelehnt" and e.herkunft != flt:
			continue
		var who: String = sim.company(e.company).player_name if e.company >= 0 else ("Stadt" if e.herkunft == "world" else "Zuschauer")
		txt += "[color=#777]%s %s[/color] [b]%s[/b] [color=%s][%s][/color] " % [e.id, Catalog.game_time_short(e.t), who,
			cols.get(e.herkunft, "#ccc"), DecisionLog.ORIGIN_TEXT.get(e.herkunft, e.herkunft)]
		if str(e.aktion) != "":
			txt += "%s → [color=%s]%s[/color]: %s\n" % [_esc(e.aktion), "#6fd08c" if e.pruefung == "ok" else "#ff6b5e", e.pruefung, _esc(e.ergebnis)]
		else:
			txt += _esc(e.ergebnis) + "\n"
		if e.ziel != "" or e.begruendung != "":
			txt += "   [color=#c9c4b4]Ziel: %s · Begründung: „%s“[/color]\n" % [_esc(e.ziel), _esc(e.begruendung)]
		if not e.wahrgenommen.is_empty():
			txt += "   [color=#888]Anlass: %s[/color]\n" % _esc("; ".join(e.wahrgenommen))
		var folgen := sim.decisions.consequences(e)
		if folgen != "":
			txt += "   [color=#8fe0a0]Folgen: %s[/color]\n" % _esc(folgen)
		n += 1
		if n >= 60:
			break
	decisions_rt.text = txt if txt != "" else "[color=#999]Noch keine Einträge.[/color]"


## Personal je Firma: Rolle, Status, Aufgabe mit Fortschritt, Erschoepfung; offene Aufgaben; verlorene Arbeiter.
func _update_staff() -> void:
	var P: Personnel = sim.personnel
	var txt := "[color=#999]Arbeitsmarkt: %d verfügbar · Fahrzeugangebote: %d · Hierarchie: Unternehmer → Vorarbeiter → Arbeiter[/color]\n\n" % [
		P.available().size(), sim.resources.available_offers().size()]
	for c in sim.companies:
		var col := c.color.lightened(0.3).to_html(false)
		txt += "[color=#%s][b]%s[/b][/color]  Lohnsumme %.0f €/h · Treibstoff %d l · Ersatzteile %d\n" % [col, c.company_name,
			P.wages_per_hour(c.id), int(c.fuel), c.parts]
		for w in P.employed(c.id):
			var t: WorkerTask = P.tasks.get(w.task_id)
			var task := ""
			if t and not t.is_final():
				task = " · %s %s (%s, %d %%)" % [t.id, t.describe(), t.status, int(t.progress * 100)]
			elif w.vehicle_id >= 0:
				task = " · fährt #%d" % w.vehicle_id
			var role := "[color=#f2c14e]VA[/color] " if w.role == "foreman" else ""
			txt += "  %s%s (%s) %s · %s · Erschöpfung %d %%%s%s\n" % [role, w.name, w.id, w.skill_text(), w.status_text(sim),
				int(w.fatigue), task, (" · betreut %d" % w.supervised.size()) if w.role == "foreman" else ""]
		for t in P.tasks.values():
			if t.company == c.id and t.worker_id == "" and not t.is_final():
				txt += "  [color=#ffb347]%s %s wartet auf Verteilung (%s)[/color]\n" % [t.id, t.kind, t.report]
		for w in P.workers.values():
			if w.lost and t_belongs(w, c):
				txt += "  [color=#ff6b5e]verloren: %s[/color]\n" % w.name
		txt += "\n"
	staff_rt.text = txt


func t_belongs(w: Worker, c: Company) -> bool:
	for e in c.key_events:
		if str(e).contains(w.name) and str(e).contains("Personalverlust"):
			return true
	return false


func _update_selection() -> void:
	var sel: Dictionary = session.entity_view.selected
	follow_btn.set_pressed_no_signal(session.following)
	if sel.is_empty():
		sel_title.text = "Auswahl: Linksklick auf Figur, Fahrzeug oder Gebäude · Rechts-/Mitteltaste ziehen = Kamera · Mausrad = Zoom"
		sel_text.text = ""
		return
	match sel.kind:
		"vehicle":
			var v: FleetVehicle = sim.vehicles.get(sel.id)
			if v == null:
				session.entity_view.selected = {}
				return
			var c := sim.company(v.owner)
			sel_title.text = "%s – %s" % [v.display_name(), c.company_name]
			var d: Worker = sim.driver_of(v)
			var k: Contract = sim.contracts.get(v.contract_id)
			sel_text.text = "Status: %s · Zustand %d%% · Fahrer: %s · Kilometer: %d Tiles · Buchwert %s\n" % [
				FleetVehicle.STATE_TEXT.get(v.state, v.state), int(v.condition), d.name if d else "keiner",
				v.odometer, Catalog.money(v.book_value)]
			if k:
				sel_text.text += "Auftrag %s: %d× %s von %s nach %s · %s · Frist %s\n" % [k.id, k.qty, Catalog.CARGO[k.cargo].name,
					sim.city.building(k.pickup).name, sim.city.building(k.dropoff).name, Catalog.money(k.reward),
					Catalog.game_minutes_to_text(k.deadline)]
			if not v.load.is_empty():
				sel_text.text += "Ladung: %s · " % ", ".join(v.load.keys().map(func(kid): return "%d×%s" % [v.load[kid], kid]))
			if not v.stops.is_empty():
				sel_text.text += "Stopps: %s" % ", ".join(v.stops.map(func(st): return "%s %d×%s@%s" % [st.art, st.menge, st.contract_id, st.ort]))
		"avatar":
			var c := sim.company(sel.id)
			var a: Avatar = sim.avatars[sel.id]
			var ctl: AgentController = session.controllers[sel.id]
			sel_title.text = "%s (%s) – %s" % [c.player_name, Catalog.PERSONALITIES[c.personality].name, c.company_name]
			var doing: String = {"idle": "steht", "walking": "unterwegs", "wander": "schlendert", "talking": "im Gespräch"}.get(a.state, a.state)
			if a.pending.has("action"):
				doing += " → " + str(a.pending.action.get("action"))
			sel_text.text = "Figur: %s · Viertel: %s\nLetzte Entscheidung: %s" % [doing,
				Catalog.DISTRICTS[sim.city.district_of(a.tile())],
				ctl.summaries[-1].text if not ctl.summaries.is_empty() else "–"]
		"worker":
			var w: Worker = sim.personnel.workers.get(sel.id)
			if w == null or w.lost:
				session.entity_view.selected = {}
				return
			sel_title.text = "%s %s (%s) – %s" % ["Vorarbeiter" if w.role == "foreman" else "Arbeiter", w.name, w.id,
				sim.company(w.employer).company_name if w.employer >= 0 else "verfügbar"]
			var t: WorkerTask = sim.personnel.tasks.get(w.task_id)
			var task := "keine"
			if t:
				task = "%s %s – %s, Fortschritt %d %% (%s)" % [t.id, t.describe(), t.status, int(t.progress * 100), t.report]
			sel_text.text = "Fähigkeiten: %s · Lohn %.0f €/h · Erfahrung %d · Zuverlässigkeit %d %% · Loyalität %d · Erschöpfung %d %%\nStatus: %s · Aufgabe: %s%s" % [
				w.skill_text(), w.wage, int(w.experience), int(w.reliability * 100), int(w.loyalty), int(w.fatigue),
				w.status_text(sim), task, ("\nBetreut: %s · Bereich %d Tiles · Befugnisse %s" % [", ".join(w.supervised), int(w.control_radius()), str(w.orders)]) if w.role == "foreman" else ""]
		"person":
			var pr: Dictionary = sim.residents.people.get(sel.id, {})
			if pr.is_empty():
				session.entity_view.selected = {}
				return
			sel_title.text = "%s – %s" % [pr.name, pr.role]
			sel_text.text = sim.residents.describe(pr)
		"building":
			var b: Dictionary = sim.city.building(sel.id)
			sel_title.text = "%s (%s)" % [b.name, Catalog.DISTRICTS[b.district]]
			var txt := ""
			for pr in sim.residents.of_building(sel.id).slice(0, 1):
				txt += "Kontakt: %s (%s)%s
" % [pr.name, pr.role, (" – " + str(pr.last_concern)) if pr.state == "wartet" else ""]
			if not b["in"].is_empty():
				txt += "Empfängt: %s\n" % ", ".join(b["in"].map(func(x): return Catalog.CARGO[x].name))
			if not b.out.is_empty():
				txt += "Versendet: %s\n" % ", ".join(b.out.map(func(x): return Catalog.CARGO[x].name))
			var loyal := sim.loyal_company(sel.id)
			if loyal >= 0:
				txt += "Stammkunde von %s\n" % sim.company(loyal).company_name
			if b.role == "depot_site":
				var o: int = sim.depot_owner.get(sel.id, -1)
				txt += "Depotstandort (ID %d): %s" % [sel.id, sim.company(o).company_name if o >= 0 else "frei – mietbar"]
			elif b.role in ["dealer", "workshop", "bank"]:
				txt += {"dealer": "Autohaus: Fahrzeugkauf vor Ort", "workshop": "Werkstatt: Reparaturen", "bank": "Bank: Kredite"}[b.role]
			sel_text.text = txt
