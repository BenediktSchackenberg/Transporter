class_name ActivityLayer
extends Node2D
## Kartenebene "KI-Aktivitaet": zeigt die Eintraege des ActivityFeed als pulsierende Markierung am Zielort, eine Linie von der
## Unternehmerfigur zum Ziel (solange die Entscheidung frisch ist) und ein Schild mit Wer/Was. Sabotage und Angriffe rot und
## groesser. Reine Darstellung; Ein-/Ausschalten ueber `enabled` (HUD-Schaltflaeche, Taste K).

const LINE_MIN := 60.0              # Spielminuten mit Verbindungslinie
const LABELS_MAX := 8               # so viele neueste Eintraege tragen ein Schild
const ACTOR_COLORS := {"buergermeister": Color("#f2c14e"), "disponent": Color("#5ad1e6"), "stadt": Color("#9ad06a")}

var sim: Simulation
var cv: CityView
var enabled := true
var zoom := 1.0
var _t := 0.0
var _font: Font


func setup(simulation: Simulation, city_view: CityView) -> void:
	sim = simulation
	cv = city_view
	z_index = 70
	_font = ThemeDB.fallback_font


func update_view(delta: float, z: float) -> void:
	_t += delta
	zoom = maxf(0.05, z)
	visible = enabled
	if enabled:
		queue_redraw()


static func cell_screen(x: int, y: int) -> Vector2:
	return Iso.to_screen(Vector2((x + 0.5) * 32.0, (y + 0.5) * 32.0))


func color_of(e: Dictionary) -> Color:
	if ACTOR_COLORS.has(str(e.actor)):
		return ACTOR_COLORS[str(e.actor)]
	var c = sim.company(int(e.company))
	return c.color if c != null else Color.WHITE


func _draw() -> void:
	if sim == null or sim.activity == null:
		return
	var now: float = sim.game_min
	var items: Array = sim.activity.active(now)
	var inv := 1.0 / zoom
	var n := items.size()
	for i in n:
		var e: Dictionary = items[i]
		var age := now - float(e.t)
		var fade := clampf(1.0 - age / ActivityFeed.KEEP_MIN, 0.25, 1.0)
		var hostile: bool = str(e.kind) in ["sabotage", "angriff"]
		var col := Color("#ff4d4d") if hostile else color_of(e)
		var p := cell_screen(int(e.x), int(e.y))
		var pulse := 1.0 + 0.18 * sin(_t * 5.0 + float(e.id))
		var r := (46.0 if hostile else 32.0) * pulse * clampf(inv, 1.0, 3.0)
		# Verbindungslinie von der Unternehmerfigur zum Ziel
		if age < LINE_MIN and str(e.actor).begins_with("C") and int(e.company) >= 0 and int(e.company) < sim.avatars.size():
			var from: Vector2 = Iso.to_screen(sim.avatars[int(e.company)].pos) + Vector2(0, -40)
			draw_line(from, p, Color(col, 0.55 * fade), 3.0 * clampf(inv, 1.0, 3.0), true)
		draw_arc(p, r + 3.0 * clampf(inv, 1.0, 3.0), 0.0, TAU, 40, Color(0, 0, 0, 0.6 * fade), 3.0 * clampf(inv, 1.0, 3.0), true)   # dunkler Rand: auch auf hellem Grund sichtbar
		draw_arc(p, r, 0.0, TAU, 40, Color(col.lightened(0.25), fade), 5.0 * clampf(inv, 1.0, 3.0), true)
		draw_circle(p, r * 0.4, Color(col, 0.7 * fade))
		var icon_name: String = ActivityFeed.KINDS.get(str(e.kind), ActivityFeed.KINDS.sonstiges).icon
		var tex: Texture2D = cv.tex(icon_name) if cv != null else null
		if tex != null:
			var s := Vector2(28, 28) * clampf(inv, 0.8, 3.0)
			draw_texture_rect(tex, Rect2(p - s * 0.5 - Vector2(0, r + s.y * 0.6), s), false, Color(1, 1, 1, fade))
		# Schild nur fuer die neuesten Eintraege (sonst wird die Karte unlesbar)
		if i >= n - LABELS_MAX and _font != null:
			var fs := int(clampf(15.0 * inv, 16.0, 44.0))
			var label: String = str(e.text)
			var size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var at := p + Vector2(-size.x * 0.5, r + fs * 1.4)
			draw_rect(Rect2(at - Vector2(8, fs * 1.05), size + Vector2(16, fs * 0.6)), Color(0.02, 0.02, 0.04, 0.88 * fade))
			draw_rect(Rect2(at - Vector2(8, fs * 1.05), Vector2(5, size.y + fs * 0.6)), Color(col, fade))   # Farbstreifen: wer
			draw_string_outline(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, fs / 4), Color(0, 0, 0, fade))
			draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.98, 0.9, fade))
