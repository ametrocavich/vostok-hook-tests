extends Node

## Example 05: Mutate a property on the caller from inside a hook.
##
## A pre-hook fires before vanilla reads its own state, so values you
## write here are what vanilla will use this frame.
##
## We bump walkSpeed and sprintSpeed once, then keep re-applying every
## frame in case vanilla reassigns them (some games rebuild these from
## settings on hot-reload).
##
## Caller is the Controller node. We check the property exists before
## writing to it so this fails safely on game updates that rename fields.
##
## Console: "[ex05] applied walkSpeed=10.0 sprintSpeed=20.0"

const FAST_WALK := 10.0
const FAST_SPRINT := 20.0

var _lib: Object = null
var _applied := false

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex05] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	_lib.hook("controller-movement-pre", _boost_speed)

func _boost_speed() -> void:
	var ctrl = _lib._caller
	if ctrl == null or not "walkSpeed" in ctrl:
		return
	ctrl.walkSpeed = FAST_WALK
	ctrl.sprintSpeed = FAST_SPRINT
	if not _applied:
		_applied = true
		print("[ex05] applied walkSpeed=%s sprintSpeed=%s" % [FAST_WALK, FAST_SPRINT])
