extends Node

## Example 09: Replace + skip_super to block damage. (God mode.)
##
## Hitbox.ApplyDamage(damage) is fired every time the player or an AI
## takes a hit. We register a replace hook that calls skip_super(),
## which prevents vanilla from running. The damage is dropped on the
## floor, health stays where it was.
##
## Bounded for safety. The first 15 hits are blocked, then we disable
## ourselves so the player can eventually die. If you remove BLOCK_LIMIT
## you have permanent invincibility.
##
## Console:
##   [ex09] blocked hit 1 of 15
##   ...
##   [ex09] blocked hit 15 of 15
##   [ex09] god mode disabled, damage will land normally

const BLOCK_LIMIT := 15

var _lib: Object = null
var _blocked := 0
var _enabled := true

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("[ex09] RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	var id = _lib.hook("hitbox-applydamage", _block_damage)
	if id == -1:
		push_warning("[ex09] another mod already owns the damage replace slot")

func _block_damage(_damage = null) -> void:
	if not _enabled:
		return
	_lib.skip_super()
	_blocked += 1
	print("[ex09] blocked hit %d of %d" % [_blocked, BLOCK_LIMIT])
	if _blocked >= BLOCK_LIMIT:
		_enabled = false
		print("[ex09] god mode disabled, damage will land normally")
