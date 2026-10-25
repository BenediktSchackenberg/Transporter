class_name SetupMenu
extends Control
## Einrichtung der Partie: 2–4 KI-Spieler mit eigenem API-Zugang, Modell, Persoenlichkeit und Budgets.
## Nicht-geheime Einstellungen werden in user://setup.json gemerkt. API-Keys nur auf ausdruecklichen
## Wunsch im Windows-Tresor (Anmeldeinformationsverwaltung), nie in Dateien.

signal start_requested(cfg: Dictionary)
signal load_requested(path: String)

const SETUP_PATH := "user://setup.json"
const EXAMPLE_PATH := "res://config/example_config.json"
const DURATIONS := [5, 15, 30, 60, 120, 240, 720, 1440, 0]   # aktive Echtzeitminuten, 0 = Endlosmodus
const PROVIDERS := ["demo", "openai", "ionos"]
const DEFAULT_NAMES := [["Greta", "Greta Logistik"], ["Viktor", "Vitesse Transporte"], ["Amira", "Amira Express"],
	["Bodo", "Bodo & Söhne"]]

var rows: Array = []        # pro Spieler: Dictionary mit Controls
var seed_edit: LineEdit
var duration_opt: OptionButton
var speed_opt: OptionButton
var fault_spin: SpinBox
var carry_check: CheckBox
var weather_opt: OptionButton
const WEATHER_MODES := ["live", "sim", "replay"]
var status_label: Label


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	scroll.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var title := UITheme.label("PIXEL TRANSPORT RIVALS", 32, UITheme.ACCENT)
	root.add_child(title)
	root.add_child(UITheme.label("Partie einrichten – bis zu vier autonome KI-Unternehmer bauen Speditionen auf. Du schaust zu.", 16, UITheme.MUTED))
	# Globale Einstellungen
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 12)
	root.add_child(g)
	g.add_child(UITheme.label("Seed:"))
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size.x = 110
	seed_edit.text = str(randi() % 100000)
	g.add_child(seed_edit)
	g.add_child(UITheme.label("Partiedauer (aktive Echtzeit):"))
	duration_opt = OptionButton.new()
	for d in DURATIONS:
		duration_opt.add_item("Endlos (bis zum Beenden)" if d == 0 else ("%d Stunden" % (d / 60) if d >= 240 else "%d Minuten" % d))
	duration_opt.select(2)
	g.add_child(duration_opt)
	g.add_child(UITheme.label("Startgeschwindigkeit:"))
	speed_opt = OptionButton.new()
	for s in GameSession.SPEEDS:
		speed_opt.add_item("%dx" % s)
	speed_opt.select(1)
	g.add_child(speed_opt)
	g.add_child(UITheme.label("Demo-Fehlerquote:"))
	fault_spin = SpinBox.new()
	fault_spin.min_value = 0
	fault_spin.max_value = 0.5
	fault_spin.step = 0.05
	fault_spin.value = 0.1
	fault_spin.tooltip_text = "Nur DEMO-Adapter: Anteil simulierter Fehler (ungültiges JSON, Rate Limit, Timeout)."
	g.add_child(fault_spin)
	g.add_child(UITheme.label("Wetter:"))
	weather_opt = OptionButton.new()
	for t in ["Live: Mainz (Open-Meteo, Modelldaten)", "Simuliertes Ersatzwetter (offline)", "Wiederholung des Wetters der letzten Partie"]:
		weather_opt.add_item(t)
	weather_opt.tooltip_text = "Live: echtes Wetter für Mainz, alle Spieler sehen denselben Stand. Wiederholung: spielt den aufgezeichneten Verlauf der letzten Partie ab (Vergleichspartien)."
	g.add_child(weather_opt)
	carry_check = CheckBox.new()
	carry_check.text = "Erfahrungen der vorigen Partie übernehmen (alle Spieler)"
	carry_check.tooltip_text = "Gespeicherte Erfahrungen je Spieler-Platz werden als Vermutungen übernommen. Für Vergleiche: für alle gleich."
	g.add_child(carry_check)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	for i in 4:
		grid.add_child(_player_panel(i))
	var hint := UITheme.label("Anbieter „OpenAI-kompatibel“: echte Modell-API (z. B. https://api.openai.com/v1, https://openrouter.ai/api/v1, http://localhost:11434/v1 für Ollama). " +
		"„IONOS · Qwen“: IONOS AI Model Hub mit Herstellerparametern (Token im Feld API-Key). „DEMO (simuliert)“: keine KI, regelbasierte Testantworten – deutlich gekennzeichnet.", 12, UITheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	root.add_child(buttons)
	var start := Button.new()
	start.text = "  Partie starten  "
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_on_start)
	buttons.add_child(start)
	var load_btn := Button.new()
	load_btn.text = "Spielstand laden"
	load_btn.pressed.connect(func(): load_requested.emit(GameSession.SAVE_PATH))
	load_btn.disabled = not FileAccess.file_exists(GameSession.SAVE_PATH)
	buttons.add_child(load_btn)
	var example := Button.new()
	example.text = "Beispielkonfiguration laden"
	example.pressed.connect(func(): _apply_config(_read_json(EXAMPLE_PATH)))
	buttons.add_child(example)
	var quit := Button.new()
	quit.text = "Beenden"
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)
	status_label = UITheme.label("", 16, UITheme.WARN)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)
	var saved := _read_json(SETUP_PATH)
	if not saved.is_empty():
		_apply_config(saved)


func _player_panel(i: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	panel.add_child(v)
	var r := {}
	var head := HBoxContainer.new()
	v.add_child(head)
	r.enabled = CheckBox.new()
	r.enabled.text = "Spieler %d aktiv" % (i + 1)
	r.enabled.button_pressed = i < 4
	head.add_child(r.enabled)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.color = Catalog.COMPANY_COLORS[i]
	head.add_child(swatch)
	r.swatch = swatch
	var form := GridContainer.new()
	form.columns = 4
	form.add_theme_constant_override("h_separation", 8)
	v.add_child(form)
	r.name = _field(form, "Name", DEFAULT_NAMES[i][0])
	r.company = _field(form, "Firma", DEFAULT_NAMES[i][1])
	r.color = _option(form, "Farbe", Catalog.COLOR_NAMES, i)
	r.color.item_selected.connect(func(idx): swatch.color = Catalog.COMPANY_COLORS[idx])
	var avatars: Array = []
	for k in Catalog.AVATAR_COUNT:
		avatars.append("Figur %d" % (k + 1))
	r.avatar = _option(form, "Avatar", avatars, i)
	var pnames: Array = Catalog.PERSONALITIES.values().map(func(p): return p.name)
	r.personality = _option(form, "Persönlichkeit", pnames, i % pnames.size())
	r.form = _option(form, "Rechtsform", CompanyForms.FORMS.values().map(func(f): return f.name), 0)
	r.provider = _option(form, "Anbieter", ["DEMO (simuliert)", "OpenAI-kompatibel", "IONOS · Qwen"], 0)
	r.base_url = _field(form, "API-Basis-URL", "https://api.openai.com/v1")
	r.model = _field(form, "Modell", "gpt-4o-mini")
	r.provider.item_selected.connect(func(idx):
		if idx == 2:   # IONOS-Profil: Adresse und Modell vorbelegen
			r.base_url.text = OpenAIAdapter.IONOS_BASE_URL
			r.model.text = OpenAIAdapter.IONOS_MODEL)
	r.api_key = _field(form, "API-Key", "")
	r.api_key.secret = true
	r.api_key.placeholder_text = "wird nie gespeichert"
	r.save_key = CheckBox.new()
	r.save_key.text = "Key im Win-Tresor"
	r.save_key.tooltip_text = "API-Key in der Windows-Anmeldeinformationsverwaltung speichern (sonst nur für diese Sitzung im Speicher)."
	form.add_child(UITheme.label(""))
	form.add_child(r.save_key)
	r.interval = _spin(form, "Entscheidung alle (s)", 5, 300, 20)
	r.max_requests = _spin(form, "Max. Anfragen", 1, 5000, 300)
	r.max_tokens = _spin(form, "Tokenbudget", 1000, 10000000, 400000)
	r.max_tokens.step = 1000
	r.tokens_per_request = _spin(form, "Max. Token/Antwort", 200, 8000, 900)
	r.fallback = CheckBox.new()
	r.fallback.text = "Ersatzmodus"
	r.fallback.tooltip_text = "Bei API-Ausfall regelbasiert weiterspielen (sichtbar als ERSATZMODUS markiert)."
	r.fallback.button_pressed = true
	form.add_child(UITheme.label(""))
	form.add_child(r.fallback)
	r.strategy = _field(form, "Strategie-Zusatz", "")
	r.strategy.placeholder_text = "optional, z. B. „Fokus auf Kühltransporte“"
	rows.append(r)
	return panel


func _field(form: GridContainer, label: String, value: String) -> LineEdit:
	form.add_child(UITheme.label(label + ":", 12, UITheme.MUTED))
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size.x = 120
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(e)
	return e


func _option(form: GridContainer, label: String, items: Array, selected: int) -> OptionButton:
	form.add_child(UITheme.label(label + ":", 12, UITheme.MUTED))
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(selected)
	o.clip_text = true
	o.fit_to_longest_item = false
	o.custom_minimum_size.x = 120
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(o)
	return o


func _spin(form: GridContainer, label: String, lo: float, hi: float, value: float) -> SpinBox:
	form.add_child(UITheme.label(label + ":", 12, UITheme.MUTED))
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(s)
	return s


func collect() -> Dictionary:
	var players: Array = []
	for i in 4:
		var r: Dictionary = rows[i]
		if not r.enabled.button_pressed:
			continue
		players.append({"slot": i, "player_name": r.name.text.strip_edges(), "company_name": r.company.text.strip_edges(),
			"color_idx": r.color.selected, "avatar_style": r.avatar.selected,
			"personality": Catalog.PERSONALITIES.keys()[r.personality.selected], "form": CompanyForms.FORMS.keys()[r.form.selected],
			"provider": PROVIDERS[r.provider.selected], "base_url": r.base_url.text.strip_edges(),
			"model": r.model.text.strip_edges(), "api_key": r.api_key.text.strip_edges(),
			"save_key": r.save_key.button_pressed, "interval": r.interval.value, "max_requests": int(r.max_requests.value),
			"max_tokens": int(r.max_tokens.value), "max_tokens_per_request": int(r.tokens_per_request.value),
			"fallback": r.fallback.button_pressed, "strategy": r.strategy.text.strip_edges(), "timeout": 45.0})
	return {"seed": seed_edit.text.to_int(), "duration_min": DURATIONS[duration_opt.selected],
		"speed_idx": speed_opt.selected, "demo_fault_rate": fault_spin.value, "carry_memory": carry_check.button_pressed,
		"weather": WEATHER_MODES[weather_opt.selected], "weather_replay": "user://last_weather.json" if weather_opt.selected == 2 else "",
		"players": players}


func _apply_config(cfg: Dictionary) -> void:
	if cfg.is_empty():
		status_label.text = "Konfiguration nicht gefunden."
		return
	seed_edit.text = str(int(cfg.get("seed", 1234)))
	var di := DURATIONS.find(int(cfg.get("duration_min", 30)))
	duration_opt.select(maxi(0, di))
	speed_opt.select(int(cfg.get("speed_idx", 1)))
	fault_spin.value = float(cfg.get("demo_fault_rate", 0.1))
	weather_opt.select(maxi(0, WEATHER_MODES.find(str(cfg.get("weather", "live")))))
	for r in rows:
		r.enabled.button_pressed = false
	for p in cfg.get("players", []):
		var r: Dictionary = rows[int(p.get("slot", 0))]
		r.enabled.button_pressed = true
		r.name.text = p.get("player_name", "")
		r.company.text = p.get("company_name", "")
		r.color.select(int(p.get("color_idx", 0)))
		r.swatch.color = Catalog.COMPANY_COLORS[int(p.get("color_idx", 0))]
		r.avatar.select(int(p.get("avatar_style", 0)))
		r.personality.select(maxi(0, Catalog.PERSONALITIES.keys().find(p.get("personality", ""))))
		r.form.select(maxi(0, CompanyForms.FORMS.keys().find(p.get("form", "einzel"))))
		r.provider.select(maxi(0, PROVIDERS.find(p.get("provider", "demo"))))
		r.base_url.text = p.get("base_url", "")
		r.model.text = p.get("model", "")
		r.save_key.button_pressed = p.get("save_key", false)
		r.interval.value = float(p.get("interval", 20))
		r.max_requests.value = float(p.get("max_requests", 300))
		r.max_tokens.value = float(p.get("max_tokens", 400000))
		r.tokens_per_request.value = float(p.get("max_tokens_per_request", 900))
		r.fallback.button_pressed = p.get("fallback", true)
		r.strategy.text = p.get("strategy", "")
	status_label.text = "Konfiguration geladen."


func _on_start() -> void:
	var cfg := collect()
	var err := validate(cfg)
	if err != "":
		status_label.text = err
		return
	# Keys: aus dem Tresor holen bzw. auf Wunsch dort speichern
	for p in cfg.players:
		if p.provider == "demo":
			continue
		var slot := "slot%d" % p.slot
		if p.api_key == "" and p.save_key:
			p.api_key = CredentialStore.read_key(slot)
		elif p.api_key != "" and p.save_key:
			if not CredentialStore.save_key(slot, p.api_key):
				status_label.text = "Hinweis: Key für %s konnte nicht im Windows-Tresor gespeichert werden." % p.player_name
		elif not p.save_key:
			CredentialStore.delete_key(slot)
	_save_setup(cfg)
	start_requested.emit(cfg)


static func validate(cfg: Dictionary) -> String:
	if cfg.players.size() < 2:
		return "Mindestens zwei Spieler müssen aktiv sein."
	if cfg.players.size() > 4:
		return "Höchstens vier Spieler."
	var colors := {}
	for p in cfg.players:
		if p.player_name == "" or p.company_name == "":
			return "Jeder Spieler braucht einen Namen und einen Firmennamen."
		if colors.has(p.color_idx):
			return "Jede Firma braucht eine eigene Farbe."
		colors[p.color_idx] = true
		if p.provider != "demo" and (p.base_url == "" or p.model == ""):
			return "%s: Für die echte API sind Basis-URL und Modell nötig." % p.player_name
	if int(cfg.duration_min) not in DURATIONS:
		return "Ungültige Partiedauer."
	return ""


func _save_setup(cfg: Dictionary) -> void:
	var copy := cfg.duplicate(true)
	for p in copy.players:
		p.erase("api_key")
	var f := FileAccess.open(SETUP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(copy, "  "))


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
