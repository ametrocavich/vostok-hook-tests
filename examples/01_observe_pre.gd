extends Node

## Example 01: Observe a method with a pre-hook.
##
## Pre-hooks run BEFORE the original method. This one fires every time
## the player interacts with a door, before the door starts opening.
##
## Console: "[ex01] door interact"

var _lib: Object = null

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex01] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	_lib.hook("door-interact-pre", _on_door_interact)

func _on_door_interact() -> void:
	print("[ex01] door interact")
