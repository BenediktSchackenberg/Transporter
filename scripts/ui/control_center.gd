class_name ControlCenter
extends Control
## Leitstelle (UI-Neugestaltung): einklappbares Seitenfenster ueber der Karte mit sechs Hauptbereichen -
## KI-Zentrale, Welt & Ereignisse, Unternehmen, Staedte, Wirtschaft & Finanzen, Einstellungen & Technik.
## Liest nur vorhandene Spielsysteme (EventCenter, DecisionLog, FinanceHistory, CivicWorks, Ledger, ...); keine eigene Simulation.
## Lange Texte in gut lesbarer Systemschrift, Ueberschriften in Pixelschrift; Farben: gruen ok, gelb Warnung, rot kritisch, blau Info,
## violett KI - immer mit Symbol bzw. Statuswort. Die alte Oberflaeche bleibt als Expertenmodus erreichbar.

const AREAS := [
	{"key": "ki", "label": "KI-Zentrale", "icon": "◆"},
	{"key": "welt", "label": "Welt & Ereignisse", "icon": "✦"},
	{"key": "firmen", "label": "Unternehmen", "icon": "▣"},
	{"key": "staedte", "label": "Städte", "icon": "▲"},
	{"key": "dienste", "label": "Öffentliche Dienste & Regionalpolitik", "icon": "✚"},
	{"key": "finanzen", "label": "Wirtschaft & Finanzen", "icon": "€"},
	{"key": "technik", "label": "Einstellungen & Technik", "icon": "⚙"},
]
const C_OK := Color("#6fd08c")
const C_WARN := Color("#ffb347")
const C_BAD := Color("#ff6b5e")
const C_INFO := Color("#7fc8ff")
const C_AI := Color("#b48cff")
const C_TEXT := Color("#ece8dc")
const C_MUTED := Color("#a9a7b6")
const C_BG := Color("#171822")
const C_CARD := Color("#232533")
const PERIODS := [[1, "Heute"], [7, "7 Tage"], [30, "30 Tage"], [0, "Gesamt"]]

var session: GameSession
var sim: Simulation
var area := "ki"
var expanded := true
var body_font: Font
var root_panel: PanelContainer
var nav_box: VBoxContainer
var nav_btns := {}
var content: VBoxContainer
var scroll: ScrollContainer
var title_lbl: Label
var search: LineEdit
var modal: PanelContainer
var modal_body: VBoxContainer
var modal_title: Label
var _refresh := 0.0
var _sig := ""
var period := 7
var ev_filter := {"cat": "", "min_sev": 1, "town": -1, "company": -1, "days": 0}
var ev_page := 1
var welt_tab := "ereignisse"
var ui_scale := 1.0
var markers_on := true
var expert := false
var markers: MapMarkers


func build(s: GameSession) -> void:
	session = s
	sim = s.sim
	body_font = ThemeDB.fallback_font
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_top = 58
	offset_bottom = -6
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_panel = PanelContainer.new()
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_panel.add_theme_stylebox_override("panel", _box(C_BG, Color("#0b0c12"), 2, 6))
	add_child(root_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	root_panel.add_child(row)
	nav_box = VBoxContainer.new()
	nav_box.custom_minimum_size = Vector2(104, 0)
	nav_box.add_theme_constant_override("separation", 6)
	row.add_child(nav_box)
	var tog := _btn("⟩ Karte", func(): set_expanded(not expanded))
	tog.tooltip_text = "Leitstelle ein-/ausklappen (F1)"
	nav_box.add_child(tog)
	for a in AREAS:
		var b := Button.new()
		b.text = "%s\n%s" % [a.icon, a.label]
		b.custom_minimum_size = Vector2(100, 64)
		b.add_theme_font_override("font", body_font)
		b.add_theme_font_size_override("font_size", 13)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.toggle_mode = true
		b.pressed.connect(func(): open_area(a.key))
		nav_box.add_child(b)
		nav_btns[a.key] = b
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	row.add_child(main)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	main.add_child(head)
	title_lbl = _h(" KI-Zentrale", 24, UITheme.ACCENT)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_lbl)
	search = LineEdit.new()
	search.placeholder_text = "Suche: Greta, A899, Flughafen, Marktplatz …"
	search.custom_minimum_size = Vector2(300, 34)
	search.add_theme_font_override("font", body_font)
	search.add_theme_font_size_override("font_size", 15)
	search.text_submitted.connect(func(t): _search(t))
	head.add_child(search)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	_build_modal()
	_load_settings()
	markers = MapMarkers.new()
	markers.sim = sim
	session.city_view.fx_node.add_child(markers)
	markers.visible = markers_on
	_apply_width()
	open_area("ki")


func _apply_width() -> void:
	var vw := get_viewport_rect().size.x if is_inside_tree() else 1920.0
	var w := clampf(vw * 0.5, 760.0, 1100.0) if expanded else 112.0
	offset_left = -w - 6
	offset_right = -6
	scroll.get_parent().visible = expanded
	if session != null and session.hud != null and session.hud.sel_panel != null:
		session.hud.sel_panel.offset_right = -w - 16 if not expert else -450.0   # Auswahlfenster nicht unter der Leitstelle


var _modal_open := false


func set_expanded(on: bool) -> void:
	if not on:
		_modal_open = modal.visible   # Detailfenster merken und beim Aufklappen wieder zeigen
		modal.visible = false
	expanded = on
	_apply_width()
	if on:
		_rebuild()
		modal.visible = _modal_open


func toggle() -> void:
	set_expanded(not expanded)


func open_area(key: String) -> void:
	area = key
	for k in nav_btns:
		nav_btns[k].button_pressed = k == key
	for a in AREAS:
		if a.key == key:
			title_lbl.text = " %s %s" % [a.icon, a.label]
	if not expanded:
		set_expanded(true)
	modal.visible = false
	_sig = ""
	_rebuild()


func _process(delta: float) -> void:
	if not visible or not expanded or sim == null:
		return
	_refresh += delta
	if _refresh < 1.5:
		return
	_refresh = 0.0
	var sig := _signature()
	if sig != _sig:
		_rebuild()


## Neuaufbau nur, wenn sich die Datenlage der sichtbaren Ansicht geaendert hat (nicht jedes Bild).
func _signature() -> String:
	match area:
		"ki":
			return "%d|%d|%d" % [sim.center.order.size(), sim.decisions.next_id, int(sim.game_min / 20.0)]
		"welt":
			return "%d|%s|%d|%s|%d" % [sim.center.order.size(), str(ev_filter), ev_page, welt_tab, sim.social.messages.size()]
		_:
			return "%s|%d" % [area, int(sim.game_min / 30.0)]


func _rebuild() -> void:
	_sig = _signature()
	for ch in content.get_children():
		ch.queue_free()
	match area:
		"ki": _view_ki()
		"welt": _view_welt()
		"firmen": _view_firmen()
		"staedte": _view_staedte()
		"dienste": _view_dienste()
		"finanzen": _view_finanzen()
		"technik": _view_technik()


# ------------------------------------------------------------------ Bausteine
static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _h(text: String, size: int, col: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _t(text: String, size: int = 15, col: Color = C_TEXT, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _btn(text: String, cb: Callable, small: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", body_font)
	b.add_theme_font_size_override("font_size", 13 if small else 14)
	b.pressed.connect(cb)
	return b


## Karte mit farbigem Rand links (Bedeutung) und Inhalt (VBox).
func _card(parent: Control, accent: Color) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := _box(C_CARD, accent.darkened(0.2), 0, 6)
	sb.border_width_left = 5
	sb.border_color = accent
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v


func _kpi(grid: Control, title: String, value: String, sub: String, trend: int, col: Color) -> void:
	var v := _card(grid, col)
	v.custom_minimum_size = Vector2(150, 92)
	v.add_child(_t(title, 13, C_MUTED))
	var val := _h(value, 24, col)
	val.clip_text = true
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	val.custom_minimum_size = Vector2(60, 0)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(val)
	var arrow := "▲ steigt" if trend > 0 else ("▼ sinkt" if trend < 0 else "▶ gleich")
	v.add_child(_t(arrow + ("  ·  " + sub if sub != "" else ""), 13, C_MUTED))
	(v.get_child(v.get_child_count() - 1) as Label).add_theme_color_override("font_color", C_OK if trend > 0 else (C_BAD if trend < 0 else C_MUTED))


func _section(text: String) -> void:
	var l := _h(text, 19, UITheme.ACCENT)
	content.add_child(l)


func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	parent.add_child(r)
	return r


func _sev_color(sev: int, cat: String) -> Color:
	if cat == "kritisch" or sev >= 3:
		return C_BAD
	if cat == "ki":
		return C_AI
	if cat == "stadt":
		return C_INFO
	if cat == "wirtschaft":
		return C_OK
	return C_MUTED


func _when(t: float) -> String:
	return Catalog.game_time_short(t)


# ------------------------------------------------------------------ 1. KI-Zentrale
func _view_ki() -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	var ais := session.controllers.filter(func(c): return sim.company(c.cid) != null and sim.company(c.cid).is_active())
	var api := ais.filter(func(c): return not c.fallback_active and c.config.get("provider", "demo") != "demo").size()
	_kpi(grid, "Aktive KI-Unternehmen", str(ais.size()), "%d mit KI-Modell, %d im Ersatzmodus" % [api, ais.size() - api], 0, C_AI)
	var staff := 0
	for c in sim.companies:
		staff += sim.personnel.employed(c.id).size()
	_kpi(grid, "Mitarbeiter der Firmen", str(staff), "", FinanceHistory.trend(sim.finance.world_series("beschaeftigt")), C_INFO)
	var moving := 0
	for v in sim.vehicles.values():
		if v.contract_id != "" or not v.stops.is_empty():
			moving += 1
	_kpi(grid, "Fahrzeuge im Einsatz", "%d / %d" % [moving, sim.vehicles.size()], "", 0, C_INFO)
	var ks: Array = sim.contracts.values().filter(func(k): return k.owner >= 0 and k.status in ["accepted", "assigned", "loading", "in_transit"])
	var underway := ks.filter(func(k): return k.status in ["loading", "in_transit"]).size()
	var waiting := ks.filter(func(k): return k.status == "accepted").size()
	var risk := ks.filter(func(k): return k.deadline - sim.game_min < 60.0 and k.status != "in_transit").size()
	_kpi(grid, "Transportaufträge", "%d aktiv" % ks.size(), "%d unterwegs, %d warten auf Fahrzeug%s" % [underway, waiting, (", ⚠ %d gefährdet" % risk) if risk > 0 else ""], 0, C_WARN if risk > 0 else C_OK)
	var open_b := 0
	if sim.civic != null:
		open_b = sim.civic.anlagen.values().filter(func(a): return a.status in ["geplant", "material", "im_bau"]).size()
	var builds := sim.construction.projects.values().filter(func(p): return p.status in ["im_bau", "erschliessung"]).size()
	_kpi(grid, "Offene Bauprojekte", str(open_b + builds), "%d Anlagen der Bürgermeister, %d Bauvorhaben" % [open_b, builds], 0, C_INFO)
	var today := sim.center.query({"min_sev": 2, "days": 1}, 999).size()
	var crit := sim.center.query({"cat": "kritisch", "days": 1}, 999).size()
	_kpi(grid, "Bedeutende Ereignisse heute", str(today), ("⚠ %d kritisch" % crit) if crit > 0 else "keine kritischen", 0, C_BAD if crit > 0 else C_OK)
	var profit := 0.0
	for c in sim.companies:
		profit += float(sim.finance.company_period(c.id, 7).get("ergebnis", 0.0))
	_kpi(grid, "Ergebnis aller Firmen (7 Tage)", Catalog.money(profit), "Summe aus Umsatz minus Kosten", 1 if profit > 0 else -1, C_OK if profit >= 0 else C_BAD)
	var busy := ais.filter(func(c): return str(c.status).contains("wartet")).size()
	_kpi(grid, "KI denkt gerade nach", str(busy), "%d Anfragen, %d Fehler" % [_sum_ai("requests"), _sum_ai("errors")], 0, C_AI)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	content.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(_h("Was passiert gerade?", 19, UITheme.ACCENT))
	for e in sim.center.query({"min_sev": 1}, 14):
		_event_card(left, e)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	right.add_child(_h("KI-Spieler", 19, UITheme.ACCENT))
	for ctl in session.controllers:
		_ai_card(right, ctl)


func _sum_ai(k: String) -> int:
	var n := 0
	for c in session.controllers:
		n += int(c.stats.get(k, 0))
	return n


func _event_card(parent: Control, e: Dictionary) -> void:
	var col := _sev_color(int(e.sev), str(e.cat))
	var v := _card(parent, col)
	var top := _row(v)
	var cat: Dictionary = EventCenter.CATS.get(str(e.cat), EventCenter.CATS.normal)
	top.add_child(_t("%s %s · %s" % [cat.icon, cat.label, EventCenter.SEV_LABEL[clampi(int(e.sev), 0, 3)]], 13, col, false))
	var who := ""
	if int(e.company) >= 0 and sim.company(int(e.company)) != null:
		who = sim.company(int(e.company)).company_name
	elif int(e.town) >= 0 and sim.towns != null:
		who = sim.towns.name_of(int(e.town))
	top.add_child(_t("%s%s" % [who, ("  ·  %s" % _when(float(e.t_last)))], 13, C_MUTED))
	v.add_child(_t(str(e.title), 16, C_TEXT))
	if int(e.n) > 1:
		v.add_child(_t("%d gleichartige Meldungen zusammengefasst – zuletzt: %s" % [int(e.n), str(e.text).left(160)], 14, C_MUTED))
	elif str(e.text) != str(e.title):
		v.add_child(_t(str(e.text).left(240), 14, C_MUTED))
	if str(e.status) != "":
		v.add_child(_t("Status: %s" % e.status, 13, C_OK if str(e.status) == "ausgeführt" else (C_BAD if str(e.status) == "abgelehnt" else C_MUTED)))
	var acts := _row(v)
	if not (e.cell as Array).is_empty():
		acts.add_child(_btn("⌖ Auf Karte zeigen", func(): jump_event(e), true))
	if str(e.decision) != "":
		acts.add_child(_btn("? Warum", func(): show_decision(str(e.decision)), true))
	if int(e.company) >= 0:
		acts.add_child(_btn("▣ Unternehmen", func(): show_company(int(e.company)), true))
	if str(e.anlage) != "":
		acts.add_child(_btn("▲ Stadt", func(): show_town(int(e.town)), true))


func _ai_card(parent: Control, ctl: AgentController) -> void:
	var c: Company = sim.company(ctl.cid)
	if c == null:
		return
	var st := _ai_status(ctl)
	var v := _card(parent, st[1])
	var top := _row(v)
	top.add_child(_h("%s" % c.player_name, 18, c.color.lightened(0.25)))
	top.add_child(_t(c.company_name, 14, C_MUTED))
	v.add_child(_t("Status: %s %s" % [st[2], st[0]], 14, st[1]))
	v.add_child(_t("Ziel: %s" % (ctl.goal if ctl.goal != "" else "noch keines genannt"), 14))
	v.add_child(_t("Gerade: %s" % LiveText.figure_text(sim, c.id).left(120), 14, C_MUTED))
	var last := _last_decision(c.id)
	if not last.is_empty():
		v.add_child(_t("Letzte Entscheidung: %s" % DecisionText.headline(sim, last), 14, C_AI))
	var fin := sim.finance.company_period(c.id, 7)
	var res := float(fin.get("ergebnis", 0.0))
	v.add_child(_t("Finanzen (7 Tage): %s %s · Bargeld %s" % ["▲ Gewinn" if res >= 0 else "▼ Verlust", Catalog.money(res), Catalog.money(c.ledger.cash)], 14, C_OK if res >= 0 else C_BAD))
	var prob := _last_problem(c.id)
	if prob != "":
		v.add_child(_t("Problem: %s" % prob, 14, C_WARN))
	var acts := _row(v)
	acts.add_child(_btn("Details", func(): show_company(c.id), true))
	if not last.is_empty():
		acts.add_child(_btn("? Warum", func(): show_decision(str(last.id)), true))


## [Statuswort, Farbe, Symbol]: plant (Modell denkt), aktiv, Ersatzmodus, braucht Hilfe (Fehlerserie, Geld knapp).
func _ai_status(ctl: AgentController) -> Array:
	var c: Company = sim.company(ctl.cid)
	if c.ledger.cash < 0.0 or int(ctl.stats.get("errors", 0)) > int(ctl.stats.get("ok", 0)) + 3:
		return ["braucht Hilfe", C_BAD, "⚠"]
	if ctl.fallback_active or ctl.config.get("provider", "demo") == "demo":
		return ["arbeitet im regelbasierten Ersatzmodus", C_WARN, "◇"]
	if str(ctl.status).contains("wartet"):
		return ["plant (KI-Modell denkt nach)", C_AI, "◆"]
	return ["aktiv", C_OK, "●"]


func _last_decision(cid: int) -> Dictionary:
	for i in range(sim.decisions.entries.size() - 1, -1, -1):
		var d: Dictionary = sim.decisions.entries[i]
		if int(d.company) == cid and str(d.herkunft) in ["api", "plan", "fallback"] and DecisionText.action_of(d) not in ["wait", "collect_contracts"]:
			return d
	return {}


func _last_problem(cid: int) -> String:
	for i in range(sim.decisions.entries.size() - 1, maxi(-1, sim.decisions.entries.size() - 60), -1):
		var d: Dictionary = sim.decisions.entries[i]
		if int(d.company) == cid and str(d.pruefung) != "ok":
			var rj := DecisionText.reject_info(str(d.ergebnis))
			return rj.title if not rj.is_empty() else str(d.ergebnis).left(90)
	return ""


# ------------------------------------------------------------------ 2. Welt & Ereignisse
func _view_welt() -> void:
	var tabs := _row(content)
	for t in [["ereignisse", "Ereignisse"], ["gespraeche", "Gespräche der KI"]]:
		var b := _btn(t[1], func(): welt_tab = t[0]; _rebuild())
		b.toggle_mode = true
		b.button_pressed = welt_tab == t[0]
		tabs.add_child(b)
	if welt_tab == "gespraeche":
		_view_gespraeche()
		return
	var f := _row(content)
	_opt(f, "Kategorie", [["", "alle"], ["kritisch", "kritisch"], ["wirtschaft", "Wirtschaft"], ["ki", "KI-Entscheidungen"], ["stadt", "Stadtentwicklung"], ["normal", "Aktivitäten"]], "cat")
	_opt(f, "Priorität", [[0, "alle"], [1, "ab normal"], [2, "wichtig"], [3, "kritisch"]], "min_sev")
	var towns_opts: Array = [[-1, "alle Städte"]]
	if sim.towns != null:
		for k in sim.towns.count():
			towns_opts.append([k, sim.towns.name_of(k)])
	_opt(f, "Stadt", towns_opts, "town")
	var f2 := _row(content)
	var comp_opts: Array = [[-1, "alle Unternehmen"]]
	for c in sim.companies:
		comp_opts.append([c.id, c.company_name])
	_opt(f2, "Unternehmen", comp_opts, "company")
	_opt(f2, "Zeitraum", [[0, "gesamt"], [1, "heute"], [7, "7 Tage"], [30, "30 Tage"]], "days")
	var flt := ev_filter.duplicate()
	if search.text.strip_edges() != "":
		flt["text"] = search.text.strip_edges()
	var list := sim.center.query(flt, 40 * ev_page)
	content.add_child(_t("%d Ereignisse angezeigt (neueste zuerst; gleichartige Meldungen sind zusammengefasst)" % list.size(), 13, C_MUTED))
	for e in list:
		_event_card(content, e)
	if list.size() >= 40 * ev_page:
		content.add_child(_btn("Ältere Ereignisse laden", func(): ev_page += 1; _rebuild()))


func _opt(parent: Control, label: String, opts: Array, key: String) -> void:
	parent.add_child(_t(label + ":", 13, C_MUTED, false))
	var o := OptionButton.new()
	o.add_theme_font_override("font", body_font)
	o.add_theme_font_size_override("font_size", 14)
	for i in opts.size():
		o.add_item(str(opts[i][1]), i)
		if str(opts[i][0]) == str(ev_filter.get(key, "")):
			o.select(i)
	o.item_selected.connect(func(i): ev_filter[key] = opts[i][0]; ev_page = 1; _rebuild())
	parent.add_child(o)


## Gespraeche zwischen KI-Spielern: je Paar und Thema eine Karte, wiederholte Nachrichten zusammengefasst, Angebote hervorgehoben.
func _view_gespraeche() -> void:
	var convs := {}
	for m in sim.social.messages:
		var a := int(m.from)
		var b := int(m.to)
		var key := ("%d|alle" % a) if b < 0 else "%d|%d" % [mini(a, b), maxi(a, b)]
		if not convs.has(key):
			convs[key] = {"msgs": [], "a": a, "b": b, "t": 0.0}
		convs[key].msgs.append(m)
		convs[key].t = float(m.t)
	var keys := convs.keys()
	keys.sort_custom(func(x, y): return float(convs[x].t) > float(convs[y].t))
	if keys.is_empty():
		content.add_child(_t("Noch keine Gespräche zwischen den Unternehmern.", 15, C_MUTED))
	for key in keys.slice(0, 20):
		var cv: Dictionary = convs[key]
		var ca: Company = sim.company(int(cv.a))
		var cb: Company = sim.company(int(cv.b)) if int(cv.b) >= 0 else null
		var v := _card(content, C_AI)
		v.add_child(_h("%s ↔ %s" % [_who(ca), _who(cb) if cb else "alle"], 17, C_TEXT))
		var text_all := ""
		for m in cv.msgs:
			text_all += str(m.text).to_lower() + " "
		var topic := "Transportauftrag" if text_all.contains("auftrag") or text_all.contains("fracht") else ("Kooperation" if text_all.contains("kooperation") else ("Preis" if text_all.contains("preis") or text_all.contains("eur") else "Allgemein"))
		var offers := sim.social.offers.values().filter(func(o): return (int(o.get("from", -2)) == int(cv.a) and int(o.get("to", -2)) == int(cv.b)) or (int(o.get("from", -2)) == int(cv.b) and int(o.get("to", -2)) == int(cv.a)))
		var outcome := "keine Angebote"
		if not offers.is_empty():
			var stt := str(offers[-1].get("status", "open"))
			outcome = "letztes Angebot: %s" % {"open": "offen", "accepted": "angenommen ✔", "rejected": "abgelehnt ✖", "countered": "Gegenangebot",
				"invalid": "ungültig geworden", "expired": "abgelaufen", "done": "erledigt ✔"}.get(stt, stt)
		v.add_child(_t("Thema: %s · %d Nachrichten · %s · zuletzt %s" % [topic, cv.msgs.size(), outcome, _when(float(cv.t))], 14, C_MUTED))
		var shown := 0
		var last_text := ""
		var repeat := 0
		for m in cv.msgs.slice(-12):
			if str(m.text) == last_text:
				repeat += 1
				continue
			if repeat > 0:
				v.add_child(_t("   (%d× wiederholt)" % repeat, 13, C_MUTED))
				repeat = 0
			last_text = str(m.text)
			var from: Company = sim.company(int(m.from))
			var is_offer := str(m.text).to_lower().contains("angebot") or str(m.text).contains("EUR")
			v.add_child(_t("%s  %s: %s" % [_when(float(m.t)), from.player_name if from else "?", str(m.text).left(220)], 14, C_WARN if is_offer else C_TEXT))
			shown += 1
		if repeat > 0:
			v.add_child(_t("   (%d× wiederholt)" % repeat, 13, C_MUTED))


# ------------------------------------------------------------------ 3. Unternehmen
func _view_firmen() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for c in sim.companies:
		var fin := sim.finance.company_period(c.id, 7)
		var res := float(fin.get("ergebnis", 0.0))
		var v := _card(grid, c.color)
		v.custom_minimum_size = Vector2(360, 0)
		v.add_child(_h(c.company_name, 18, c.color.lightened(0.3)))
		var ctl := _ctl(c.id)
		v.add_child(_t("Geschäftsführung: %s%s" % [c.player_name, " (KI-Spieler)" if ctl != null else " (Modellfirma)"], 14, C_MUTED))
		var biz := sim.biz.of(c.id).size()
		v.add_child(_t("Bereich: %s · %d Mitarbeiter · %d Fahrzeuge%s" % ["Transport" + (" + %d Betriebe" % biz if biz > 0 else ""), sim.personnel.employed(c.id).size(), sim.company_vehicles(c.id).size(),
			"" if c.status in ["aktiv", "active", ""] else " · Status: %s" % c.status], 14))
		v.add_child(_t("Aktuell: %s" % LiveText.figure_text(sim, c.id).left(100), 14, C_MUTED))
		v.add_child(_t("%s (7 Tage): %s · Bargeld %s" % ["▲ Gewinnphase" if res >= 0 else "▼ Verlustphase", Catalog.money(res), Catalog.money(c.ledger.cash)], 14, C_OK if res >= 0 else C_BAD))
		v.add_child(_btn("Unternehmen öffnen", func(): show_company(c.id), true))


func _who(c: Company) -> String:
	return "%s (%s)" % [c.company_name, c.player_name] if c != null else "?"


func _ctl(cid: int) -> AgentController:
	for c in session.controllers:
		if c.cid == cid:
			return c
	return null


# ------------------------------------------------------------------ 4. Staedte
func _view_staedte() -> void:
	if sim.towns == null:
		return
	for k in sim.towns.count():
		var M: Mayor = sim.towns.mayor(k)
		var col := Color(str(sim.civic.profiles[k].color)) if sim.civic != null and sim.civic.profiles.has(k) else C_INFO
		var v := _card(content, col)
		var top := _row(v)
		top.add_child(_h(sim.towns.name_of(k), 20, col.lightened(0.2)))
		top.add_child(_t("Bürgermeister %s%s" % [M.name, (" · " + CivicWorks.PERSONAS[sim.civic.profiles[k].persona].label) if sim.civic != null and sim.civic.profiles.has(k) else ""], 14, C_MUTED))
		var pop := sim.citizens.population_of(k)
		var ts := sim.finance.town_series(k, "einwohner")
		v.add_child(_t("Einwohner %d %s · Zufriedenheit/Zustimmung %.0f %% · Arbeitslos %d · Kasse %s (verfügbar %s)" % [pop, ["▼", "▶", "▲"][FinanceHistory.trend(ts) + 1],
			M.approval, sim.citizens.unemployed_of(k), Catalog.money(M.cash()), Catalog.money(M.available_budget())], 14))
		if sim.civic != null and sim.civic.profiles.has(k):
			v.add_child(_t("Ziel: %s" % sim.civic.profiles[k].vision, 14, C_AI))
			for a in sim.civic.anlagen.values().filter(func(a): return int(a.town) == k and a.status in ["geplant", "material", "im_bau"]):
				v.add_child(_t("▲ %s – %s" % [a.title, _anlage_status(a)], 14, C_INFO))
		var acts := _row(v)
		acts.add_child(_btn("Stadt öffnen", func(): show_town(k), true))
		acts.add_child(_btn("⌖ Auf Karte", func(): _jump_cell(sim.city.building(int(sim.towns.get_t(k).town_hall)).road), true))


## Oeffentliche Dienste und Regionalpolitik (Auftrag 20): je Stadt Einrichtungen mit Personal und Fahrzeugen, Kennzahlen der Dienste,
## Bedarf mit naechster Massnahme, geplante Neubauten und letzte Entscheidungen; dazu Kreiskrankenhaus und Regionalrat.
func _view_dienste() -> void:
	if sim.municipal == null or not sim.municipal.enabled():
		content.add_child(_t("Kommunale Dienste gibt es nur in der Region.", 15, C_MUTED))
		return
	var M: Municipal = sim.municipal
	var rv := _card(content, C_INFO)
	rv.add_child(_h("Region", 20, C_INFO))
	for f in sim.rescue.hospitals():
		rv.add_child(_t("✚ %s (%s): %d/%d Betten belegt%s" % [f.name, sim.towns.name_of(int(f.town)), sim.rescue.occupied(f), sim.rescue.beds(f),
			" · Zweckverband" if f.has("shares") else ""], 15))
	var cs: Dictionary = sim.council.summary() if sim.council.enabled() else {}
	if not cs.is_empty():
		rv.add_child(_t("Regionalrat: nächste Sitzung Tag %d%s" % [int(cs.naechste_sitzung_tag), (" · läuft: " + str(cs.laufend)) if str(cs.laufend) != "" else ""], 15))
		var last: Dictionary = cs.letzte
		for x in last.get("antraege", []):
			var col := C_OK if x.result == "beschlossen" else C_BAD
			rv.add_child(_t("%s %s (%s): %s · Stimmen %s" % ["✔" if x.result == "beschlossen" else "✖", str(x.kind), x.von, x.text, str(x.votes)], 14, col))
	for k in sim.towns.count():
		var v := _card(content, C_INFO)
		v.add_child(_h(sim.towns.name_of(k), 20, C_INFO.lightened(0.2)))
		for f in M.of_town(k):
			var r := _row(v)
			var need := 0
			for b in f.staff_need:
				need += int(f.staff_need[b])
			r.add_child(_t("%s %s · %s · Personal %d/%d%s · %s" % ["●" if f.status == "in_betrieb" else "○", f.name, Municipal.STYLES[f.style], M.staff_count(f.id), need,
				(" + %d ehrenamtlich" % M.volunteers_of(f.id).size()) if not M.volunteers_of(f.id).is_empty() else "",
				", ".join(f.vehicles.map(func(vid): return "%s (%s)" % [M.vehicles[vid].type, M.vehicles[vid].status]))], 14))
			var cell := Vector2i(int(f.cell[0]), int(f.cell[1]))
			r.add_child(_btn("⌖", func(): _jump_cell(cell), true))
			if FireService.is_station(f) and f.status == "in_betrieb":   # Etappe 13: Dienstplan, Funktionen, Lehrgaenge, Erschoepfung
				var crew: Array = M.staff_of(f.id) + M.volunteers_of(f.id)
				var fn := {}
				for p in M.staff_of(f.id):
					fn[str(p.get("funktion", "Feuerwehrmann/-frau"))] = int(fn.get(str(p.get("funktion", "Feuerwehrmann/-frau")), 0)) + 1
				var tired := crew.filter(func(p): return float(p.get("erschoepfung", 0.0)) >= FireService.TIRED).size()
				v.add_child(_t("    im Dienst %d · einsatzbereit %d · Lehrgang %d/%d · erschöpft %d · %s" % [sim.fire._pros_on_duty(f), sim.fire._crew_free(f),
					crew.filter(func(p): return bool(p.get("lehrgang", false))).size(), crew.size(), tired,
					", ".join(fn.keys().map(func(x): return "%d %s" % [int(fn[x]), x]))], 13))
		for e in sim.fire.active().filter(func(e): return int(e.town) == k):   # laufende Einsaetze, anklickbar zur Einsatzstelle
			var r := _row(v)
			r.add_child(_t("🚒 %s: %s (%s) · %s · %s" % [e.kind, e.name, e.cause, e.phase,
				", ".join(e.vehicles.map(func(vid): return str(M.vehicles[vid].label) if M.vehicles.has(vid) else vid)) if not e.vehicles.is_empty() else "keine Wache frei"], 14, C_WARN))
			var ecell := Vector2i(int(e.cell[0]), int(e.cell[1]))
			r.add_child(_btn("⌖", func(): _jump_cell(ecell), true))
		var rs: Dictionary = sim.rescue.summary(k)
		var es: Dictionary = sim.education.summary(k)
		var ws: Dictionary = sim.winter.summary(k)
		var fs: Dictionary = sim.fire.summary(k)
		v.add_child(_t("Rettung: %d Notfälle, Hilfsfrist Ø %.1f min (%d %% ≤ 15 min) · Feuerwehr: %d Einsätze aktiv · Schnee: %d Abschnitte (Rettungswege %d) · Schlaglöcher %d" % [
			int(rs.notfaelle), float(rs.mittlere_hilfsfrist_min), roundi(float(rs.hilfsfrist_eingehalten_anteil) * 100.0), fs.aktiv.size(),
			int(ws.verschneit), int(ws.rettungswege_verschneit), int(ws.schlagloecher)], 14))
		v.add_child(_t("Bildung: Kita %d/%d Plätze, Schule %d/%d Plätze, Lehrkräfte %d %%" % [int(es.kinder_kita), int(es.kitaplaetze), int(es.kinder_schule), int(es.schulplaetze),
			roundi(float(es.lehrkraefte_quote) * 100.0)], 14))
		for l in sim.transit.summary(k):
			v.add_child(_t("Bus %s: %d Fahrgäste, Takt %d min, Kostendeckung %d %%, Anbindung %d %%" % [l.linie, int(l.fahrgaeste), int(l.takt_min),
				roundi(float(l.kostendeckung) * 100.0), roundi(float(l.anbindung) * 100.0)], 14))
		for n in sim.services.needs(k).slice(0, 3):
			v.add_child(_t("⚠ Bedarf: %s – nächster Schritt: %s" % [n.grund, {"bauen": "Neubau " + str(n.get("typ", "")), "fahrzeug": "Fahrzeug " + str(n.get("fahrzeug", "")),
				"schliessen": "Schließung"}.get(n.massnahme, n.massnahme)], 14, C_WARN))
		for b in sim.services.builds.values().filter(func(b): return int(b.town) == k):
			v.add_child(_t("▲ Neubau %s im Bau (%s)" % [Municipal.TYPES[b.code].label, b.reason], 14, C_INFO))
		for e in sim.services.log.filter(func(e): return int(e.town) == k).slice(-3):
			v.add_child(_t("Tag %d · %s: %s" % [int(e.day), e.by, e.text], 13, C_AI))


func _anlage_status(a: Dictionary) -> String:
	match str(a.status):
		"geplant":
			return "geplant, Besuch im Großlager folgt"
		"material":
			return "Materialien werden beschafft; nächster Schritt: Bauauftrag nach der Rückkehr"
		"im_bau":
			return "im Bau (%d %%)" % int(float(a.get("progress", 0.0)) * 100.0)
		"eroeffnet":
			return "eröffnet am Tag %d" % int(a.opened)
		"abgelehnt":
			return "vom Rat abgelehnt"
	return str(a.status)


# ------------------------------------------------------------------ 5. Wirtschaft & Finanzen
func _view_finanzen() -> void:
	var pr := _row(content)
	pr.add_child(_t("Zeitraum:", 14, C_MUTED, false))
	for p in PERIODS:
		var b := _btn(str(p[1]), func(): period = int(p[0]); _rebuild())
		b.toggle_mode = true
		b.button_pressed = period == int(p[0])
		pr.add_child(b)
	_section("Unternehmen im Vergleich (%s)" % sim.finance.company_period(sim.companies[0].id, period).get("zeitraum", ""))
	var g := GridContainer.new()
	g.columns = 9
	g.add_theme_constant_override("h_separation", 14)
	content.add_child(g)
	for h in ["Unternehmen", "Umsatz", "Kosten", "Ergebnis", "Bargeld", "Schulden", "Vermögen", "Personal", "Fahrz."]:
		g.add_child(_t(h, 13, C_MUTED, false))
	var rows := sim.companies.duplicate()
	rows.sort_custom(func(a, b): return float(sim.finance.company_period(a.id, period).ergebnis) > float(sim.finance.company_period(b.id, period).ergebnis))
	for c in rows:
		var f := sim.finance.company_period(c.id, period)
		var nb := _btn(c.company_name, func(): show_company(c.id), true)
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		g.add_child(nb)
		for key in ["umsatz", "kosten", "ergebnis", "bargeld", "schulden", "vermoegen"]:
			var val := float(f.get(key, 0.0))
			g.add_child(_t(Catalog.money(val), 14, (C_OK if val >= 0 else C_BAD) if key in ["ergebnis", "bargeld", "vermoegen"] else C_TEXT, false))
		g.add_child(_t(str(sim.personnel.employed(c.id).size()), 14, C_TEXT, false))
		g.add_child(_t(str(sim.company_vehicles(c.id).size()), 14, C_TEXT, false))
	content.add_child(_t("Umsatz = Erlöse (Transport, Verkäufe, Geschäfte); Kosten = alle Aufwände inkl. Abschreibung; Ergebnis = Umsatz − Kosten. Bargeld = Liquidität; Vermögen = Bargeld + Buchwerte − Schulden. Kreditauszahlungen und Tilgungen sind weder Umsatz noch Kosten.", 13, C_MUTED))
	_section("Gesamtwirtschaft der Region")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	_kpi(grid, "Einwohner", str(sim.citizens.population()), "", FinanceHistory.trend(sim.finance.world_series("einwohner")), C_INFO)
	_kpi(grid, "Beschäftigt", str(sim.citizens.employed_total()), "Arbeitslos %d" % sim.citizens.unemployed_total(), FinanceHistory.trend(sim.finance.world_series("beschaeftigt")), C_OK)
	var fs := sim.finance.world_series("firmen")
	_kpi(grid, "Unternehmen", str(sim.companies.filter(func(c): return c.status not in ["geschlossen", "verwertung"]).size()), "Insolvent/geschlossen %d · Betriebe %d" % [sim.companies.filter(func(c): return c.status in ["insolvenz", "verwertung", "geschlossen"]).size(), sim.biz.items.size()], FinanceHistory.trend(fs), C_INFO)
	var lf := sim.finance.world_series("lieferungen")
	_kpi(grid, "Lieferungen gesamt", str(int(lf[-1][1]) if not lf.is_empty() else 0), "Transportvolumen", FinanceHistory.trend(lf), C_OK)
	if sim.hub != null and sim.hub.enabled:
		_kpi(grid, "Großlager-Umsatz", Catalog.money(float(sim.hub.stats.umsatz)), "Importe %s" % Catalog.money(float(sim.hub.stats.import)), 0, C_INFO)
	var inv := 0.0
	if sim.towns != null:
		for k in sim.towns.count():
			for prj in sim.towns.mayor(k).projects.values():
				if str(prj.status) == "fertig":
					inv += float(prj.cost)
	_kpi(grid, "Öffentliche Investitionen", Catalog.money(inv), "abgeschlossene Projekte aller Städte", 0, C_INFO)
	var ch := LineChart.new()
	ch.custom_minimum_size = Vector2(0, 210)
	ch.title = "Einwohner und Beschäftigte je Spieltag"
	ch.money = false
	ch.series = [{"name": "Einwohner", "color": C_INFO, "points": sim.finance.world_series("einwohner")}, {"name": "Beschäftigt", "color": C_OK, "points": sim.finance.world_series("beschaeftigt")}]
	content.add_child(ch)
	if sim.towns != null and sim.towns.count() > 1:
		_section("Die Städte im Vergleich")
		var tg := GridContainer.new()
		tg.columns = 7
		tg.add_theme_constant_override("h_separation", 14)
		content.add_child(tg)
		for h in ["Stadt", "Einwohner", "Zustimmung", "Arbeitslos", "Kasse", "Investiert", "Projekte"]:
			tg.add_child(_t(h, 13, C_MUTED, false))
		for k in sim.towns.count():
			var M: Mayor = sim.towns.mayor(k)
			var ts: Array = sim.finance.towns.get(k, [])
			var last: Dictionary = ts[-1] if not ts.is_empty() else {}
			var tb := _btn(sim.towns.name_of(k), func(): show_town(k), true)
			tg.add_child(tb)
			tg.add_child(_t(str(sim.citizens.population_of(k)), 14, C_TEXT, false))
			tg.add_child(_t("%.0f %%" % M.approval, 14, C_OK if M.approval >= 50 else C_WARN, false))
			tg.add_child(_t(str(sim.citizens.unemployed_of(k)), 14, C_TEXT, false))
			tg.add_child(_t(Catalog.money(M.cash()), 14, C_TEXT, false))
			tg.add_child(_t(Catalog.money(float(last.get("investiert", 0.0))), 14, C_TEXT, false))
			tg.add_child(_t(str(int(last.get("projekte_laufend", 0))), 14, C_TEXT, false))


# ------------------------------------------------------------------ 6. Einstellungen & Technik
func _view_technik() -> void:
	_section("Darstellung")
	var r := _row(content)
	r.add_child(_t("Oberflächengröße:", 15, C_TEXT, false))
	for sc in [1.0, 1.25, 1.5]:
		var b := _btn("%d %%" % int(sc * 100.0), func(): set_ui_scale(sc))
		b.toggle_mode = true
		b.button_pressed = is_equal_approx(ui_scale, sc)
		r.add_child(b)
	var r2 := _row(content)
	var mk := CheckButton.new()
	mk.text = "Ereignismarker auf der Karte"
	mk.add_theme_font_override("font", body_font)
	mk.button_pressed = markers_on
	mk.toggled.connect(func(on): markers_on = on; markers.visible = on; _save_settings())
	r2.add_child(mk)
	var ex := CheckButton.new()
	ex.text = "Expertenmodus (alte Protokollansichten mit IDs, API-Status, Rohdaten)"
	ex.add_theme_font_override("font", body_font)
	ex.button_pressed = expert
	ex.toggled.connect(func(on): set_expert(on))
	content.add_child(ex)
	_section("Spielstand")
	var r3 := _row(content)
	r3.add_child(_btn("Speichern", func(): session.save_game()))
	r3.add_child(_t("Laden und Partie beenden: oben in der Leiste.", 14, C_MUTED, false))
	_section("KI-Anbindung")
	for ctl in session.controllers:
		var c: Company = sim.company(ctl.cid)
		var st := _ai_status(ctl)
		content.add_child(_t("%s %s – %s · %s (%s) · Anfragen %d, Fehler %d, Aktionen ok %d / abgelehnt %d" % [st[2], c.player_name, st[0], str(ctl.config.get("provider", "")), str(ctl.config.get("model", "")),
			int(ctl.stats.requests), int(ctl.stats.errors), int(ctl.stats.get("actions_ok", 0)), int(ctl.stats.get("actions_rejected", 0))], 14, st[1]))
		if ctl.last_error != "":
			content.add_child(_t("    letzte Störung: %s" % ctl.last_error.left(160), 13, C_MUTED))
	content.add_child(_t("Tastatur: F1 Leitstelle ein/aus · Tab Seitenleisten · O nächste Stadt · Mausrad Zoom.", 14, C_MUTED))


func set_ui_scale(sc: float) -> void:
	ui_scale = sc
	get_window().content_scale_factor = sc
	_save_settings()
	_apply_width()
	_rebuild()


func set_expert(on: bool) -> void:
	expert = on
	if session.hud != null:
		session.hud.set_expert(on)
	_save_settings()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://ui.cfg") == OK:
		ui_scale = float(cf.get_value("ui", "scale", 1.0))
		markers_on = bool(cf.get_value("ui", "markers", true))
		expert = bool(cf.get_value("ui", "expert", false))
	if not is_equal_approx(ui_scale, 1.0):
		get_window().content_scale_factor = ui_scale


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("ui", "scale", ui_scale)
	cf.set_value("ui", "markers", markers_on)
	cf.set_value("ui", "expert", expert)
	cf.save("user://ui.cfg")


# ------------------------------------------------------------------ Detailfenster
func _build_modal() -> void:
	modal = PanelContainer.new()
	modal.add_theme_stylebox_override("panel", _box(Color("#1d1f2c"), UITheme.ACCENT, 2, 8))
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left = 112
	modal.offset_top = 46
	modal.offset_right = -8
	modal.offset_bottom = -8
	modal.visible = false
	root_panel.add_child(modal)
	var v := VBoxContainer.new()
	modal.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	modal_title = _h("", 22, UITheme.ACCENT)
	modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(modal_title)
	head.add_child(_btn("✕ Schließen", func(): modal.visible = false))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_constant_override("separation", 8)
	sc.add_child(modal_body)


func _open_modal(title: String) -> VBoxContainer:
	if not expanded:
		set_expanded(true)
	for ch in modal_body.get_children():
		ch.queue_free()
	modal_title.text = title
	modal.visible = true
	return modal_body


## "Warum?": Ziel, Begruendung, Lage, Entscheidung, Ablauf in 5 Schritten, Folgen, Risiken; technische Details aufklappbar.
func show_decision(id: String) -> void:
	var d: Dictionary = {}
	for e in sim.decisions.entries:
		if str(e.id) == id:
			d = e
	if d.is_empty():
		_open_modal("Entscheidung nicht mehr im Speicher").add_child(_t("Die Entscheidung %s ist älter als die gespeicherte Historie." % id, 15, C_MUTED))
		return
	var x := DecisionText.explain(sim, d)
	var b := _open_modal(str(x.titel))
	b.add_child(_t("%s · %s · Quelle: %s" % [x.wer, x.wann, x.herkunft], 14, C_MUTED))
	for sec in [["Was wollte die KI erreichen?", str(x.ziel) + ((" – Zweck dieser Aktion: " + str(x.zweck)) if str(x.zweck) != "" else "")],
			["Warum? (Begründung der KI, wörtlich)", x.begruendung], ["Was hat sie entschieden?", x.entscheidung]]:
		var v := _card(b, C_AI)
		v.add_child(_h(sec[0], 17, C_AI))
		v.add_child(_t(str(sec[1]), 15))
	if not (x.lage as Array).is_empty():
		var vl := _card(b, C_INFO)
		vl.add_child(_h("Lage zum Entscheidungszeitpunkt (gemessen)", 17, C_INFO))
		for f in x.lage:
			vl.add_child(_t("• " + str(f), 15))
	var va := _card(b, C_MUTED)
	va.add_child(_h("Ablauf: vorgeschlagen → geprüft → angenommen → ausgeführt → Ergebnis", 17, C_TEXT))
	for st in x.ablauf:
		var pend: bool = st.size() > 3 and bool(st[3])
		va.add_child(_t("%s %s: %s" % ["◷" if pend else ("✔" if bool(st[2]) else "✖"), st[0], str(st[1])], 15, C_WARN if pend else (C_OK if bool(st[2]) else C_BAD)))
	var vf := _card(b, C_OK)
	vf.add_child(_h("Folgen (aus dem aktuellen Spielstand)", 17, C_OK))
	vf.add_child(_t(str(x.folgen), 15))
	vf.add_child(_t("Risiken: %s" % x.risiken, 15, C_WARN))
	var tech := _btn("▸ Technische Details", func(): pass, true)
	b.add_child(tech)
	var tv := _t("Aktion: %s\nPrüfung: %s\nMeldung der Engine: %s\nVerweise: %s\nEntscheidung %s, Schlüssel %s" % [x.technik.aktion, x.technik.pruefung, x.technik.meldung, str(x.technik.verweise), x.technik.id, x.technik.schluessel], 13, C_MUTED)
	tv.visible = false
	b.add_child(tv)
	tech.pressed.connect(func(): tv.visible = not tv.visible)


## Unternehmensdetail: Ueberblick, Finanzen (Diagramme), Auftraege, Fahrzeuge, Mitarbeiter, KI-Strategie, Entscheidungen.
func show_company(cid: int, tab: String = "ueberblick") -> void:
	var c: Company = sim.company(cid)
	if c == null:
		return
	var b := _open_modal("%s – %s" % [c.company_name, c.player_name])
	var tabs := _row(b)
	for t in [["ueberblick", "Überblick"], ["finanzen", "Finanzen"], ["auftraege", "Aufträge"], ["fahrzeuge", "Fahrzeuge"], ["personal", "Mitarbeiter"], ["strategie", "KI-Strategie"], ["entscheidungen", "Entscheidungen"]]:
		var tb := _btn(t[1], func(): show_company(cid, t[0]), true)
		tb.toggle_mode = true
		tb.button_pressed = tab == t[0]
		tabs.add_child(tb)
	var f := sim.finance.company_period(cid, period)
	match tab:
		"ueberblick":
			var grid := GridContainer.new()
			grid.columns = 3
			b.add_child(grid)
			_kpi(grid, "Umsatz (%s)" % f.zeitraum, Catalog.money(float(f.umsatz)), "", 0, C_INFO)
			_kpi(grid, "Kosten (%s)" % f.zeitraum, Catalog.money(float(f.kosten)), "", 0, C_WARN)
			_kpi(grid, "Betriebsergebnis", Catalog.money(float(f.ergebnis)), "", 1 if float(f.ergebnis) >= 0 else -1, C_OK if float(f.ergebnis) >= 0 else C_BAD)
			_kpi(grid, "Kontostand", Catalog.money(float(f.bargeld)), "Liquidität", FinanceHistory.trend(sim.finance.company_series(cid, "bargeld")), C_INFO)
			_kpi(grid, "Schulden", Catalog.money(float(f.schulden)), "", 0, C_WARN if float(f.schulden) > 0 else C_OK)
			_kpi(grid, "Vermögen", Catalog.money(float(f.vermoegen)), "Bargeld + Buchwerte − Schulden", 0, C_INFO)
			b.add_child(_t("Gerade: %s" % LiveText.figure_text(sim, cid), 15))
			b.add_child(_t("Ruf %.0f · %d Mitarbeiter · %d Fahrzeuge · %d Betriebe · Stellplätze %d/%d" % [c.reputation, sim.personnel.employed(cid).size(), sim.company_vehicles(cid).size(), sim.biz.of(cid).size(), c.vehicle_ids.size(), c.fleet_limit()], 15, C_MUTED))
			if not c.depots.is_empty():
				b.add_child(_btn("⌖ Firmensitz auf der Karte", func(): _jump_cell(sim.city.building(int(c.depots[0])).road)))
		"finanzen":
			var pr := _row(b)
			for p in PERIODS:
				var pb := _btn(str(p[1]), func(): period = int(p[0]); show_company(cid, "finanzen"), true)
				pb.toggle_mode = true
				pb.button_pressed = period == int(p[0])
				pr.add_child(pb)
			b.add_child(_t("Umsatz %s · Kosten %s · Ergebnis %s (%s)" % [Catalog.money(float(f.umsatz)), Catalog.money(float(f.kosten)), Catalog.money(float(f.ergebnis)), f.zeitraum], 16))
			var ch := LineChart.new()
			ch.custom_minimum_size = Vector2(0, 220)
			ch.title = "Umsatz, Kosten und Ergebnis je Spieltag"
			ch.series = [{"name": "Umsatz", "color": C_OK, "points": sim.finance.company_series(cid, "umsatz")}, {"name": "Kosten", "color": C_BAD, "points": sim.finance.company_series(cid, "kosten")},
				{"name": "Ergebnis", "color": C_INFO, "points": sim.finance.company_series(cid, "ergebnis")}]
			b.add_child(ch)
			var ch2 := LineChart.new()
			ch2.custom_minimum_size = Vector2(0, 180)
			ch2.title = "Liquidität (Bargeld) und Schulden"
			ch2.series = [{"name": "Bargeld", "color": C_INFO, "points": sim.finance.company_series(cid, "bargeld")}, {"name": "Schulden", "color": C_WARN, "points": sim.finance.company_series(cid, "schulden")}]
			b.add_child(ch2)
			b.add_child(_h("Kostenstruktur (%s)" % f.zeitraum, 17, UITheme.ACCENT))
			var bars := BarChart.new()
			bars.items = (f.kostenstruktur as Dictionary).keys().map(func(k): return [k, float(f.kostenstruktur[k])])
			bars.custom_minimum_size = Vector2(0, 26 * maxi(1, bars.items.size()) + 10)
			b.add_child(bars)
			var ch3 := LineChart.new()
			ch3.custom_minimum_size = Vector2(0, 170)
			ch3.title = "Aufträge: geliefert, verspätet, gescheitert (kumuliert)"
			ch3.money = false
			ch3.series = [{"name": "geliefert", "color": C_OK, "points": sim.finance.company_series(cid, "geliefert")}, {"name": "verspätet", "color": C_WARN, "points": sim.finance.company_series(cid, "verspaetet")},
				{"name": "gescheitert", "color": C_BAD, "points": sim.finance.company_series(cid, "gescheitert")}]
			b.add_child(ch3)
		"auftraege":
			var ks: Array = sim.contracts.values().filter(func(k): return k.owner == cid and k.status in ["accepted", "assigned", "loading", "in_transit"])
			b.add_child(_t("%d laufende Aufträge · geliefert %d (pünktlich %d, verspätet %d), gescheitert %d" % [ks.size(), int(c.stats.completed), int(c.stats.on_time), int(c.stats.late), int(c.stats.failed)], 15))
			for k in ks:
				var late: bool = k.deadline - sim.game_min < 60.0 and k.status != "in_transit"
				var v := _card(b, C_WARN if late else C_OK)
				v.add_child(_t("%s · %s" % [k.cargo_name(), Catalog.money(k.reward)], 16))
				v.add_child(_t("%s → %s · Frist in %d Spielminuten · Status: %s%s" % [sim.city.building(k.pickup).name, sim.city.building(k.dropoff).name, int(k.deadline - sim.game_min), {"accepted": "angenommen, wartet auf Fahrzeug", "assigned": "Fahrzeug eingeplant", "loading": "wird geladen", "in_transit": "unterwegs"}.get(k.status, k.status), "  ⚠ gefährdet" if late else ""], 14, C_MUTED))
				v.add_child(_btn("⌖ Abholort zeigen", func(): _jump_cell(sim.city.building(k.pickup).road), true))
		"fahrzeuge":
			for veh in sim.company_vehicles(cid):
				var d: Worker = sim.driver_of(veh)
				var k: Contract = sim.contracts.get(veh.contract_id)
				var v := _card(b, C_INFO)
				v.add_child(_t("%s (%s)" % [Catalog.model(veh.model).name, FleetVehicle.STATE_TEXT.get(veh.state, veh.state)], 16))
				v.add_child(_t("Fahrer: %s · Zustand %d %% · Ladung %d/%d · Auftrag: %s" % [d.name if d else "keiner", int(veh.condition), sim.logistics.load_total(veh), int(veh.spec().capacity), k.cargo_name() if k else "keiner"], 14, C_MUTED))
				var vid: int = veh.id
				v.add_child(_btn("⌖ Fahrzeug auf der Karte", func(): _jump_vehicle(vid), true))
		"personal":
			for w in sim.personnel.employed(cid):
				var t: WorkerTask = sim.personnel.tasks.get(w.task_id)
				var v := _card(b, C_INFO)
				v.add_child(_t("%s – %s" % [w.name, w.status_text(sim)], 15))
				v.add_child(_t("Aufgabe: %s · Lohn %s/h · Erschöpfung %d %%" % [t.describe() if t else "keine", Catalog.money(float(w.wage)), int(float(w.get("fatigue")) if w.get("fatigue") != null else 0.0)], 14, C_MUTED))
		"strategie":
			var ctl := _ctl(cid)
			b.add_child(_t("Persönlichkeit: %s" % str(Catalog.PERSONALITIES.get(c.personality, {}).get("name", c.personality)), 15))
			if ctl != null:
				var st := _ai_status(ctl)
				b.add_child(_t("KI: %s %s · %s (%s)" % [st[2], st[0], str(ctl.config.get("provider", "")), str(ctl.config.get("model", ""))], 15, st[1]))
				b.add_child(_t("Aktuelles Ziel: %s" % (ctl.goal if ctl.goal != "" else "nicht genannt"), 15))
			var plan: Dictionary = sim.plans.current(cid)
			if not plan.is_empty():
				b.add_child(_t("Plan: %s" % str(plan.get("ziel", plan.get("goal", ""))), 15, C_AI))
			b.add_child(_t(str(sim.strategy.summary_of(cid)).left(600), 14, C_MUTED))
		"entscheidungen":
			b.add_child(_t("Zeitleiste der Entscheidungen (neueste zuerst). Ein Klick erklärt Ziel, Begründung, Ablauf und Folgen.", 14, C_MUTED))
			var n := 0
			for i in range(sim.decisions.entries.size() - 1, -1, -1):
				var d: Dictionary = sim.decisions.entries[i]
				if int(d.company) != cid or str(d.herkunft) not in ["api", "plan", "fallback"]:
					continue
				var ok := str(d.pruefung) == "ok"
				var line := _btn("Tag %d %s  %s %s" % [GameCalendar.day_of(float(d.t)), _when(float(d.t)), "✔" if ok else "✖", DecisionText.headline(sim, d)], func(): show_decision(str(d.id)), true)
				line.alignment = HORIZONTAL_ALIGNMENT_LEFT
				line.add_theme_color_override("font_color", C_OK if ok else C_BAD)
				b.add_child(line)
				n += 1
				if n >= 60:
					break


## Stadtdetail: Uebersicht, Plaene des Buergermeisters, Bauprojekte mit Material und Fortschritt, Haushalt.
func show_town(k: int) -> void:
	if sim.towns == null or k < 0 or k >= sim.towns.count():
		return
	var M: Mayor = sim.towns.mayor(k)
	var b := _open_modal("%s – Bürgermeister %s" % [sim.towns.name_of(k), M.name])
	var grid := GridContainer.new()
	grid.columns = 3
	b.add_child(grid)
	_kpi(grid, "Einwohner", str(sim.citizens.population_of(k)), "", FinanceHistory.trend(sim.finance.town_series(k, "einwohner")), C_INFO)
	_kpi(grid, "Zustimmung", "%.0f %%" % M.approval, "", FinanceHistory.trend(sim.finance.town_series(k, "zustimmung")), C_OK if M.approval >= 50 else C_WARN)
	_kpi(grid, "Arbeitslos", str(sim.citizens.unemployed_of(k)), "Beschäftigung %d %%" % int(sim.citizens.employment_rate_of(k) * 100.0), 0, C_WARN)
	_kpi(grid, "Kasse", Catalog.money(M.cash()), "verfügbar %s" % Catalog.money(M.available_budget()), FinanceHistory.trend(sim.finance.town_series(k, "kasse")), C_INFO)
	_kpi(grid, "Gebunden in Projekten", Catalog.money(M.commitments), "", 0, C_WARN)
	var ts: Array = sim.finance.towns.get(k, [])
	var inc := 0.0
	var out := 0.0
	for s in ts.slice(-7):
		inc += float(s.einnahmen)
		out += float(s.ausgaben)
	_kpi(grid, "Haushalt (7 Tage)", Catalog.money(inc - out), "Einnahmen %s · Ausgaben %s" % [Catalog.money(inc), Catalog.money(out)], 1 if inc >= out else -1, C_OK if inc >= out else C_BAD)
	var ch := LineChart.new()
	ch.custom_minimum_size = Vector2(0, 190)
	ch.title = "Stadtkasse und Investitionen je Spieltag"
	ch.series = [{"name": "Kasse", "color": C_INFO, "points": sim.finance.town_series(k, "kasse")}, {"name": "investiert (kumuliert)", "color": C_OK, "points": sim.finance.town_series(k, "investiert")}]
	b.add_child(ch)
	if sim.civic != null and sim.civic.profiles.has(k):
		var w: Dictionary = sim.civic.window(k)
		b.add_child(_h("Pläne des Bürgermeisters", 19, UITheme.ACCENT))
		b.add_child(_t("%s · Ziel: %s · %s · nächster Besuch im Großlager: Tag %d" % [w.persoenlichkeit, w.vision, w.unterwegs, int(w.naechster_besuch)], 15, C_AI))
		var D: CityDepot = sim.towns.depot(k)
		for a in sim.civic.anlagen.values().filter(func(a): return int(a.town) == k):
			var col := C_OK if a.status == "eroeffnet" else (C_BAD if a.status == "abgelehnt" else C_INFO)
			var v := _card(b, col)
			v.add_child(_h("%s" % a.title, 17, col))
			v.add_child(_t("Status: %s" % _anlage_status(a), 15))
			v.add_child(_t("Begründung: %s" % a.reason, 14, C_MUTED))
			var res: Dictionary = D.project_res.get(str(a.project), {})
			if not res.is_empty():
				var parts: Array = []
				for it in res.items:
					parts.append("%s %d/%d" % [CityGoods.get_item(it).name, int(res.reserved.get(it, 0)), int(res.items[it])])
				v.add_child(_t("Material (geliefert/benötigt): %s" % ", ".join(parts), 14, C_MUTED))
			var e: Dictionary = sim.construction.public.get(str(a.project), {})
			v.add_child(_t("Kosten %s%s%s" % [Catalog.money(float(a.cost)), (" · Baufirma %s" % sim.construction.builders[e.builder].name) if not e.is_empty() and sim.construction.builders.has(e.builder) else "",
				(" · noch etwa %d Bautage" % int(e.days_left)) if not e.is_empty() and a.status == "im_bau" else ""], 14, C_MUTED))
			if str(a.get("result", "")) != "":
				v.add_child(_t("Ergebnis: %s" % a.result, 14, C_OK))
			var cell := Vector2i(int(a.rect[0]) + int(a.rect[2]) / 2, int(a.rect[1]) + int(a.rect[3]) / 2)
			v.add_child(_btn("⌖ Bauplatz auf der Karte", func(): _jump_cell(cell), true))
	b.add_child(_h("Ereignisse dieser Stadt", 19, UITheme.ACCENT))
	for e in sim.center.query({"town": k, "min_sev": 1}, 10):
		_event_card(b, e)


# ------------------------------------------------------------------ Suche
func _search(text: String) -> void:
	var q := text.strip_edges().to_lower()
	if q == "":
		return
	var b := _open_modal("Suche: %s" % text)
	var found := 0
	for c in sim.companies:
		if c.company_name.to_lower().contains(q) or c.player_name.to_lower().contains(q):
			b.add_child(_btn("▣ Unternehmen: %s (%s)" % [c.company_name, c.player_name], func(): show_company(c.id)))
			found += 1
	if sim.towns != null:
		for k in sim.towns.count():
			if sim.towns.name_of(k).to_lower().contains(q) or sim.towns.mayor(k).name.to_lower().contains(q) or "bürgermeister".contains(q):
				b.add_child(_btn("▲ Stadt: %s (Bürgermeister %s)" % [sim.towns.name_of(k), sim.towns.mayor(k).name], func(): show_town(k)))
				found += 1
	if sim.contracts.has(text.strip_edges().to_upper()):
		var k: Contract = sim.contracts[text.strip_edges().to_upper()]
		b.add_child(_btn("✉ Auftrag %s: %s, %s → %s (%s)" % [k.id, k.cargo_name(), sim.city.building(k.pickup).name, sim.city.building(k.dropoff).name, k.status], func(): _jump_cell(sim.city.building(k.pickup).road)))
		found += 1
	for v in sim.vehicles.values():
		if ("fahrzeug".contains(q) and q.length() >= 4) or ("#%d" % v.id) == q or Catalog.model(v.model).name.to_lower().contains(q):
			var vid: int = v.id
			b.add_child(_btn("🚚 Fahrzeug #%d %s (%s)" % [v.id, Catalog.model(v.model).name, sim.company(v.owner).company_name if sim.company(v.owner) else ""], func(): _jump_vehicle(vid)))
			found += 1
			if found > 40:
				break
	var nb := 0
	for bd in sim.city.buildings:
		if str(bd.get("name", "")).to_lower().contains(q) and nb < 15:
			var cell: Vector2i = bd.road
			b.add_child(_btn("■ Gebäude: %s" % bd.name, func(): _jump_cell(cell)))
			nb += 1
			found += 1
	if sim.civic != null:
		for a in sim.civic.anlagen.values():
			if str(a.title).to_lower().contains(q):
				var c2 := Vector2i(int(a.rect[0]), int(a.rect[1]))
				b.add_child(_btn("▲ Bauprojekt: %s in %s (%s)" % [a.title, sim.towns.name_of(int(a.town)), _anlage_status(a)], func(): _jump_cell(c2)))
				found += 1
	for e in sim.center.query({"text": text.strip_edges()}, 15):
		_event_card(b, e)
		found += 1
	if found == 0:
		b.add_child(_t("Nichts gefunden.", 15, C_MUTED))


# ------------------------------------------------------------------ Kamera
## Ereignis auf der Karte zeigen: gespeicherter Ort; bewegliches Fahrzeug: damaliger Ort und Knopf fuer die aktuelle Position.
func jump_event(e: Dictionary) -> void:
	var cell := Vector2i(int(e.cell[0]), int(e.cell[1]))
	_jump_cell(cell)
	var refs: Dictionary = e.get("refs", {})
	if refs.has("vehicle_id") and sim.vehicles.has(int(refs.vehicle_id)):
		var vid := int(refs.vehicle_id)
		if sim.vehicles[vid].tile().distance_to(cell) > 3:
			session.hud.show_toast("Ereignisort gezeigt – das Fahrzeug ist inzwischen weitergefahren (Leitstelle: Fahrzeug folgen).")


func _jump_cell(cell: Vector2i) -> void:
	session.set_follow(false)
	var cam: Camera2D = session.city_view.camera
	var target := Iso.to_screen(sim.city.tile_center(cell))
	var tw := create_tween()
	tw.tween_property(cam, "position", target, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if cam.zoom.x < 0.6:
		tw.parallel().tween_property(cam, "zoom", Vector2(0.75, 0.75), 0.6)
	markers.highlight(cell)
	set_expanded(false)   # Karte frei machen; F1 oder "Leitstelle" oeffnet wieder


func _jump_vehicle(vid: int) -> void:
	if not sim.vehicles.has(vid):
		return
	_jump_cell(sim.vehicles[vid].tile())
	session.follow({"kind": "vehicle", "id": vid})


# ------------------------------------------------------------------ Diagramme
## Liniendiagramm: mehrere Reihen [[Tag, Wert], ...] mit Achsen, Legende und Beschriftung (lesbare Schrift).
class LineChart extends Control:
	var title := ""
	var series: Array = []
	var money := true

	func _draw() -> void:
		var f: Font = ThemeDB.fallback_font
		var r := Rect2(Vector2(70, 46), size - Vector2(84, 68))
		draw_rect(Rect2(Vector2.ZERO, size), Color("#1a1b26"))
		draw_string(f, Vector2(8, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ece8dc"))
		var lo := INF
		var hi := -INF
		var d0 := INF
		var d1 := -INF
		for s in series:
			for p in s.points:
				lo = minf(lo, float(p[1]))
				hi = maxf(hi, float(p[1]))
				d0 = minf(d0, float(p[0]))
				d1 = maxf(d1, float(p[0]))
		if lo == INF:
			draw_string(f, r.position + Vector2(10, 30), "Noch keine Daten (erste Werte nach dem nächsten Tageswechsel)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#a9a7b6"))
			return
		if is_equal_approx(hi, lo):
			hi = lo + 1.0
		if is_equal_approx(d1, d0):
			d1 = d0 + 1.0
		lo = minf(lo, 0.0)
		for i in 5:
			var y := r.position.y + r.size.y * float(i) / 4.0
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.07))
			var val := hi - (hi - lo) * float(i) / 4.0
			draw_string(f, Vector2(4, y + 4), Catalog.money(val) if money else str(int(round(val))), HORIZONTAL_ALIGNMENT_LEFT, 64, 11, Color("#a9a7b6"))
		if lo < 0.0 and hi > 0.0:
			var y0 := r.position.y + r.size.y * (hi / (hi - lo))
			draw_line(Vector2(r.position.x, y0), Vector2(r.end.x, y0), Color(1, 1, 1, 0.3), 1.0)
		draw_string(f, Vector2(r.position.x, r.end.y + 16), "Tag %d" % int(d0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#a9a7b6"))
		draw_string(f, Vector2(r.end.x - 50, r.end.y + 16), "Tag %d" % int(d1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#a9a7b6"))
		var lx := 8.0
		for s in series:
			var pts := PackedVector2Array()
			for p in s.points:
				pts.append(Vector2(r.position.x + r.size.x * (float(p[0]) - d0) / (d1 - d0), r.position.y + r.size.y * (hi - float(p[1])) / (hi - lo)))
			if pts.size() >= 2:
				draw_polyline(pts, s.color, 2.0, true)
			elif pts.size() == 1:
				draw_circle(pts[0], 3.0, s.color)
			draw_rect(Rect2(lx, 28, 12, 8), s.color)
			draw_string(f, Vector2(lx + 16, 37), str(s.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ece8dc"))
			lx += 22.0 + f.get_string_size(str(s.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0


## Balkendiagramm (waagerecht) fuer Kostenstrukturen: [[Name, Wert], ...]
class BarChart extends Control:
	var items: Array = []

	func _draw() -> void:
		var f: Font = ThemeDB.fallback_font
		var hi := 1.0
		for it in items:
			hi = maxf(hi, float(it[1]))
		var y := 4.0
		if items.is_empty():
			draw_string(f, Vector2(8, 18), "Keine Kosten im Zeitraum", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#a9a7b6"))
		var total := 0.0
		for it in items:
			total += float(it[1])
		for it in items:
			var w := (size.x - 330.0) * float(it[1]) / hi
			draw_string(f, Vector2(4, y + 15), str(it[0]), HORIZONTAL_ALIGNMENT_LEFT, 180, 13, Color("#ece8dc"))
			draw_rect(Rect2(186, y + 3, maxf(2.0, w), 16), Color("#ff8a6a"))
			draw_string(f, Vector2(192 + w, y + 15), "%s (%d %%)" % [Catalog.money(float(it[1])), int(100.0 * float(it[1]) / maxf(1.0, total))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ece8dc"))
			y += 26.0
