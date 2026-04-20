extends Node

## Example 02: Observe a method with a post-hook.
##
## Post-hooks run AFTER the original method, so you can read the
## resulting state. Here we read door.isOpen after the vanilla
## Interact() finishes, which tells us whether the door actually opened.
##
## The caller (the Door node) is available via _lib._caller.
##
## Console: "[ex02] door interact: isOpen=true"

var _lib: Object = null

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex02] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	_lib.hook("door-interact-post", _after_door_interact)

func _after_door_interact() -> void:
	var door = _lib._caller
	if door == null or not "isOpen" in door:
		return
	print("[ex02] door interact: isOpen=%s" % door.isOpen)
