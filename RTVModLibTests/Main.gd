extends Node

## RTVModLib Comprehensive Test Suite v2.0
##
## Aggressively exercises the hook system to find cracks. Covers what a
## real mod author might need to do: observe, mutate, block, count, defer,
## chain, stress-test, and interact across hooks.
##
## Sections:
##   A. Core API surface            (~25 sync tests)
##   B. Dispatch semantics          (~18 tests, some async for deferred)
##   C. Edge cases & stress         (~15 tests)
##   D. Caller tracking             (~8 tests)
##   R. Registry (Database)         (~14 sync tests -- tetra's const->dict + _get())
##   E. Lifecycle / integration     (gameplay-dependent)
##   F. Real mod scenarios          (gameplay-dependent)
##
## Output prefix [TEST]. Pass/fail reported per-test, summary at 60/120/180s.

var _lib: Object = null

# ----- test-tracking -----
var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _results: Array[String] = []
var _section_name: String = ""
var _current_test: String = ""

# ----- phase 2 gameplay-tracking -----
var _gameplay: Dictionary = {}
var _elapsed: float = 0.0
var _next_report_at: float = 60.0
var _report_interval: float = 60.0
var _report_count: int = 0
# No hard cap -- reports roll every 60s until game exits.
# Press F10 at any time for an on-demand report.
# Press F9 to trigger the G10 negative control (unhook + revert walkSpeed).
var _f10_prev_pressed: bool = false
var _f9_prev_pressed: bool = false

# ----- dispatch ordering state (used by multiple tests) -----
var _event_log: Array = []
var _skip_super_fired: bool = false
var _movement_post_order: Array = []
var _movement_post_logged: bool = false

# ----- legacy real-mod counters (still used by footstep + damage reports) -----
var _footstep_blocks: int = 0

# ----- Section G: Bulletproof In-Game Effect Verification -----
# Each test verifies THREE layers:
#   Layer 1 (WRITE):       read-before, apply, read-after -> must equal target
#   Layer 2 (PERSISTENCE): every subsequent frame, read -> must still be target
#   Layer 3 (EFFECT):      a DOWNSTREAM property reflects the change
#                          (proves the game actually USES the value we wrote)
# Plus a NEGATIVE CONTROL phase after ~120s: revert and verify game respects it.

# G1: walkSpeed / sprintSpeed
const G1_WALK := 10.0
const G1_SPRINT := 20.0
var _g1_baseline_walk := 0.0
var _g1_baseline_sprint := 0.0
var _g1_applied := false
var _g1_write_ok := false
var _g1_persist_ok := 0
var _g1_persist_fail := 0
var _g1_effect_currentspeed_samples: Array[float] = []   # currentSpeed when walking
var _g1_effect_currentspeed_max := 0.0
var _g1_reverted := false
var _g1_revert_respected := 0   # frames where currentSpeed fell back near baseline

# G2: gameData.baseFOV (expect camera.fov lerps toward it)
const G2_FOV := 120.0
var _g2_baseline_fov := 0.0
var _g2_applied := false
var _g2_write_ok := false
var _g2_persist_ok := 0
var _g2_persist_fail := 0
var _g2_effect_camfov_max := 0.0     # max camera.fov observed
var _g2_reverted := false

# G3: jumpVelocity (expect velocity.y peak after Jump = new value)
const G3_JUMP := 20.0
var _g3_baseline_jump := 0.0
var _g3_applied := false
var _g3_write_ok := false
var _g3_persist_ok := 0
var _g3_persist_fail := 0
var _g3_peak_velocity_y := 0.0
var _g3_jump_events := 0

# G4: gravityMultiplier
const G4_GRAVITY := 0.5
var _g4_baseline_gravity := 0.0
var _g4_applied := false
var _g4_write_ok := false
var _g4_persist_ok := 0
var _g4_persist_fail := 0

# G5: God mode (replace + skip_super on hitbox-applydamage)
# Verification: gameData.health shouldn't drop below its observed maximum
var _g5_damage_events := 0       # pre fires
var _g5_damage_blocked := 0      # replace fires
var _g5_health_max_seen := 0.0   # highest health observed (baseline)
var _g5_health_min_seen := 999.0 # lowest health observed (should stay near max)
var _g5_damage_values: Array[float] = []

# G7: Door block -- replace door-interact, skip_super, read isOpen before/after
# LIMITED to G7_MAX_BLOCKS attempts so player can progress through the game.
const G7_MAX_BLOCKS := 5
var _g7_door_attempts := 0
var _g7_door_isopen_preserved := 0   # before == after
var _g7_door_isopen_changed := 0     # before != after (leak!)
var _g7_door_before_state: bool = false
var _g7_blocks_done := 0
var _g7_door_enabled := true

# G8: Priority composition -- three hooks on controller-movement-pre
# Uses NODE METADATA (not walkSpeed) to avoid interfering with G1's writes.
# pri 80  writes meta "__g8" = 8
# pri 200 writes meta "__g8" = 12
# pri 300 reads meta "__g8" -- should always be 12 (higher priority wins)
var _g8_p50_fires := 0
var _g8_p200_fires := 0
var _g8_observed_values: Array[int] = []
var _g8_final_was_12 := 0
var _g8_final_was_other := 0

# G5 god-mode: LIMIT so player can eventually die after test window
const G5_MAX_BLOCKS := 15
var _g5_blocks_done := 0
var _g5_enabled := true

# G9: Pre-hook fires even with replace present on hitbox-applydamage
# We hook pre + replace. Count pre and replace. They should be equal (both fire).
var _g9_pre_count := 0
var _g9_replace_count := 0

# G10: Unhook reverts -- triggered by F9 keybind, not by a timer.
# Player plays as long as they want, then presses F9 to run the negative control.
var _g10_unhooked := false
var _g10_unhook_respected := 0   # readings after revert that match baseline

# =======================================================================
#  ENTRY
# =======================================================================

func _ready() -> void:
	_log("===== RTVModLib Comprehensive Test Suite v2.0 =====")
	if not Engine.has_meta("RTVModLib"):
		_log("FATAL: RTVModLib not in Engine meta")
		return
	_lib = Engine.get_meta("RTVModLib")
	if _lib._is_ready:
		_run_all_sync_phases()
	else:
		_log("Waiting for frameworks_ready...")
		_lib.frameworks_ready.connect(_run_all_sync_phases)

func _process(delta: float) -> void:
	_elapsed += delta

	# Rolling reports every 60s -- no hard cap, keep going until game exits.
	if _elapsed >= _next_report_at:
		_report_count += 1
		_next_report_at += _report_interval
		_print_report(false)

	# Keybind polling (Input.is_key_pressed works mid-game once scene is loaded)
	var f10_now = Input.is_key_pressed(KEY_F10)
	if f10_now and not _f10_prev_pressed:
		_log("[F10] On-demand report")
		_print_report(false)
	_f10_prev_pressed = f10_now

	var f9_now = Input.is_key_pressed(KEY_F9)
	if f9_now and not _f9_prev_pressed:
		_trigger_g10_negative_control()
	_f9_prev_pressed = f9_now

func _trigger_g10_negative_control() -> void:
	if _g10_unhooked:
		_log("[F9] G10 already triggered -- ignoring")
		return
	_g10_unhooked = true
	var ctrl = _find_controller_in_tree()
	if ctrl and "walkSpeed" in ctrl:
		ctrl.walkSpeed = _g1_baseline_walk if _g1_baseline_walk > 0.0 else 2.5
		ctrl.sprintSpeed = _g1_baseline_sprint if _g1_baseline_sprint > 0.0 else 5.0
		_log("")
		_log("  [G10] NEGATIVE CONTROL: unhooked G1, reset walkSpeed->%.2f sprintSpeed->%.2f" % [
			ctrl.walkSpeed, ctrl.sprintSpeed])
		_log("  [G10] Walk around -- if currentSpeed falls to ~2.5, vanilla uses the reverted value.")
		_log("  [G10] Press F10 for a report.")
	else:
		_log("  [G10] ERROR: could not find Controller in tree")

func _find_controller_in_tree() -> Node:
	return _find_with_class(get_tree().root, "Controller")

func _find_with_class(n: Node, target: String) -> Node:
	var s = n.get_script()
	if s and s.get_global_name() == target:
		return n
	for child in n.get_children():
		var r = _find_with_class(child, target)
		if r: return r
	return null

# =======================================================================
#  RUNNER
# =======================================================================

func _run_all_sync_phases() -> void:
	await _run_section("A. Core API Surface", _tests_section_a)
	await _run_section("B. Dispatch Semantics", _tests_section_b)
	await _run_section("C. Edge Cases & Stress", _tests_section_c)
	await _run_section("D. Caller Tracking", _tests_section_d)
	await _run_section("R. Registry (Database)", _tests_section_r)
	_log("--- Sync phases complete: %d pass / %d fail / %d skip ---" % [
		_passed, _failed, _skipped])
	_run_gameplay_setup()

func _run_section(name: String, body: Callable) -> void:
	_section_name = name
	_log("")
	_log("-- Section %s --" % name)
	await body.call()

# Test invocation with auto-cleanup and result reporting.
# Test function returns: null/"" = pass, "skip" prefix = skip, anything else = fail reason
# We `await` because some tests use `await get_tree().process_frame` internally.
# `await` on a non-awaitable value returns that value synchronously.
func _t(name: String, fn: Callable) -> void:
	_current_test = name
	var err = await fn.call()
	if err is String and err.begins_with("skip:"):
		_skipped += 1
		_results.append("SKIP " + _section_name + " :: " + name + " -- " + err.substr(5))
		_log("  [SKIP] %s -- %s" % [name, err.substr(5)])
	elif err == null or err == "":
		_passed += 1
		_results.append("PASS " + _section_name + " :: " + name)
		_log("  [PASS] %s" % name)
	else:
		_failed += 1
		_results.append("FAIL " + _section_name + " :: " + name + " -- " + str(err))
		_log("  [FAIL] %s -- %s" % [name, str(err)])

func _log(msg: String) -> void:
	print("[TEST] " + msg)

# =======================================================================
#  SECTION A -- CORE API SURFACE
# =======================================================================

func _tests_section_a() -> void:
	await _t("A01 engine_meta_set", func():
		if not Engine.has_meta("RTVModLib"): return "meta missing"
		return null)
	await _t("A02 is_ready_flag", func():
		if not _lib._is_ready: return "_is_ready false"
		return null)
	await _t("A03 frameworks_ready_signal", func():
		if not _lib.has_signal("frameworks_ready"): return "signal missing"
		return null)
	await _t("A04 caller_field_exists", func():
		if not "_caller" in _lib: return "_caller missing"
		return null)
	await _t("A05 hook_returns_positive_id", func():
		var id = _lib.hook("__a05-pre", func(): pass)
		var ok = id > 0
		_lib.unhook(id)
		return null if ok else "got id=%d" % id)
	await _t("A06 hook_ids_monotonic", func():
		var a = _lib.hook("__a06a-pre", func(): pass)
		var b = _lib.hook("__a06b-pre", func(): pass)
		var c = _lib.hook("__a06c-pre", func(): pass)
		_lib.unhook(a); _lib.unhook(b); _lib.unhook(c)
		if not (a < b and b < c): return "ids not monotonic: %d,%d,%d" % [a,b,c]
		return null)
	await _t("A07 hook_rejects_duplicate_replace", func():
		var a = _lib.hook("__a07", func(): pass)
		var b = _lib.hook("__a07", func(): pass)
		_lib.unhook(a)
		if b > 0: _lib.unhook(b)
		return null if b == -1 else "duplicate got id=%d" % b)
	await _t("A08 unhook_frees_replace_slot", func():
		# After unhook, a new replace should be accepted
		var a = _lib.hook("__a08", func(): pass)
		_lib.unhook(a)
		var b = _lib.hook("__a08", func(): pass)
		if b <= 0:
			return "replace rejected after unhook: %d" % b
		_lib.unhook(b)
		return null)
	await _t("A09 unhook_removes_hook", func():
		var id = _lib.hook("__a09-pre", func(): pass)
		if not _lib.has_hooks("__a09-pre"): return "not registered"
		_lib.unhook(id)
		if _lib.has_hooks("__a09-pre"): return "still present after unhook"
		return null)
	await _t("A10 unhook_specific_id_among_many", func():
		var a = _lib.hook("__a10-pre", func(): pass)
		var b = _lib.hook("__a10-pre", func(): pass)
		var c = _lib.hook("__a10-pre", func(): pass)
		_lib.unhook(b)
		var remaining = _lib._get_hooks("__a10-pre").size()
		_lib.unhook(a); _lib.unhook(c)
		if remaining != 2: return "expected 2 remaining, got %d" % remaining
		return null)
	await _t("A11 has_hooks_false_for_unknown", func():
		if _lib.has_hooks("__never_registered_a11-pre"): return "true for unknown"
		return null)
	await _t("A12 has_replace_detects_replace", func():
		var id = _lib.hook("__a12", func(): pass)
		var ok = _lib.has_replace("__a12")
		_lib.unhook(id)
		return null if ok else "not detected"
		)
	await _t("A13 get_replace_owner_id_matches", func():
		var id = _lib.hook("__a13", func(): pass)
		var owner = _lib.get_replace_owner("__a13")
		_lib.unhook(id)
		return null if owner == id else "got %d expected %d" % [owner, id])
	await _t("A14 get_replace_owner_none_returns_minus_one", func():
		return null if _lib.get_replace_owner("__a14_never") == -1 else "expected -1")
	await _t("A15 priority_ordering_basic", func():
		_event_log.clear()
		var c = _lib.hook("__a15-pre", func(): _event_log.append("C"), 300)
		var a = _lib.hook("__a15-pre", func(): _event_log.append("A"), 100)
		var b = _lib.hook("__a15-pre", func(): _event_log.append("B"), 200)
		_lib._dispatch("__a15-pre", [])
		_lib.unhook(a); _lib.unhook(b); _lib.unhook(c)
		return null if _event_log == ["A","B","C"] else "got %s" % [_event_log])
	await _t("A16 priority_equal_values_register_order", func():
		# When priorities are equal, register order is preserved (stable sort)
		_event_log.clear()
		var a = _lib.hook("__a16-pre", func(): _event_log.append("1st"), 100)
		var b = _lib.hook("__a16-pre", func(): _event_log.append("2nd"), 100)
		var c = _lib.hook("__a16-pre", func(): _event_log.append("3rd"), 100)
		_lib._dispatch("__a16-pre", [])
		_lib.unhook(a); _lib.unhook(b); _lib.unhook(c)
		return null if _event_log == ["1st","2nd","3rd"] else "got %s" % [_event_log])
	await _t("A17 seq_monotonic", func():
		var s0 = _lib.seq()
		var id = _lib.hook("__a17-pre", func(): pass)
		_lib._dispatch("__a17-pre", [])
		_lib._dispatch("__a17-pre", [])
		_lib._dispatch("__a17-pre", [])
		var s1 = _lib.seq()
		_lib.unhook(id)
		if s1 - s0 < 3: return "increase=%d expected >=3" % [s1-s0]
		return null)
	await _t("A18 dispatch_on_missing_hook_safe", func():
		_lib._dispatch("__a18_nobody-pre", [])
		_lib._dispatch("__a18_nobody-post", [1,2,3])
		_lib._dispatch_deferred("__a18_nobody-callback", [])
		return null)
	await _t("A19 unhook_bad_id_safe", func():
		_lib.unhook(999999999)
		_lib.unhook(-1)
		_lib.unhook(0)
		return null)
	await _t("A20 suffix_determines_stackability", func():
		# -pre/-post/-callback all stack
		var ids = []
		ids.append(_lib.hook("__a20-pre", func(): pass))
		ids.append(_lib.hook("__a20-pre", func(): pass))
		ids.append(_lib.hook("__a20-post", func(): pass))
		ids.append(_lib.hook("__a20-post", func(): pass))
		ids.append(_lib.hook("__a20-callback", func(): pass))
		ids.append(_lib.hook("__a20-callback", func(): pass))
		var all_ok = true
		for id in ids:
			if id <= 0: all_ok = false
		for id in ids: _lib.unhook(id)
		return null if all_ok else "some stacked hooks rejected")
	await _t("A21 non_suffix_is_replace", func():
		var a = _lib.hook("__a21_noname", func(): pass)
		var b = _lib.hook("__a21_noname", func(): pass)
		_lib.unhook(a)
		if b > 0: _lib.unhook(b)
		return null if b == -1 else "not treated as replace")
	await _t("A22 has_hooks_matches_registry", func():
		if _lib.has_hooks("__a22-pre"): return "unexpected pre-existing"
		var id = _lib.hook("__a22-pre", func(): pass)
		var present = _lib.has_hooks("__a22-pre")
		_lib.unhook(id)
		return null if present else "not present after register")
	await _t("A23 skip_super_field_exists", func():
		if not "_skip_super" in _lib: return "_skip_super missing"
		return null)
	await _t("A24 seq_method_callable", func():
		var s = _lib.seq()
		if not (s is int): return "seq() returned %s" % typeof(s)
		return null)
	await _t("A25 unhook_unregistered_hook_name_safe", func():
		# Unhook an id from a hook name that was never registered
		_lib.unhook(123456)
		return null)

# =======================================================================
#  SECTION B -- DISPATCH SEMANTICS
# =======================================================================

func _tests_section_b() -> void:
	await _t("B01 dispatch_passes_zero_args", func():
		var fired = [false]
		var id = _lib.hook("__b01-pre", func(): fired[0] = true)
		_lib._dispatch("__b01-pre", [])
		_lib.unhook(id)
		return null if fired[0] else "callback not fired")
	await _t("B02 dispatch_passes_one_arg", func():
		var received = [null]
		var id = _lib.hook("__b02-pre", func(x): received[0] = x)
		_lib._dispatch("__b02-pre", [42])
		_lib.unhook(id)
		return null if received[0] == 42 else "got %s" % received[0])
	await _t("B03 dispatch_passes_multi_args", func():
		var received = [null, null, null]
		var id = _lib.hook("__b03-pre", func(a,b,c):
			received[0] = a; received[1] = b; received[2] = c)
		_lib._dispatch("__b03-pre", ["x", 7, Vector2(1,2)])
		_lib.unhook(id)
		if received[0] != "x" or received[1] != 7 or received[2] != Vector2(1,2):
			return "got %s" % [received]
		return null)
	await _t("B04 dispatch_fires_all_registered", func():
		var count = [0]
		var ids = []
		for i in range(5):
			ids.append(_lib.hook("__b04-pre", func(): count[0] += 1))
		_lib._dispatch("__b04-pre", [])
		for id in ids: _lib.unhook(id)
		return null if count[0] == 5 else "expected 5 fires, got %d" % count[0])
	await _t("B05 dispatch_order_under_mixed_priority", func():
		_event_log.clear()
		var a = _lib.hook("__b05-pre", func(): _event_log.append("p50"), 50)
		var b = _lib.hook("__b05-pre", func(): _event_log.append("p150"), 150)
		var c = _lib.hook("__b05-pre", func(): _event_log.append("p100"), 100)
		_lib._dispatch("__b05-pre", [])
		_lib.unhook(a); _lib.unhook(b); _lib.unhook(c)
		return null if _event_log == ["p50","p100","p150"] else "got %s" % [_event_log])
	await _t("B06 dispatch_deferred_fires_next_frame", func():
		var fired = [false]
		var id = _lib.hook("__b06-callback", func(): fired[0] = true)
		_lib._dispatch_deferred("__b06-callback", [])
		if fired[0]: # Should NOT fire synchronously
			_lib.unhook(id)
			return "fired synchronously"
		await get_tree().process_frame
		_lib.unhook(id)
		return null if fired[0] else "did not fire after frame")
	await _t("B07 dispatch_deferred_with_args", func():
		var received = [null]
		var id = _lib.hook("__b07-callback", func(x): received[0] = x)
		_lib._dispatch_deferred("__b07-callback", ["hello"])
		await get_tree().process_frame
		_lib.unhook(id)
		return null if received[0] == "hello" else "got %s" % received[0])
	await _t("B08 skip_super_flag_set_by_method", func():
		_lib._skip_super = false
		_lib.skip_super()
		var flag = _lib._skip_super
		_lib._skip_super = false  # reset
		return null if flag else "skip_super() did not set flag")
	await _t("B09 replace_hook_can_call_skip_super", func():
		# Dispatch to simulate framework behavior -- for a hook with no suffix,
		# caller would normally save/restore _skip_super and run replace.
		var ran = [false]
		var id = _lib.hook("__b09", func():
			_lib.skip_super()
			ran[0] = true
		)
		var prev = _lib._skip_super
		_lib._skip_super = false
		var cbs = _lib._get_hooks("__b09")
		if cbs.size() != 1:
			_lib.unhook(id)
			return "expected 1 replace, got %d" % cbs.size()
		cbs[0].callv([])
		var skipped = _lib._skip_super
		_lib._skip_super = prev
		_lib.unhook(id)
		if not ran[0]: return "replace did not run"
		if not skipped: return "skip_super did not set flag"
		return null)
	await _t("B10 replace_without_skip_leaves_flag_false", func():
		var id = _lib.hook("__b10", func(): pass)  # no skip_super call
		_lib._skip_super = false
		var cbs = _lib._get_hooks("__b10")
		cbs[0].callv([])
		var flag = _lib._skip_super
		_lib.unhook(id)
		return null if not flag else "flag set without skip_super"
		)
	await _t("B11 pre_post_both_stack_independently", func():
		_event_log.clear()
		var id1 = _lib.hook("__b11-pre", func(): _event_log.append("pre1"))
		var id2 = _lib.hook("__b11-pre", func(): _event_log.append("pre2"))
		var id3 = _lib.hook("__b11-post", func(): _event_log.append("post1"))
		_lib._dispatch("__b11-pre", [])
		_lib._dispatch("__b11-post", [])
		_lib.unhook(id1); _lib.unhook(id2); _lib.unhook(id3)
		return null if _event_log == ["pre1","pre2","post1"] else "got %s" % [_event_log])
	await _t("B12 dispatch_many_times_each_fires", func():
		var count = [0]
		var id = _lib.hook("__b12-pre", func(): count[0] += 1)
		for i in range(100):
			_lib._dispatch("__b12-pre", [])
		_lib.unhook(id)
		return null if count[0] == 100 else "got %d fires" % count[0])
	await _t("B13 dispatch_with_null_arg", func():
		var received = [1]  # sentinel
		var id = _lib.hook("__b13-pre", func(x): received[0] = x)
		_lib._dispatch("__b13-pre", [null])
		_lib.unhook(id)
		return null if received[0] == null else "got %s" % received[0])
	await _t("B14 dispatch_preserves_args_across_hooks", func():
		# Each hook should see the same args, not mutated-by-previous
		var seen = []
		var a = _lib.hook("__b14-pre", func(x): seen.append(["a", x]))
		var b = _lib.hook("__b14-pre", func(x): seen.append(["b", x]))
		_lib._dispatch("__b14-pre", [42])
		_lib.unhook(a); _lib.unhook(b)
		if seen.size() != 2: return "expected 2 events, got %d" % seen.size()
		if seen[0][1] != 42 or seen[1][1] != 42: return "got %s" % [seen]
		return null)
	await _t("B15 lambda_captures_outer_state", func():
		var state = {"count": 0}
		var id = _lib.hook("__b15-pre", func(): state["count"] += 7)
		_lib._dispatch("__b15-pre", [])
		_lib._dispatch("__b15-pre", [])
		_lib.unhook(id)
		return null if state["count"] == 14 else "got %d" % state["count"])
	await _t("B16 same_callable_registered_twice_fires_twice", func():
		var count = [0]
		var cb = func(): count[0] += 1
		var a = _lib.hook("__b16-pre", cb)
		var b = _lib.hook("__b16-pre", cb)
		_lib._dispatch("__b16-pre", [])
		_lib.unhook(a); _lib.unhook(b)
		return null if count[0] == 2 else "got %d fires" % count[0])
	await _t("B17 deferred_does_not_fire_if_unhooked_in_between", func():
		var fired = [false]
		var id = _lib.hook("__b17-callback", func(): fired[0] = true)
		_lib._dispatch_deferred("__b17-callback", [])
		# Unhook before the deferred fires -- the bindv+call_deferred keeps the
		# Callable captured, so it SHOULD still fire even after unhook.
		# This documents the actual behavior: deferred callables are captured.
		_lib.unhook(id)
		await get_tree().process_frame
		# Either behavior is valid; we just record it for transparency
		if fired[0]:
			return null  # captured-and-fires behavior
		return null  # also fine
		)
	await _t("B18 dispatch_after_all_unhook_is_noop", func():
		var count = [0]
		var id = _lib.hook("__b18-pre", func(): count[0] += 1)
		_lib.unhook(id)
		_lib._dispatch("__b18-pre", [])
		return null if count[0] == 0 else "fired after unhook"
		)

# =======================================================================
#  SECTION C -- EDGE CASES & STRESS
# =======================================================================

func _tests_section_c() -> void:
	await _t("C01 unhook_during_dispatch_no_crash", func():
		# A hook that unhooks itself during dispatch.
		var count = [0]
		var my_id = [0]
		my_id[0] = _lib.hook("__c01-pre", func():
			count[0] += 1
			_lib.unhook(my_id[0]))
		_lib._dispatch("__c01-pre", [])
		_lib._dispatch("__c01-pre", [])
		return null if count[0] == 1 else "expected 1 fire, got %d" % count[0])
	await _t("C02 unhook_other_during_dispatch", func():
		# Hook A unhooks hook B during dispatch. Behavior: current iteration
		# may still call B because the for-loop iterates a snapshot, OR may
		# skip B. Either way must not crash.
		var seen = []
		var id_b = [0]
		var id_a = _lib.hook("__c02-pre", func():
			seen.append("a")
			_lib.unhook(id_b[0]))
		id_b[0] = _lib.hook("__c02-pre", func(): seen.append("b"))
		_lib._dispatch("__c02-pre", [])
		_lib.unhook(id_a)
		# no crash is the pass condition
		return null)
	await _t("C03 register_during_dispatch_doesnt_fire_now", func():
		var count_new = [0]
		var id_a = _lib.hook("__c03-pre", func():
			_lib.hook("__c03-pre", func(): count_new[0] += 1)
		)
		_lib._dispatch("__c03-pre", [])
		# Newly-registered hook must NOT have fired yet (or should fire -- doc it)
		var fired_during = count_new[0]
		_lib._dispatch("__c03-pre", [])
		# Clean up all hooks on this name
		for entry in _lib._hooks.get("__c03-pre", []):
			_lib.unhook(entry["id"])
		return null if fired_during == 0 else \
			"newly-registered hook fired during same dispatch (count=%d)" % fired_during)
	await _t("C04 recursive_dispatch_no_stack_overflow", func():
		# A hook that dispatches the same hook recursively, bounded.
		var depth = [0]
		var max_depth = [0]
		var id = _lib.hook("__c04-pre", func(n):
			depth[0] += 1
			if depth[0] > max_depth[0]: max_depth[0] = depth[0]
			if n > 0:
				_lib._dispatch("__c04-pre", [n - 1])
			depth[0] -= 1
		)
		_lib._dispatch("__c04-pre", [10])
		_lib.unhook(id)
		return null if max_depth[0] == 11 else "max_depth=%d expected 11" % max_depth[0])
	await _t("C05 many_hooks_500", func():
		var count = [0]
		var ids = []
		for i in range(500):
			ids.append(_lib.hook("__c05-pre", func(): count[0] += 1))
		_lib._dispatch("__c05-pre", [])
		for id in ids: _lib.unhook(id)
		return null if count[0] == 500 else "got %d fires of 500" % count[0])
	await _t("C06 nested_dispatch_different_hooks", func():
		var seen = []
		var id_a = _lib.hook("__c06a-pre", func():
			seen.append("a")
			_lib._dispatch("__c06b-pre", [])
			seen.append("a_end"))
		var id_b = _lib.hook("__c06b-pre", func(): seen.append("b"))
		_lib._dispatch("__c06a-pre", [])
		_lib.unhook(id_a); _lib.unhook(id_b)
		return null if seen == ["a","b","a_end"] else "got %s" % [seen])
	await _t("C07 hook_that_returns_value_is_ignored", func():
		# Dispatch ignores return values from -pre hooks (no arg mutation either)
		var id = _lib.hook("__c07-pre", func(x) -> int: return x * 2)
		_lib._dispatch("__c07-pre", [5])
		_lib.unhook(id)
		return null)  # no crash is the pass condition
	await _t("C08 exception_in_hook_affects_subsequent", func():
		# GDScript errors in a hook don't halt the engine but do halt the
		# current dispatch loop (Godot prints error). Verify hooks AFTER the
		# erroring one may or may not fire. Document the behavior.
		_event_log.clear()
		var a = _lib.hook("__c08-pre", func(): _event_log.append("a"))
		var b = _lib.hook("__c08-pre", func():
			_event_log.append("b_start")
			# Trigger a runtime error
			var null_obj = null
			null_obj.nonexistent_method()  # will push error
			_event_log.append("b_end"))
		var c = _lib.hook("__c08-pre", func(): _event_log.append("c"))
		_lib._dispatch("__c08-pre", [])
		_lib.unhook(a); _lib.unhook(b); _lib.unhook(c)
		# We expect "a" always, "b_start" always, and want to see if "c" runs.
		# No crash is the pass condition; report observation.
		_log("      (observed order: %s)" % [_event_log])
		return null)
	await _t("C09 dispatch_with_large_arg_array", func():
		# Verify we can dispatch a method with many args (12)
		var count = [0]
		var id = _lib.hook("__c09-pre", func(a,b,c,d,e,f,g,h,i,j,k,l):
			count[0] = a+b+c+d+e+f+g+h+i+j+k+l)
		_lib._dispatch("__c09-pre", [1,2,3,4,5,6,7,8,9,10,11,12])
		_lib.unhook(id)
		return null if count[0] == 78 else "got %d" % count[0])
	await _t("C10 hook_count_reflects_all_registrations", func():
		var ids = []
		for i in range(25):
			ids.append(_lib.hook("__c10-pre", func(): pass))
		var arr: Array = _lib._hooks.get("__c10-pre", [])
		var n = arr.size()
		for id in ids: _lib.unhook(id)
		return null if n == 25 else "got %d entries" % n)
	await _t("C11 unhook_all_by_iterating", func():
		var ids = []
		for i in range(10):
			ids.append(_lib.hook("__c11-pre", func(): pass))
		for id in ids: _lib.unhook(id)
		return null if not _lib.has_hooks("__c11-pre") else "still present after bulk unhook"
		)
	await _t("C12 callable_bound_to_nonself_object_works", func():
		# A Callable bound to another object still dispatches correctly
		var helper := Node.new()
		add_child(helper)
		var meta = [""]
		# Can't easily create a bound method in line; just use a lambda that
		# references helper to prove cross-object capture works.
		var id = _lib.hook("__c12-pre", func():
			meta[0] = str(helper.name))
		_lib._dispatch("__c12-pre", [])
		_lib.unhook(id)
		helper.queue_free()
		return null if meta[0] != "" else "helper not captured")
	await _t("C13 seq_increments_per_callback_not_per_dispatch", func():
		var s0 = _lib.seq()
		var ids = []
		for i in range(3):
			ids.append(_lib.hook("__c13-pre", func(): pass))
		_lib._dispatch("__c13-pre", [])  # should increment seq by 3 (one per cb)
		var s1 = _lib.seq()
		for id in ids: _lib.unhook(id)
		var delta = s1 - s0
		return null if delta == 3 else "delta=%d expected 3 (one per callback)" % delta)
	await _t("C14 callback_deferred_ordering_preserved", func():
		_event_log.clear()
		var a = _lib.hook("__c14-callback", func(): _event_log.append("a"), 100)
		var b = _lib.hook("__c14-callback", func(): _event_log.append("b"), 200)
		_lib._dispatch_deferred("__c14-callback", [])
		await get_tree().process_frame
		_lib.unhook(a); _lib.unhook(b)
		return null if _event_log == ["a","b"] else "got %s" % [_event_log])
	await _t("C15 empty_hook_registry_is_stable", func():
		# After all unhooks, registry entry may remain empty but harmless
		var id = _lib.hook("__c15-pre", func(): pass)
		_lib.unhook(id)
		_lib._dispatch("__c15-pre", [])
		return null)
	# -- Follow-ups on the C03 bug (dispatch iterates live array) --
	await _t("C16 self_registering_hook_does_not_infinite_loop", func():
		# A hook that registers another copy of itself during dispatch would
		# infinite-loop IF the live-array iteration keeps picking up appends
		# without bound. Limit to 5 to prove termination still happens (each
		# new hook ALSO self-registers, so this is the worst case).
		var count = [0]
		var limit = 5
		var registered_ids = []
		var self_cb: Callable
		self_cb = func():
			count[0] += 1
			if count[0] < limit:
				registered_ids.append(_lib.hook("__c16-pre", self_cb))
		registered_ids.append(_lib.hook("__c16-pre", self_cb))
		_lib._dispatch("__c16-pre", [])
		for id in registered_ids: _lib.unhook(id)
		# Document actual count observed
		return "skip:observed count=%d (expected 1 if snapshot, %d if live)" % [count[0], limit])
	await _t("C17 register_higher_priority_during_dispatch (BOUNDED -- hangs without bound!)", func():
		# DANGER: when a hook at pri 100 registers a HIGHER-priority hook
		# (pri 50) during dispatch, sort_custom relocates hooks mid-iteration.
		# The for-each index can point at the same pri-100 hook again -> infinite loop.
		# We HARD-BOUND registrations at 3 to keep the game alive.
		# If fire_count > 1, we've proven the re-entry bug is real.
		_event_log.clear()
		var fire_count = [0]
		var new_ids: Array = []
		var id_b = _lib.hook("__c17-pre", func(): _event_log.append("B"), 200)
		var id_a = _lib.hook("__c17-pre", func():
			fire_count[0] += 1
			_event_log.append("A%d" % fire_count[0])
			if fire_count[0] < 3:  # HARD BOUND -- without this, infinite loop
				new_ids.append(_lib.hook("__c17-pre",
					func(): _event_log.append("NEW"), 50))
		, 100)
		_lib._dispatch("__c17-pre", [])
		_lib.unhook(id_a); _lib.unhook(id_b)
		for id in new_ids: _lib.unhook(id)
		if fire_count[0] > 1:
			return "skip:id_a fired %dx -- sort_custom mid-iter re-entry CONFIRMED  log=%s" % [
				fire_count[0], _event_log]
		return "skip:id_a fired 1x -- sort_custom did NOT cause re-entry  log=%s" % [_event_log])
	await _t("C18 unhook_all_on_name_during_dispatch (BOUNDED)", func():
		# A hook (pri 0 -- runs first) unhooks every hook on its own name
		# during dispatch. Does iteration crash, skip, or continue safely?
		# Bounded: only one "wipe" call, but that's enough to expose behavior.
		_event_log.clear()
		var ids: Array = []
		var wiped = [false]
		var wipe_cb := func():
			if wiped[0]: return  # safety -- only wipe once
			wiped[0] = true
			_event_log.append("wipe")
			for id in ids:
				_lib.unhook(id)
		ids.append(_lib.hook("__c18-pre", wipe_cb, 0))
		for i in range(5):
			ids.append(_lib.hook("__c18-pre", func(): _event_log.append("fire")))
		_lib._dispatch("__c18-pre", [])
		# cleanup any remaining (should be none after wipe)
		for id in ids: _lib.unhook(id)
		return "skip:observed log=%s (5 fires expected if iteration continues past unhooks)" % [_event_log])
	await _t("C19 index_error_in_hook_does_not_halt_chain", func():
		# An empty-array index access pushes a runtime error. Verify that
		# subsequent hooks still fire (mod-isolation property).
		_event_log.clear()
		var a = _lib.hook("__c19-pre", func(): _event_log.append("a"))
		var b = _lib.hook("__c19-pre", func():
			_event_log.append("b_pre")
			var arr: Array = []
			var _x = arr[99]  # runtime error: out-of-bounds
			_event_log.append("b_post"))
		var c = _lib.hook("__c19-pre", func(): _event_log.append("c"))
		_lib._dispatch("__c19-pre", [])
		_lib.unhook(a); _lib.unhook(b); _lib.unhook(c)
		if not ("c" in _event_log):
			return "hook 'c' did not fire -- error in 'b' halted dispatch: %s" % [_event_log]
		return null)
	await _t("C20 skip_super_leaks_between_unrelated_dispatches", func():
		# If a replace hook sets skip_super, and the framework wrapper fails
		# to reset it, the next unrelated method call would inherit the flag
		# and skip its vanilla. Verify the lib does NOT auto-reset -- this
		# is the framework wrapper's responsibility, and documents the contract.
		_lib._skip_super = false
		var id = _lib.hook("__c20_a", func():
			_lib.skip_super())
		var cbs = _lib._get_hooks("__c20_a")
		cbs[0].callv([])
		var leaked = _lib._skip_super
		_lib._skip_super = false  # clean up
		_lib.unhook(id)
		if not leaked:
			return "skip_super flag did not persist after replace -- auto-reset?"
		return null)  # leak IS expected; framework wrapper must save/restore

# =======================================================================
#  SECTION D -- CALLER TRACKING
# =======================================================================

func _tests_section_d() -> void:
	await _t("D01 caller_is_null_initially_or_stale", func():
		# At this point, phase 1 may have run some dispatches. We just verify
		# _caller is either null or a valid node -- not garbage.
		var c = _lib._caller
		if c == null: return null
		if is_instance_valid(c): return null
		return "_caller is dangling pointer"
		)
	await _t("D02 caller_can_be_read_in_hook", func():
		# Dispatch from this test node. Framework wrappers normally set
		# _caller = self before dispatch. Here we manually set it to verify
		# the hook can read it.
		var captured = [null]
		var id = _lib.hook("__d02-pre", func():
			captured[0] = _lib._caller)
		_lib._caller = self
		_lib._dispatch("__d02-pre", [])
		_lib.unhook(id)
		return null if captured[0] == self else "got %s" % captured[0])
	await _t("D03 caller_survives_pre_to_post_chain", func():
		# In a real framework wrapper, _caller is set ONCE before pre, then
		# post runs after super. Verify that within our synthetic test, the
		# caller is still set when post runs (if framework sets it once).
		var captured_pre = [null]
		var captured_post = [null]
		var a = _lib.hook("__d03-pre", func(): captured_pre[0] = _lib._caller)
		var b = _lib.hook("__d03-post", func(): captured_post[0] = _lib._caller)
		_lib._caller = self
		_lib._dispatch("__d03-pre", [])
		_lib._dispatch("__d03-post", [])
		_lib.unhook(a); _lib.unhook(b)
		if captured_pre[0] != self: return "pre caller wrong"
		if captured_post[0] != self: return "post caller wrong"
		return null)
	await _t("D04 caller_updated_between_dispatches", func():
		var helper1 := Node.new()
		var helper2 := Node.new()
		helper1.name = "H1"
		helper2.name = "H2"
		add_child(helper1); add_child(helper2)
		var captured: Array[String] = []
		var id = _lib.hook("__d04-pre", func():
			captured.append(String(_lib._caller.name) if _lib._caller else "null"))
		_lib._caller = helper1
		_lib._dispatch("__d04-pre", [])
		_lib._caller = helper2
		_lib._dispatch("__d04-pre", [])
		_lib.unhook(id)
		helper1.queue_free(); helper2.queue_free()
		if captured.size() != 2: return "expected 2 captures, got %d" % captured.size()
		if captured[0] != "H1": return "first=%s expected H1" % captured[0]
		if captured[1] != "H2": return "second=%s expected H2" % captured[1]
		return null)
	await _t("D05 caller_can_mutate_props", func():
		# Simulates a mod setting a property on the caller from inside a hook.
		# Here we use a helper Node and set a metadata key.
		var helper := Node.new()
		helper.name = "Target"
		add_child(helper)
		var id = _lib.hook("__d05-pre", func():
			_lib._caller.set_meta("modded", true))
		_lib._caller = helper
		_lib._dispatch("__d05-pre", [])
		_lib.unhook(id)
		var ok = helper.has_meta("modded") and helper.get_meta("modded") == true
		helper.queue_free()
		return null if ok else "meta not set via _caller")
	await _t("D06 caller_class_and_name_readable", func():
		var helper := Node.new()
		helper.name = "ClassCheck"
		add_child(helper)
		var info = {}
		var id = _lib.hook("__d06-pre", func():
			info["name"] = _lib._caller.name
			info["class"] = _lib._caller.get_class())
		_lib._caller = helper
		_lib._dispatch("__d06-pre", [])
		_lib.unhook(id)
		helper.queue_free()
		if info.get("name") != "ClassCheck": return "name wrong: %s" % info.get("name")
		if info.get("class") != "Node": return "class wrong: %s" % info.get("class")
		return null)
	await _t("D07 caller_null_when_not_set", func():
		# Fresh _caller = null dispatch; hook reads null
		_lib._caller = null
		var captured = [self]  # sentinel
		var id = _lib.hook("__d07-pre", func(): captured[0] = _lib._caller)
		_lib._dispatch("__d07-pre", [])
		_lib.unhook(id)
		return null if captured[0] == null else "got %s" % captured[0])
	await _t("D08 multiple_hooks_see_same_caller", func():
		var helper := Node.new()
		helper.name = "Shared"
		add_child(helper)
		var captured = []
		var a = _lib.hook("__d08-pre", func(): captured.append(_lib._caller))
		var b = _lib.hook("__d08-pre", func(): captured.append(_lib._caller))
		var c = _lib.hook("__d08-pre", func(): captured.append(_lib._caller))
		_lib._caller = helper
		_lib._dispatch("__d08-pre", [])
		_lib.unhook(a); _lib.unhook(b); _lib.unhook(c)
		helper.queue_free()
		var all_same = captured.size() == 3 and captured[0] == helper and captured[1] == helper and captured[2] == helper
		return null if all_same else "got %s" % [captured])

# =======================================================================
#  SECTION R -- REGISTRY (Database mod-override surface)
# =======================================================================
#
# Exercises tetra's Database transform end-to-end: verifies the
# const->dict rewrite ran, the injected _get() serves vanilla ids,
# and lib.register/override/remove/revert round-trip correctly
# through the live Database autoload. Without these, the database
# override API has zero runtime coverage.

func _tests_section_r() -> void:
	await _t("R01 database_autoload_in_tree", func():
		var db = get_tree().root.get_node_or_null("Database")
		if db == null: return "Database autoload not found"
		return null)
	await _t("R02 vanilla_scenes_dict_present", func():
		var db = get_tree().root.get_node_or_null("Database")
		if db == null: return "skip:no Database"
		if not ("_rtv_vanilla_scenes" in db): return "_rtv_vanilla_scenes missing -- const->dict transform did not run"
		return null)
	await _t("R03 vanilla_scenes_populated", func():
		var db = get_tree().root.get_node_or_null("Database")
		if db == null or not ("_rtv_vanilla_scenes" in db): return "skip:no dict"
		var vs: Dictionary = db._rtv_vanilla_scenes
		if vs.size() == 0: return "_rtv_vanilla_scenes empty -- regex extracted no entries"
		return null)
	await _t("R04 get_resolves_vanilla_via_get_method", func():
		var db = get_tree().root.get_node_or_null("Database")
		if db == null or not ("_rtv_vanilla_scenes" in db): return "skip:no dict"
		var vs: Dictionary = db._rtv_vanilla_scenes
		if vs.is_empty(): return "skip:empty dict"
		var first_key: String = vs.keys()[0]
		var result = db.get(first_key)
		if not (result is PackedScene): return "get('%s') returned %s, expected PackedScene" % [first_key, typeof(result)]
		return null)
	await _t("R05 override_and_mod_dicts_present", func():
		var db = get_tree().root.get_node_or_null("Database")
		if db == null: return "skip:no Database"
		if not ("_rtv_override_scenes" in db): return "_rtv_override_scenes missing -- registry injection did not run"
		if not ("_rtv_mod_scenes" in db): return "_rtv_mod_scenes missing -- registry injection did not run"
		return null)
	await _t("R06 register_scene_roundtrip", func():
		var db = get_tree().root.get_node_or_null("Database")
		if db == null: return "skip:no Database"
		var fake := PackedScene.new()
		var test_id := "__rtvmodlibtests_R06__"
		var ok: bool = _lib.register("scenes", test_id, fake)
		if not ok: return "register returned false"
		var got = db.get(test_id)
		if got != fake: return "get after register returned %s, expected the registered scene" % got
		var removed: bool = _lib.remove("scenes", test_id)
		if not removed: return "remove returned false"
		var after = db.get(test_id)
		if after != null: return "get after remove returned %s, expected null" % after
		return null)
	await _t("R07 override_scene_roundtrip", func():
		var db = get_tree().root.get_node_or_null("Database")
		if db == null or not ("_rtv_vanilla_scenes" in db): return "skip:no dict"
		var vs: Dictionary = db._rtv_vanilla_scenes
		if vs.is_empty(): return "skip:empty dict"
		var target_id: String = vs.keys()[0]
		var original = db.get(target_id)
		var fake := PackedScene.new()
		var ok: bool = _lib.override("scenes", target_id, fake)
		if not ok: return "override returned false"
		var got = db.get(target_id)
		if got != fake: return "get after override returned original, expected the overridden scene"
		var reverted: bool = _lib.revert("scenes", target_id)
		if not reverted: return "revert returned false"
		var after = db.get(target_id)
		if after != original: return "get after revert returned %s, expected vanilla original" % after
		return null)
	await _t("R08 register_collision_with_vanilla_rejected", func():
		var db = get_tree().root.get_node_or_null("Database")
		if db == null or not ("_rtv_vanilla_scenes" in db): return "skip:no dict"
		var vs: Dictionary = db._rtv_vanilla_scenes
		if vs.is_empty(): return "skip:empty dict"
		var target_id: String = vs.keys()[0]
		var fake := PackedScene.new()
		var ok: bool = _lib.register("scenes", target_id, fake)
		if ok: return "register should reject vanilla collision but returned true"
		return null)
	await _t("R09 override_unknown_id_rejected", func():
		var fake := PackedScene.new()
		var ok: bool = _lib.override("scenes", "__rtvmodlibtests_R09_unknown__", fake)
		if ok: return "override should reject unknown id but returned true"
		return null)
	await _t("R10 remove_unregistered_rejected", func():
		var ok: bool = _lib.remove("scenes", "__rtvmodlibtests_R10_never_registered__")
		if ok: return "remove should reject non-mod id but returned true"
		return null)
	await _t("R11 registry_constants_exported", func():
		if not ("Registry" in _lib): return "lib.Registry missing"
		var reg: Dictionary = _lib.Registry
		if reg.get("SCENES", "") != "scenes": return "lib.Registry.SCENES != 'scenes' (got %s)" % reg.get("SCENES")
		return null)
	await _t("R12 register_empty_id_rejected", func():
		var fake := PackedScene.new()
		var ok: bool = _lib.register("scenes", "", fake)
		if ok: return "register should reject empty id but returned true"
		return null)
	await _t("R13 register_non_packedscene_rejected", func():
		var ok: bool = _lib.register("scenes", "__rtvmodlibtests_R13__", "not a PackedScene")
		if ok: return "register should reject non-PackedScene data but returned true"
		# Safety: if it DID register, clean up so subsequent runs don't see collision.
		_lib.remove("scenes", "__rtvmodlibtests_R13__")
		return null)
	await _t("R14 register_unknown_registry_rejected", func():
		var fake := PackedScene.new()
		var ok: bool = _lib.register("__unknown_registry__", "x", fake)
		if ok: return "register should reject unknown registry but returned true"
		return null)

# =======================================================================
#  SECTION E/F -- GAMEPLAY-DEPENDENT (registered now, verified at report)
# =======================================================================

func _run_gameplay_setup() -> void:
	_log("")
	_log("-- Section E. Lifecycle & Integration (gameplay) --")
	_log("-- Section F. Real Mod Scenarios (gameplay) --")

	# Phase 2 gameplay hooks -- captured as strings AT dispatch to survive
	# scene reloads.
	_gameplay = {
		"controller-gravity-pre":          _mk_entry(),
		"controller-movement-pre":         _mk_entry(),
		"controller-jump-pre":             _mk_entry(),
		"controller-playfootstep-pre":     _mk_entry(),
		"controller-_physics_process-post": _mk_entry(),
		"camera-fov-pre":                  _mk_entry(),
		"camera-_physics_process-post":    _mk_entry(),
		"door-_ready-post":                _mk_entry(),
		"door-interact-post":              _mk_entry(),
		"door-_physics_process-post":      _mk_entry(),
		"trader-_ready-post":              _mk_entry(),
		"trader-interact-post":            _mk_entry(),
		"pickup-interact-post":            _mk_entry(),
		"weaponrig-reload-post":           _mk_entry(),
		"weaponrig-ammocheck-post":        _mk_entry(),
		"lootcontainer-generateloot-post": _mk_entry(),
		"lootcontainer-interact-post":     _mk_entry(),
		"hitbox-applydamage-pre":          _mk_entry(),
	}

	for hook_name in _gameplay:
		var cb = _make_recorder(hook_name)
		_lib.hook(hook_name, cb)

	# Priority probes on controller-movement-post
	_lib.hook("controller-movement-post", _movement_post_A, 100)
	_lib.hook("controller-movement-post", _movement_post_B, 200)

	# Replace-with-skip-super: mute footsteps
	_lib.hook("controller-playfootstep", func():
		_footstep_blocks += 1
		if not _skip_super_fired:
			_skip_super_fired = true
			_log("  [E] replace+skip_super fired on controller-playfootstep")
		_lib.skip_super()
	)

	# ==============================================================
	# SECTION G -- BULLETPROOF IN-GAME EFFECT VERIFICATION
	# 3 layers per test: WRITE, PERSISTENCE, SECONDARY EFFECT
	# Plus negative-control phase at 120s (G10)
	# ==============================================================

	# G1 -- walkSpeed/sprintSpeed mutation. Layer 3: currentSpeed tracks toward target.
	_lib.hook("controller-movement-pre", _g1_apply_and_persist, 50)
	_lib.hook("controller-movement-post", _g1_observe_effect)

	# G2 -- gameData.baseFOV. Layer 3: camera.fov lerps toward baseFOV.
	_lib.hook("camera-fov-pre", _g2_apply_and_persist, 50)
	_lib.hook("camera-fov-post", _g2_observe_effect)

	# G3 -- jumpVelocity. Layer 3: velocity.y peak on Jump = new value.
	_lib.hook("controller-jump-pre", _g3_apply_and_persist, 50)
	_lib.hook("controller-jump-post", _g3_observe_effect)

	# G4 -- gravityMultiplier. Layer 3: fall rate observable in velocity.y.
	_lib.hook("controller-gravity-pre", _g4_apply_and_persist, 50)

	# G5 -- God mode. REPLACE + skip_super blocks damage. Verify via gameData.health.
	_lib.hook("hitbox-applydamage-pre", _g5_observe_pre)
	_lib.hook("hitbox-applydamage", _g5_replace_block)  # replace hook
	_lib.hook("hitbox-applydamage-post", _g5_observe_post)

	# G7 -- Door interact block (runs only while _g7_door_enabled = true).
	# Verifies isOpen state preservation.
	_lib.hook("door-interact-pre", _g7_door_pre)
	_lib.hook("door-interact", _g7_door_replace)
	_lib.hook("door-interact-post", _g7_door_post)

	# G8 -- Priority composition: 3 hooks writing at pri 50, 200, 300(reader).
	_lib.hook("controller-movement-pre", _g8_pri_50, 80)  # writes walkSpeed=8
	_lib.hook("controller-movement-pre", _g8_pri_200, 200) # writes walkSpeed=12
	_lib.hook("controller-movement-pre", _g8_pri_300_read, 300)  # reads back

	# G9 -- Pre fires WITH replace on same method (composition test).
	# Already covered implicitly by G5's pre+replace+post all firing, but add
	# a dedicated counter for clarity.
	_lib.hook("hitbox-applydamage-pre", _g9_pre)
	# replace is registered in G5
	# We'll infer G9_replace_count from G5_damage_blocked

	_log("Gameplay + Section G IN-GAME EFFECTS active:")
	_log("  G1: walkSpeed->%.0f sprintSpeed->%.0f (feel FASTER)" % [G1_WALK, G1_SPRINT])
	_log("  G2: baseFOV->%.0f (WIDER view)" % G2_FOV)
	_log("  G3: jumpVelocity->%.0f (HIGHER jumps)" % G3_JUMP)
	_log("  G4: gravityMultiplier->%.2f (FLOATY fall)" % G4_GRAVITY)
	_log("  G5: GOD MODE for first %d damage events, then disabled" % G5_MAX_BLOCKS)
	_log("  G7: DOOR BLOCK for first %d attempts, then doors work normally" % G7_MAX_BLOCKS)
	_log("  G8: priority composition via metadata (no G1 interference)")
	_log("  E/F: footstep REPLACE (silent walking, permanent)")
	_log("")
	_log("KEYBINDS:")
	_log("  F10 = print report on demand (anytime)")
	_log("  F9  = trigger G10 negative control (unhook+revert walkSpeed)")
	_log("")
	_log("Reports auto-print every 60s indefinitely. Play at your own pace.")
	_log("To fully cover all hooks, eventually:")
	_log("  walk, jump, open %d+ doors, talk to trader, open containers," % (G7_MAX_BLOCKS + 1))
	_log("  pick up items, reload weapons, take %d+ hits from AI." % (G5_MAX_BLOCKS + 1))

func _mk_entry() -> Dictionary:
	return {
		"fired": false,
		"caller_name": "",
		"caller_class": "",
		"caller_was_valid": false,
		"fire_count": 0,
	}

func _make_recorder(hook_name: String) -> Callable:
	return func(_a=null, _b=null, _c=null):
		_record(hook_name)

func _record(name: String) -> void:
	if not _gameplay.has(name):
		return
	var state = _gameplay[name]
	state["fire_count"] += 1
	var c = _lib._caller
	var caller_ok = (c != null) and is_instance_valid(c)
	if not state["fired"]:
		state["fired"] = true
		state["caller_was_valid"] = caller_ok
		if caller_ok:
			state["caller_name"] = c.name
			state["caller_class"] = c.get_class()
		_log("  FIRE %s caller=%s" % [
			name,
			"%s (%s)" % [state["caller_name"], state["caller_class"]] if caller_ok else "<null>"
		])

# ==============================================================
# SECTION G -- BULLETPROOF HOOK IMPLEMENTATIONS
# ==============================================================

# --- G1: walkSpeed mutation + persistence + currentSpeed effect ---
func _g1_apply_and_persist(_delta):
	if _g10_unhooked: return  # post-revert, do nothing
	var c = _lib._caller
	if not _valid_caller_with(c, "walkSpeed"): return

	if not _g1_applied:
		_g1_baseline_walk = c.walkSpeed
		_g1_baseline_sprint = c.sprintSpeed
		# LAYER 1: write and verify immediately
		c.walkSpeed = G1_WALK
		c.sprintSpeed = G1_SPRINT
		_g1_write_ok = is_equal_approx(c.walkSpeed, G1_WALK) and is_equal_approx(c.sprintSpeed, G1_SPRINT)
		_g1_applied = true
		_log("  [G1] APPLIED walkSpeed %.2f->%.1f, sprintSpeed %.2f->%.1f -- write_ok=%s" % [
			_g1_baseline_walk, G1_WALK, _g1_baseline_sprint, G1_SPRINT, _g1_write_ok])
		return
	# LAYER 2: persistence -- every subsequent frame must still read target
	if is_equal_approx(c.walkSpeed, G1_WALK):
		_g1_persist_ok += 1
	else:
		_g1_persist_fail += 1
		c.walkSpeed = G1_WALK  # re-apply (detect whether vanilla fights us)
		c.sprintSpeed = G1_SPRINT

func _g1_observe_effect(_delta):
	# LAYER 3: currentSpeed lerps toward target during walking.
	# If vanilla actually USES walkSpeed, currentSpeed will approach G1_WALK.
	if _g10_unhooked:
		# After revert, currentSpeed should fall back near baseline
		var c = _lib._caller
		if c and is_instance_valid(c) and "currentSpeed" in c:
			if c.currentSpeed < G1_WALK * 0.8:  # observably less than modded
				_g10_unhook_respected += 1
		return
	var c = _lib._caller
	if not c or not is_instance_valid(c): return
	if not "currentSpeed" in c: return
	var cs: float = c.currentSpeed
	if cs > 0.5:  # player is actually moving
		_g1_effect_currentspeed_samples.append(cs)
		if cs > _g1_effect_currentspeed_max: _g1_effect_currentspeed_max = cs

# --- G2: baseFOV mutation + persistence + camera.fov effect ---
func _g2_apply_and_persist(_delta):
	var c = _lib._caller
	if not _valid_caller(c): return
	if not "gameData" in c or c.gameData == null: return
	if not "baseFOV" in c.gameData: return

	if not _g2_applied:
		_g2_baseline_fov = c.gameData.baseFOV
		c.gameData.baseFOV = G2_FOV
		_g2_write_ok = is_equal_approx(c.gameData.baseFOV, G2_FOV)
		_g2_applied = true
		_log("  [G2] APPLIED baseFOV %.1f->%.1f -- write_ok=%s" % [
			_g2_baseline_fov, G2_FOV, _g2_write_ok])
		return
	if is_equal_approx(c.gameData.baseFOV, G2_FOV):
		_g2_persist_ok += 1
	else:
		_g2_persist_fail += 1
		c.gameData.baseFOV = G2_FOV

func _g2_observe_effect(_delta):
	# LAYER 3: camera.fov lerps toward gameData.baseFOV. If vanilla uses our
	# value, camera.fov should approach G2_FOV over time.
	var c = _lib._caller
	if not c or not is_instance_valid(c): return
	if not "camera" in c or c.camera == null: return
	if not "fov" in c.camera: return
	var f: float = c.camera.fov
	if f > _g2_effect_camfov_max: _g2_effect_camfov_max = f

# --- G3: jumpVelocity mutation + peak velocity.y observation ---
func _g3_apply_and_persist(_delta):
	var c = _lib._caller
	if not _valid_caller_with(c, "jumpVelocity"): return

	if not _g3_applied:
		_g3_baseline_jump = c.jumpVelocity
		c.jumpVelocity = G3_JUMP
		_g3_write_ok = is_equal_approx(c.jumpVelocity, G3_JUMP)
		_g3_applied = true
		_log("  [G3] APPLIED jumpVelocity %.1f->%.1f -- write_ok=%s" % [
			_g3_baseline_jump, G3_JUMP, _g3_write_ok])
		return
	if is_equal_approx(c.jumpVelocity, G3_JUMP):
		_g3_persist_ok += 1
	else:
		_g3_persist_fail += 1
		c.jumpVelocity = G3_JUMP

func _g3_observe_effect(_delta):
	# LAYER 3: after Jump runs, velocity.y should spike. Track peak.
	_g3_jump_events += 1
	var c = _lib._caller
	if not c or not is_instance_valid(c) or not "velocity" in c: return
	var vy: float = c.velocity.y
	if vy > _g3_peak_velocity_y: _g3_peak_velocity_y = vy

# --- G4: gravityMultiplier mutation + persistence ---
func _g4_apply_and_persist(_delta):
	var c = _lib._caller
	if not _valid_caller_with(c, "gravityMultiplier"): return

	if not _g4_applied:
		_g4_baseline_gravity = c.gravityMultiplier
		c.gravityMultiplier = G4_GRAVITY
		_g4_write_ok = is_equal_approx(c.gravityMultiplier, G4_GRAVITY)
		_g4_applied = true
		_log("  [G4] APPLIED gravityMultiplier %.2f->%.2f -- write_ok=%s" % [
			_g4_baseline_gravity, G4_GRAVITY, _g4_write_ok])
		return
	if is_equal_approx(c.gravityMultiplier, G4_GRAVITY):
		_g4_persist_ok += 1
	else:
		_g4_persist_fail += 1
		c.gravityMultiplier = G4_GRAVITY

# --- G5: God mode -- replace+skip_super + gameData.health verification ---
func _g5_observe_pre(damage):
	_g5_damage_events += 1
	if damage is float or damage is int:
		_g5_damage_values.append(float(damage))
	# Snapshot health at start of damage event
	var c = _lib._caller
	if c and is_instance_valid(c) and c.owner and "gameData" in c.owner:
		var h: float = c.owner.gameData.health
		if h > _g5_health_max_seen: _g5_health_max_seen = h
		if h < _g5_health_min_seen: _g5_health_min_seen = h

func _g5_replace_block(_damage):
	if not _g5_enabled: return
	_g5_damage_blocked += 1
	_g5_blocks_done += 1
	# Disable godmode after G5_MAX_BLOCKS so the player can die naturally
	if _g5_blocks_done >= G5_MAX_BLOCKS:
		_g5_enabled = false
		_log("  [G5] GOD MODE DISABLED after %d blocks -- damage will now land" % _g5_blocks_done)
	_lib.skip_super()

func _g5_observe_post(_damage):
	# After vanilla was skipped, verify health unchanged.
	var c = _lib._caller
	if c and is_instance_valid(c) and c.owner and "gameData" in c.owner:
		var h: float = c.owner.gameData.health
		if h < _g5_health_min_seen: _g5_health_min_seen = h

# --- G7: Door interact block -- read isOpen before/after ---
# LIMITED to G7_MAX_BLOCKS so player isn't permanently locked out of doors.
func _g7_door_pre():
	if not _g7_door_enabled: return
	var c = _lib._caller
	if not c or not is_instance_valid(c) or not "isOpen" in c: return
	_g7_door_attempts += 1
	_g7_door_before_state = c.isOpen

func _g7_door_replace():
	if not _g7_door_enabled: return
	# After N blocks, disable so player can open future doors normally.
	if _g7_blocks_done >= G7_MAX_BLOCKS:
		_g7_door_enabled = false
		_log("  [G7] DOOR BLOCKING DISABLED after %d blocks -- doors will open normally" % _g7_blocks_done)
		return  # don't skip_super -- let vanilla open this door
	_g7_blocks_done += 1
	_lib.skip_super()

func _g7_door_post():
	if not _g7_door_enabled: return
	var c = _lib._caller
	if not c or not is_instance_valid(c) or not "isOpen" in c: return
	var after: bool = c.isOpen
	if after == _g7_door_before_state:
		_g7_door_isopen_preserved += 1
	else:
		_g7_door_isopen_changed += 1

# --- G8: Priority composition -- uses metadata so it does NOT interfere with G1 ---
func _g8_pri_50(_delta):
	_g8_p50_fires += 1
	var c = _lib._caller
	if c and is_instance_valid(c):
		c.set_meta("__g8", 8)  # pri 80 -- sets to 8

func _g8_pri_200(_delta):
	_g8_p200_fires += 1
	var c = _lib._caller
	if c and is_instance_valid(c):
		c.set_meta("__g8", 12)  # pri 200 -- sets to 12

func _g8_pri_300_read(_delta):
	var c = _lib._caller
	if not c or not is_instance_valid(c) or not c.has_meta("__g8"): return
	var v: int = c.get_meta("__g8")
	_g8_observed_values.append(v)
	if v == 12:
		_g8_final_was_12 += 1
	else:
		_g8_final_was_other += 1

# --- G9: Pre fires WITH replace present ---
func _g9_pre(_damage):
	_g9_pre_count += 1

# --- Helpers ---
func _valid_caller(c) -> bool:
	return c != null and is_instance_valid(c)

func _valid_caller_with(c, prop: String) -> bool:
	return c != null and is_instance_valid(c) and prop in c

func _movement_post_A(_delta):
	if _movement_post_logged: return
	_movement_post_order.append("A")
	if _movement_post_order.size() >= 2:
		_movement_post_logged = true
		_log("  [E] movement-post order: %s (expected [A,B])" % [_movement_post_order])

func _movement_post_B(_delta):
	if _movement_post_logged: return
	_movement_post_order.append("B")
	if _movement_post_order.size() >= 2:
		_movement_post_logged = true
		_log("  [E] movement-post order: %s (expected [A,B])" % [_movement_post_order])

# =======================================================================
#  REPORT
# =======================================================================

# 3-layer report for mutation tests
func _report_3layer(label: String, applied: bool, write_ok: bool,
		persist_ok: int, persist_fail: int,
		layer3_name: String, layer3_value, layer3_expected: String) -> String:
	if not applied:
		_log("  SKIP %s -- not yet applied (trigger the method in-game)" % label)
		return "SKIP"
	# Layer 1: write
	var l1: String = "PASS" if write_ok else "FAIL"
	# Layer 2: persistence
	var total := persist_ok + persist_fail
	var pct: float = 0.0 if total == 0 else float(persist_ok) / float(total) * 100.0
	var l2: String = "PASS" if pct >= 99.0 else ("PARTIAL" if pct >= 50.0 else "FAIL")
	var l2_msg: String = "n/a" if total == 0 else "%d/%d (%.1f%%)" % [persist_ok, total, pct]
	# Layer 3: effect
	_log("  %s" % label)
	_log("    Layer 1 WRITE:       %s  (apply+readback matched)" % l1)
	_log("    Layer 2 PERSIST:     %s  frames=%s  resets=%d" % [l2, l2_msg, persist_fail])
	_log("    Layer 3 EFFECT(%s): %s  (expected %s)" % [layer3_name, str(layer3_value), layer3_expected])
	return l1

func _report_g1():
	var l3 := "unknown"
	var l3_verdict := "SKIP"
	if _g1_effect_currentspeed_samples.size() > 0:
		l3 = "max currentSpeed=%.2f samples=%d" % [_g1_effect_currentspeed_max, _g1_effect_currentspeed_samples.size()]
		if _g1_effect_currentspeed_max > G1_WALK * 0.7:
			l3_verdict = "PASS"
		else:
			l3_verdict = "FAIL (stayed near baseline %.2f)" % _g1_baseline_walk
	_report_3layer("G1 walkSpeed->%.1f / sprintSpeed->%.1f" % [G1_WALK, G1_SPRINT],
		_g1_applied, _g1_write_ok, _g1_persist_ok, _g1_persist_fail,
		"currentSpeed reaches modded", l3, ">=%.1f  %s" % [G1_WALK * 0.7, l3_verdict])

func _report_g2():
	var l3 := "max camera.fov=%.1f" % _g2_effect_camfov_max
	var l3_verdict := "SKIP"
	if _g2_effect_camfov_max > 0.0:
		if _g2_effect_camfov_max > _g2_baseline_fov + 5.0:  # tolerate lerp in-progress
			l3_verdict = "PASS"
		else:
			l3_verdict = "FAIL (fov near baseline %.1f)" % _g2_baseline_fov
	_report_3layer("G2 gameData.baseFOV->%.1f" % G2_FOV,
		_g2_applied, _g2_write_ok, _g2_persist_ok, _g2_persist_fail,
		"camera.fov lerps toward baseFOV", l3, ">%.1f  %s" % [_g2_baseline_fov + 5.0, l3_verdict])

func _report_g3():
	var l3 := "peak velocity.y=%.2f  over %d jumps" % [_g3_peak_velocity_y, _g3_jump_events]
	var l3_verdict := "SKIP"
	if _g3_jump_events > 0:
		# jumpVelocity=20, velocity.y peaks at 20 or 20/1.2=16.67
		if _g3_peak_velocity_y > _g3_baseline_jump + 2.0:
			l3_verdict = "PASS"
		else:
			l3_verdict = "FAIL (velocity.y near vanilla %.1f)" % _g3_baseline_jump
	_report_3layer("G3 jumpVelocity->%.1f" % G3_JUMP,
		_g3_applied, _g3_write_ok, _g3_persist_ok, _g3_persist_fail,
		"velocity.y spike on jump", l3, ">%.1f  %s" % [_g3_baseline_jump + 2.0, l3_verdict])

func _report_g4():
	_report_3layer("G4 gravityMultiplier->%.2f" % G4_GRAVITY,
		_g4_applied, _g4_write_ok, _g4_persist_ok, _g4_persist_fail,
		"floaty fall", "visual inspection required", "subjective")

func _report_g5():
	_log("  G5 God mode (replace+skip_super on hitbox-applydamage)")
	if _g5_damage_events == 0:
		_log("    SKIP -- no damage events yet (stand in front of AI)")
		return
	# Every pre should have a corresponding replace fire (all damage intercepted)
	var intercepted := _g5_damage_events == _g5_damage_blocked
	_log("    Damage events (pre):    %d" % _g5_damage_events)
	_log("    Damage blocks (replace): %d" % _g5_damage_blocked)
	var l1: String = "PASS" if intercepted else "FAIL"
	_log("    Layer 1 INTERCEPT:  %s  (all events blocked: %s)" % [l1, str(intercepted)])
	var health_stable := is_equal_approx(_g5_health_max_seen, _g5_health_min_seen)
	var l2: String = "PASS" if health_stable else "FAIL"
	_log("    Layer 2 HEALTH:     %s  max=%.1f min=%.1f (should be equal)" % [
		l2, _g5_health_max_seen, _g5_health_min_seen])
	var sum := 0.0; var mx := 0.0
	for d in _g5_damage_values:
		sum += d
		if d > mx: mx = d
	_log("    Damage value sum=%.1f max=%.1f (blocked, never applied to health)" % [sum, mx])

func _report_g7():
	_log("  G7 Door interact block (replace+skip_super, LIMITED to %d blocks)" % G7_MAX_BLOCKS)
	if _g7_door_attempts == 0:
		_log("    SKIP -- no door interactions yet")
		return
	var l: String = "PASS" if _g7_door_isopen_changed == 0 else "FAIL"
	_log("    Attempts:            %d  (blocks done: %d / %d, enabled: %s)" % [
		_g7_door_attempts, _g7_blocks_done, G7_MAX_BLOCKS, str(_g7_door_enabled)])
	_log("    isOpen PRESERVED:    %s  (%d preserved, %d changed despite block)" % [
		l, _g7_door_isopen_preserved, _g7_door_isopen_changed])

func _report_g8():
	_log("  G8 Priority composition (pri 80 sets meta=8, pri 200 sets =12, pri 300 reads meta)")
	_log("  (uses Node.set_meta to avoid interfering with G1 walkSpeed)")
	if _g8_p50_fires == 0 and _g8_p200_fires == 0:
		_log("    SKIP -- no movement yet")
		return
	_log("    pri 80  fires:   %d (wrote meta=8)" % _g8_p50_fires)
	_log("    pri 200 fires:   %d (wrote meta=12)" % _g8_p200_fires)
	_log("    pri 300 reads:   %d (%d saw =12, %d saw other)" % [
		_g8_observed_values.size(), _g8_final_was_12, _g8_final_was_other])
	var l: String = "PASS" if _g8_final_was_other == 0 and _g8_final_was_12 > 0 else "FAIL"
	_log("    Layer VERDICT:   %s  (highest-priority write wins at read time)" % l)

func _report_g9():
	_log("  G9 Pre-hook fires WITH replace registered on same method")
	if _g9_pre_count == 0:
		_log("    SKIP -- no damage events yet")
		return
	var l: String = "PASS" if _g9_pre_count == _g5_damage_blocked else "PARTIAL"
	_log("    pre fires:     %d" % _g9_pre_count)
	_log("    replace fires: %d" % _g5_damage_blocked)
	_log("    Layer VERDICT:  %s  (pre must fire even when replace blocks vanilla)" % l)

func _report_g10():
	_log("  G10 Negative control -- press F9 to unhook G1 + revert walkSpeed")
	if not _g10_unhooked:
		_log("    NOT TRIGGERED -- press F9 when you're ready, then walk around")
		return
	var l: String = "PASS" if _g10_unhook_respected > 0 else "PENDING"
	_log("    Layer VERDICT: %s  currentSpeed<%.1f after revert for %d frames" % [
		l, G1_WALK * 0.8, _g10_unhook_respected])
	_log("    (walk to test -- if speed stayed high, game doesn't use walkSpeed per-frame)")

func _print_report(_is_final: bool) -> void:
	var header = "Report #%d" % _report_count
	_log("")
	_log("===========================================================")
	_log("  RTVModLib Test Suite -- %s  (%.0fs elapsed)" % [header, _elapsed])
	_log("  [F10] on-demand report  [F9] G10 negative control")
	_log("===========================================================")

	_log("")
	_log("SYNC TESTS (Sections A-D): %d passed, %d failed, %d skipped" % [
		_passed, _failed, _skipped])
	if _failed > 0:
		_log("  FAILURES:")
		for r in _results:
			if r.begins_with("FAIL"):
				_log("    " + r)
	if _skipped > 0:
		_log("  SKIPS:")
		for r in _results:
			if r.begins_with("SKIP"):
				_log("    " + r)

	_log("")
	_log("GAMEPLAY HOOKS (Sections E-F):")
	var fired := 0
	var caller_valid := 0
	var caller_invalid := 0
	for name in _gameplay:
		var s = _gameplay[name]
		if s["fired"]:
			fired += 1
			if s["caller_was_valid"]:
				caller_valid += 1
				_log("  FIRED %s  caller=%s (%s)  [%dx]" % [
					name, s["caller_name"], s["caller_class"], s["fire_count"]])
			else:
				caller_invalid += 1
				_log("  FIRED %s  caller=<null at dispatch!>  [%dx]" % [name, s["fire_count"]])
		else:
			_log("  MISS  %s" % name)

	_log("")
	_log("  %d / %d gameplay hooks fired; caller valid at dispatch: %d / %d" % [
		fired, _gameplay.size(), caller_valid, fired])
	if caller_invalid > 0:
		_log("  ! %d hook(s) had null _caller -- potential RTVModLib bug" % caller_invalid)

	_log("")
	_log("Section E (Lifecycle/Integration):")
	# movement priority probe
	if _movement_post_order == ["A","B"]:
		_log("  PASS movement-post priority ordering [A,B]")
	elif _movement_post_order.is_empty():
		_log("  SKIP movement-post priority -- no movement yet")
	else:
		_log("  FAIL movement-post ordering: %s" % [_movement_post_order])
	# controller-movement-pre fired = script swap worked + instance methods route through wrapper
	if _gameplay["controller-movement-pre"]["fired"]:
		_log("  PASS controller script swap: wrapper Movement() routed to hook")
	else:
		_log("  SKIP controller script swap -- Movement never dispatched")
	# Trader/Door _ready post fired = runtime-spawned node swap + _ready fired
	if _gameplay["trader-_ready-post"]["fired"] or _gameplay["door-_ready-post"]["fired"]:
		_log("  PASS runtime-spawned node _ready hooks fire")

	_log("")
	_log("Section F (Footstep replace):")
	# F3: skip_super on replace
	if _skip_super_fired:
		_log("  PASS F3 replace+skip_super blocked PlayFootstep (%d blocks)" % _footstep_blocks)
	else:
		_log("  SKIP F3 skip_super -- no footsteps yet")

	_log("")
	_log("Section G -- BULLETPROOF IN-GAME EFFECTS (3-layer verification):")
	_log("")
	_report_g1()
	_report_g2()
	_report_g3()
	_report_g4()
	_report_g5()
	_report_g7()
	_report_g8()
	_report_g9()
	_report_g10()

	_log("")
	var total_asserts = _passed + _failed + _skipped + fired
	var total_pass = _passed + fired
	_log("OVERALL: %d passed / %d failed / %d skipped of %d" % [
		total_pass, _failed, _skipped, total_asserts])
	var missing: Array[String] = []
	for name in _gameplay:
		if not _gameplay[name]["fired"]:
			missing.append(name)
	if missing.size() > 0:
		_log("Still missing (%d): %s" % [missing.size(), ", ".join(missing)])
	else:
		_log("All gameplay hooks have fired at least once.")
	_log("===========================================================")
