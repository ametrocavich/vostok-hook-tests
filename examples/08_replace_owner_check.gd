extends Node

## Example 08: Defensive registration. Detect that another mod owns
## the replace slot and fall back to a post-hook instead of failing.
##
## Replace hooks are exclusive: first registration wins, others get -1.
## Two patterns to handle this without ugly errors:
##
##   1. Check has_replace() before calling hook() and pick a different
##      strategy (post-hook, alternative method, refuse to load).
##   2. Call hook() and check the return value for -1.
##
## This example does (1) so the user sees a clean log message instead
## of a push_warning from RTVModLib's internal rejection.
##
## Console (if uncontested):
##   [ex08] owns lootcontainer-generateloot replace slot
## Console (if another mod beat us to it):
##   [ex08] another mod owns replace, falling back to post-hook

var _lib: Object = null

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex08] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	if _lib.has_replace("lootcontainer-generateloot"):
		print("[ex08] another mod owns replace, falling back to post-hook")
		_lib.hook("lootcontainer-generateloot-post", _observe_loot)
	else:
		_lib.hook("lootcontainer-generateloot", _custom_loot)
		print("[ex08] owns lootcontainer-generateloot replace slot")

func _custom_loot() -> void:
	# Example: leave vanilla generation alone, just observe.
	# In a real mod, you'd call _lib.skip_super() and generate your own.
	pass

func _observe_loot() -> void:
	pass
