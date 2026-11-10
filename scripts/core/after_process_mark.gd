extends Node
## Absturzspur: setzt nach allen anderen _process die Marke fuer Layout und _draw (process_priority sehr hoch, main.gd).


func _process(_delta: float) -> void:
	ProcTimer.mark("nach _process (Layout, _draw)", -1)
	ProcTimer.sub("-")
