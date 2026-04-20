extends Node

## Example 06: Read which node triggered the hook.
##
## RTVModLib sets _lib._caller before each dispatch. From inside any
## hook callback you can read it to find out which game node fired
## the method, then read or mutate that node's state.
##
## Useful when one hook name is fired by many instances (every door
## in the world dispatches to the same "door-interact-pre" hook).
##
## Always check is_instance_valid() before touching the caller in case
## the node was freed between dispatch and your callback.
##
## Console: "[ex06] door 'FrontDoor' (Door) interacted"

var _lib: Object = null

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex06] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	_lib.hook("door-interact-pre", _identify_caller)

func _identify_caller() -> void:
	var node = _lib._caller
	if node == null or not is_instance_valid(node):
		return
	print("[ex06] door '%s' (%s) interacted" % [node.name, node.get_class()])
