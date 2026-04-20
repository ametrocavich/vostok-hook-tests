# vostok-hook-tests

Reading material and a runnable test mod for [RTVModLib](https://github.com/tetrahydroc/RTVModLib), the hook framework for Road to Vostok mods.

If you're learning the hook API, **start with [`examples/`](examples/)** — ten short, self-contained `.gd` files that each demonstrate one pattern.

If you want to verify a build of RTVModLib actually behaves correctly, install [`RTVModLibTests/`](RTVModLibTests/) as a mod — it runs ~80 boot-time assertions across the API surface, then verifies every gameplay hook fires while you play with three layers of in-game effect checks.

## Layout

```
examples/                    Read these first. One pattern per file.
  README.md                  Index, mod.txt template, hook-name format.
  01_observe_pre.gd          Pre-hook on door interact.
  02_observe_post.gd         Post-hook reads resulting state.
  03_priority_ordering.gd    Three hooks at priorities 50, 100, 200.
  04_replace_skip_super.gd   Replace + skip_super to silence footsteps.
  05_mutate_property.gd      Boost walkSpeed from inside a pre-hook.
  06_caller_tracking.gd      Read _lib._caller to know which node fired.
  07_unhook_after_n.gd       Self-removing hook after N fires.
  08_replace_owner_check.gd  Defensive registration with fallback.
  09_god_mode.gd             Replace + skip_super on hitbox damage.
  10_deferred_callback.gd    -callback suffix for end-of-frame work.

RTVModLibTests/              The full test suite (one heavy mod).
  mod.txt                    Loads at boot, declares needs=...
  Main.gd                    ~1600 lines, sections A-G + report harness.
```

## Install (test suite)

1. Have [vostok-mod-loader](https://github.com/ametrocavich/vostok-mod-loader) and [RTVModLib](https://github.com/tetrahydroc/RTVModLib) installed.
2. Drop `RTVModLibTests/` into `Road to Vostok/mods/`.
3. Launch. Output prefix is `[TEST]`. Reports auto-print every 60s. F10 = on-demand report. F9 = trigger the G10 negative-control phase.

## Install (an example)

Each example file is one mod's `Main.gd` worth of code. To turn one into a working mod, see the [examples README](examples/README.md) for the `mod.txt` template and which `needs=` line to use.

## What the test suite covers

| Section | Tests | Coverage |
|---|---|---|
| A | 25 | Core API: `hook`, `unhook`, `has_hooks`, `has_replace`, `get_replace_owner`, `seq`, monotonic IDs, replace-conflict rejection, suffix stackability, priority ordering. |
| B | 18 | Dispatch semantics: arg passing, multi-arg, deferred dispatch, `skip_super` flag, lambda capture across hooks. |
| C | ~20 | Edge cases and stress: unhook-during-dispatch, register-during-dispatch, recursive dispatch, 500-hook stress, errors-in-hooks, sort_custom mid-iteration behavior. |
| D | 8 | Caller tracking via the `_caller` field set by framework wrappers before each dispatch. |
| R | 14 | Registry / Database surface (`register`, `override`, `revert`, `remove`). Skips on RTVModLib builds without these. |
| E/F | gameplay | Records first-fire and `_caller` for every gameplay hook touched. |
| G | gameplay | Three-layer in-game effect verification: WRITE / PERSIST / DOWNSTREAM-EFFECT. |

Section R skips cleanly when the registry surface isn't present (the current public RTVModLib release doesn't expose it); the rest works against any build that publishes `Engine.get_meta("RTVModLib")` with the documented hook API.

## Layer-3 effect verification

Most "did my hook work" checks stop at "did the callback fire?" or "did the property write succeed?" Section G goes further. For each tested property:

1. **WRITE** — read the old value, write the new value, read it back. Must equal target.
2. **PERSIST** — every subsequent dispatch, re-read. If vanilla overwrites it, count the resets.
3. **EFFECT** — sample a downstream property derived from the one you wrote (e.g. `currentSpeed` for `walkSpeed`, `camera.fov` for `gameData.baseFOV`, peak `velocity.y` for `jumpVelocity`). If the downstream stays at vanilla, the write was cosmetic.

This is the harness that catches "I hooked the method and my callback fires but nothing changes in-game" bugs.

## Notes

- The test suite is safe to leave running with other mods loaded. God mode and door blocking self-disable after a fixed number of triggers.
- The suite is intentionally noisy. Grep for `[TEST]` to filter the console.
- The `[rtvmodlib] needs=` list in `mod.txt` only loads framework wrappers for scripts a mod actually touches. Add or remove entries to widen or narrow what hooks are exposed.
