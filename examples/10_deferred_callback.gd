extends Node

## Example 10: Deferred work with the -callback suffix.
##
## A hook name ending in -callback is dispatched via call_deferred,
## meaning your callback runs at the end of the current frame instead
## of in the middle of the dispatched method.
##
## Use this when you want to react to a method but need to touch the
## scene tree, queue_free a node, await a tween, or do anything that's
## unsafe to do mid-physics-tick. The original method finishes first,
## then your callback fires before the next frame starts.
##
## This example reacts to AI death by waiting one frame, then logging.
## In a real mod you'd use the deferred slot to spawn a loot drop, run
## a death notification UI, etc.
##
## Console: "[ex10] AI died (deferred)"

var _lib: Object = null

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex10] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	_lib.hook("ai-death-callback", _on_ai_death)

func _on_ai_death(_direction = null, _force = null) -> void:
	print("[ex10] AI died (deferred)")
