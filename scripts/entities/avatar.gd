class_name Avatar
extends Mover
## Sichtbare Unternehmerfigur eines KI-Spielers.
## Besuchspflichtige Aktionen (Fahrzeugkauf, Depotanmietung, Sabotage vor Ort, Kooperationsangebot)
## werden als pending gespeichert und beim Eintreffen erneut geprueft und ausgefuehrt.

var owner: int
var state := "idle"          # idle | walking | talking
var pending := {}            # aktueller Besuch: {"action": Dictionary, "follow": int, "place": String, "cell": Vector2i}
var queue: Array = []        # weitere Besuche, werden nacheinander abgearbeitet
var visited := {}            # Ortsname -> Spielminute des letzten Besuchs
var talk_timer := 0.0
var talk_with := -1
var wander_timer := 0.0
var bubble := ""             # aktuelle Sprechblase
var bubble_private := false
var bubble_timer := 0.0


func _init() -> void:
	lane = 0.0
	speed = 2.4


func say(text: String, private: bool) -> void:
	bubble = text
	bubble_private = private
	bubble_timer = 6.0
