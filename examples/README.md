# RTVModLib hook examples

Each `.gd` file in this folder is a complete, self-contained example of one hook pattern. Open any file and you see the entire pattern in 30 to 50 lines: state, registration, callback, and logging all in one place.

## Index

| File | Pattern | Hook used |
|---|---|---|
| [01_observe_pre.gd](01_observe_pre.gd) | Run code before a method | `door-interact-pre` |
| [02_observe_post.gd](02_observe_post.gd) | Read state after a method | `door-interact-post` |
| [03_priority_ordering.gd](03_priority_ordering.gd) | Three hooks at different priorities | `door-interact-pre` x3 |
| [04_replace_skip_super.gd](04_replace_skip_super.gd) | Replace a method, skip vanilla | `controller-playfootstep` |
| [05_mutate_property.gd](05_mutate_property.gd) | Write to the caller's properties | `controller-movement-pre` |
| [06_caller_tracking.gd](06_caller_tracking.gd) | Identify which node fired the hook | `door-interact-pre` |
| [07_unhook_after_n.gd](07_unhook_after_n.gd) | Self-removing hook | `door-interact-pre` |
| [08_replace_owner_check.gd](08_replace_owner_check.gd) | Defensive registration with fallback | `lootcontainer-generateloot` |
| [09_god_mode.gd](09_god_mode.gd) | Block damage with replace + skip_super | `hitbox-applydamage` |
| [10_deferred_callback.gd](10_deferred_callback.gd) | Run code at end of frame instead of mid-dispatch | `ai-death-callback` |

## Running an example as a mod

These files are reading material first, runnable second. To turn any one of them into a working mod, drop it into a folder structure like this:

```
mods/
  ExampleN/
    mod.txt
    Main.gd        <-- contents of the example file
```

`mod.txt` template (replace `EXAMPLE_NUM` and the `needs=` list with the script the example hooks):

```ini
[mod]
name="Example N"
id="example_n"
version="1.0.0"
priority=0

[autoload]
ExampleN="res://ExampleN/Main.gd"

[rtvmodlib]
needs="Door"
```

The `needs=` value tells RTVModLib which framework wrapper to load. Pick the script the example hooks against:

| Example | needs= |
|---|---|
| 01, 02, 03, 06, 07 | `Door` |
| 04, 05 | `Controller` |
| 08 | `LootContainer` |
| 09 | `Hitbox` |
| 10 | `AI` |

You can also combine multiple examples into one mod by listing every script they touch, e.g. `needs="Controller,Door,Hitbox"`.

## The boilerplate, once

Every example starts with the same connect-to-RTVModLib boilerplate. It looks like this:

```gdscript
var _lib: Object = null

func _ready() -> void:
	if not Engine.has_meta("RTVModLib"):
		push_error("RTVModLib not loaded")
		return
	var lib = Engine.get_meta("RTVModLib")
	if lib._is_ready:
		_on_ready()
	else:
		lib.frameworks_ready.connect(_on_ready)

func _on_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	# register hooks here
```

Why two-step: RTVModLib publishes itself on `Engine.set_meta("RTVModLib", self)` in its own `_ready`, but its framework wrappers may still be loading. The `_is_ready` flag and `frameworks_ready` signal let you wait for the API to be safe to call regardless of mod load order.

## Hook name format

```
{script}-{method}-{type}
```

- **script**: lowercase script name without `.gd`. E.g. `door`, `controller`, `lootcontainer`.
- **method**: lowercase method name. E.g. `interact`, `movement`, `applydamage`.
- **type**: one of:
  - `pre` -- runs before vanilla. Stackable. Used to read or mutate state before vanilla touches it.
  - `post` -- runs after vanilla. Stackable. Used to read the resulting state.
  - `callback` -- runs deferred after vanilla (next idle frame). Stackable. Used for scene-tree-unsafe work.
  - omitted -- replace the method. Exclusive (first registration wins). Vanilla still runs unless you call `_lib.skip_super()`.

The full list of hook names is enumerated in comments at the bottom of [`RTVLib.gd`](https://github.com/tetrahydroc/RTVModLib/blob/main/RTVLib.gd) in the upstream RTVModLib repo.
