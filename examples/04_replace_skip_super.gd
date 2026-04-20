extends Node

## Example 04: Replace a method and skip the original.
##
## A hook name without -pre/-post/-callback suffix is a REPLACE hook.
## Only one mod can own a replace slot for a given method (first to
## register wins; subsequent attempts return -1).
##
## To prevent vanilla from running after your replace, call skip_super().
## Without skip_super(), vanilla still runs after your callback.
##
## This example silences footstep audio: every time the controller
## tries to play a footstep, we skip vanilla.
##
## Console: nothing during play, but you'll hear no footsteps.

var _lib: Object = null

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex04] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	var id = _lib.hook("controller-playfootstep", _silent_footsteps)
	if id == -1:
		push_warning("[ex04] another mod already owns the footstep replace slot")

func _silent_footsteps() -> void:
	_lib.skip_super()
