extends Node

## Example 07: Hook for a fixed number of fires, then remove itself.
##
## hook() returns an int ID. Pass that ID to unhook() to remove the
## hook later. Storing the ID in a script-level var lets the callback
## remove its own registration.
##
## Useful for one-shot effects: granted XP for the first 5 doors,
## a tutorial trigger that shouldn't fire again, etc.
##
## Console:
##   [ex07] door 1 of 3
##   [ex07] door 2 of 3
##   [ex07] door 3 of 3
##   [ex07] done, unhooking

const FIRE_LIMIT := 3

var _lib: Object = null
var _hook_id: int = -1
var _fires := 0

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex07] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	_hook_id = _lib.hook("door-interact-pre", _on_door)

func _on_door() -> void:
	_fires += 1
	print("[ex07] door %d of %d" % [_fires, FIRE_LIMIT])
	if _fires >= FIRE_LIMIT:
		_lib.unhook(_hook_id)
		print("[ex07] done, unhooking")
