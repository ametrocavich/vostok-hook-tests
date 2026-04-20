# vostok-hook-tests

Test mods for [RTVModLib](https://github.com/tetrahydroc/RTVModLib), a hook framework for Road to Vostok mods. The single mod in this repo, `RTVModLibTests`, exercises the hook API end-to-end and doubles as a worked-example reference for mod authors.

This is a **mod**, not a script-only library. It loads through the [vostok-mod-loader](https://github.com/ametrocavich/vostok-mod-loader), declares which framework wrappers it needs in `mod.txt`, and runs its assertions at boot + while you play.

## Layout

```
RTVModLibTests/
  mod.txt        Declares the autoload + the framework wrappers needed
  Main.gd        ~1650 lines: every test, every example callback
```

## What it does at runtime

`Main.gd` runs in two phases:

**1. Sync phases (run once at boot, after `frameworks_ready` fires):**
| Section | Coverage | Test count |
|---|---|---|
| A | Core API surface (`hook`, `unhook`, `has_hooks`, `has_replace`, `get_replace_owner`, `seq`, suffix stackability, replace-conflict rejection, monotonic IDs, priority ordering) | 25 |
| B | Dispatch semantics (arg passing, multi-arg, deferred dispatch, `skip_super` flag, lambda capture) | 18 |
| C | Edge cases & stress (unhook-during-dispatch, register-during-dispatch, recursive dispatch, 500-hook stress, errors-in-hooks, sort_custom mid-iter behavior) | ~20 |
| D | Caller tracking (the `_caller` field set by framework wrappers) | 8 |
| R | Registry / Database (tetra's `const`->dict transform + injected `_get()` for `register`/`override`/`revert`/`remove`) | 14 |

Section R skips on RTVModLib builds that don't expose the registry surface (for example, the current public release). The remaining 4 sections work against any build that publishes the `RTVModLib` Engine meta with the documented hook API.

**2. Gameplay phase (runs while you play):**
- Sections E and F register hooks against `Controller`, `Camera`, `Door`, `Trader`, `Pickup`, `WeaponRig`, `LootContainer`, `Hitbox`. Each hook records its first fire and `_caller` on dispatch.
- Section G is the in-game effect harness. Each subtest applies a write (e.g. `walkSpeed = 10`), checks a downstream property reflects it (e.g. `currentSpeed` actually reaches 10), and counts persistence frames. G10 is a negative control: press F9, the mod unhooks itself and you can verify the game falls back to the baseline.

Reports auto-print every 60 seconds. Press F10 anytime for an on-demand report. All output is prefixed `[TEST]` so you can grep for it in the console.

## Install

1. Have [vostok-mod-loader](https://github.com/ametrocavich/vostok-mod-loader) installed.
2. Have RTVModLib (any build that publishes `Engine.get_meta("RTVModLib")` with the hook API) installed alongside it.
3. Drop the `RTVModLibTests/` folder into your `Road to Vostok/mods/` directory. Or zip it (with `mod.txt` at the archive root, `RTVModLibTests/Main.gd` inside) and use the `.vmz` extension.

The mod loader will pick it up on next launch.

## Reading the source as documentation

Each subtest in `Main.gd` is small (typically 5-15 lines) and self-contained. Read them by section:

- **Want to learn `hook`/`unhook` basics?** Open `Main.gd` and read tests `A05` through `A14`.
- **Want to see priority ordering?** `A15`, `A16`, `B05`.
- **Want to see how `skip_super` actually composes with vanilla?** `B08`-`B10`, plus `_g5_replace_block` in Section G.
- **Want a real-mod pattern (read a property, mutate it, observe the effect)?** Section G handlers `_g1_apply_and_persist` / `_g1_observe_effect` walk the full lifecycle for `walkSpeed`.
- **Want to see how to track which node triggered the hook?** Section D, plus `_make_recorder` in the gameplay setup.

## Hook name format used throughout

```
{script}-{method}-{type}
```

- `script`: lowercase script name without `.gd` (e.g. `controller`, `camera`, `lootcontainer`)
- `method`: lowercase method name (e.g. `interact`, `movement`, `generateloot`)
- `type`: `pre`, `post`, `callback`, or omitted for replace

Replace hooks are exclusive (first registration wins; subsequent attempts return `-1`). Pre, post, and callback hooks stack and run in priority order (lower number = earlier, default 100). The full list of available hook names is enumerated in comments at the bottom of [`RTVLib.gd`](https://github.com/tetrahydroc/RTVModLib/blob/main/RTVLib.gd) in the upstream RTVModLib repo.

## Layer-3 effect verification (Section G)

Most "did the hook work" checks stop at "did the callback fire?" or "did the property write succeed?" Section G goes further. For each tested property:

1. **Layer 1 (WRITE):** Read the value before, write the new value, read it back. Must equal the target.
2. **Layer 2 (PERSISTENCE):** On every subsequent dispatch, re-read. If vanilla overwrites the value, count the resets.
3. **Layer 3 (EFFECT):** Sample a downstream property the game derives from the one you wrote (e.g. `currentSpeed` for `walkSpeed`, `camera.fov` for `gameData.baseFOV`, `velocity.y` peak for `jumpVelocity`). If the downstream stays at vanilla, the write was cosmetic and didn't actually shape behavior.

This is the harness that catches "I hooked the method and my callback fires, but nothing changes in-game" bugs.

## Bounded stress tests

A few Section C tests (`C16`, `C17`, `C18`) probe behaviors that can hang the game without bounds: a hook that registers a copy of itself during dispatch, a hook that registers a higher-priority hook that `sort_custom` relocates mid-iteration, a hook that unhooks every other hook on its own name. All three are hard-bounded with explicit limits; the test result documents what was observed rather than asserting pass/fail, since the underlying behavior is implementation-defined.

## Notes

- Designed to be safe to run with other mods loaded. God mode (G5) and door blocking (G7) self-disable after a fixed number of triggers so you don't get permanently stuck.
- Intentionally noisy. The point is a permanent record of what fired, what didn't, and what the dispatched values were. If you want quiet, comment out `_log` calls.
- The `[rtvmodlib] needs=` list in `mod.txt` only loads framework wrappers for the scripts the gameplay tests touch. Add or remove entries to widen or narrow coverage.
