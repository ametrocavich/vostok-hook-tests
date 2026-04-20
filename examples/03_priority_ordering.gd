extends Node

## Example 03: Hook priority ordering.
##
## Multiple pre/post/callback hooks on the same method run in priority
## order. Lower number runs first. Default priority is 100.
##
## Three hooks register at priorities 50, 100, 200. They will fire in
## that order each time the method dispatches.
##
## Console:
##   [ex03] pri=50  (high priority, runs first)
##   [ex03] pri=100 (default, runs second)
##   [ex03] pri=200 (low priority, runs last)

var _lib: Object = null

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex03] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	_lib.hook("door-interact-pre", _high_priority, 50)
	_lib.hook("door-interact-pre", _normal_priority, 100)
	_lib.hook("door-interact-pre", _low_priority, 200)

func _high_priority() -> void:
	print("[ex03] pri=50  (high priority, runs first)")

func _normal_priority() -> void:
	print("[ex03] pri=100 (default, runs second)")

func _low_priority() -> void:
	print("[ex03] pri=200 (low priority, runs last)")
