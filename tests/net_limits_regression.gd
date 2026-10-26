extends SceneTree
## Datagram budget: the 1200-byte clamp, the encoder model the packer relies
## on, and the real frontier snapshot payloads that ride inside it.
##
## Godot's ENet peer has no MTU setting, so the only clamp is this module. The
## test pins the ceiling, proves the packer's arithmetic matches Godot's own
## variant encoder, and measures the live seat, mob, devil and clone snapshots.

const NetLimits = preload("res://scripts/net_limits.gd")
const TestSave := "user://net_limits_regression_state.json"

var failures := 0
var checks := 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("NET_LIMITS_FAIL  ",message)

func _remove_test_save() -> void:
	if FileAccess.file_exists(TestSave):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TestSave))


## Every datagram one RPC sends is `fixed` plus one packed batch.
func _worst_batch(batches: Array, fixed: Array) -> int:
	var worst := 0
	for batch in batches:
		var args: Array = fixed.duplicate()
		args.append(batch)
		worst = maxi(worst,NetLimits.message_size(args))
	return worst


func run() -> void:
	# --- the clamp itself ---------------------------------------------------
	check(NetLimits.MTU == 1200, "The datagram clamp is 1200 bytes")
	check(NetLimits.PAYLOAD + NetLimits.ENVELOPE == NetLimits.MTU, "The payload budget leaves the envelope inside the clamp")
	check(NetLimits.PAYLOAD > 0 and NetLimits.ENVELOPE > 0, "Both halves of the budget are positive")

	# --- encoder model ------------------------------------------------------
	# The packer adds sizes instead of re-encoding the growing batch, so its
	# model has to match var_to_bytes exactly.
	var samples: Array = [
		[],
		[17],
		[17,{"a":1,"b":"weapon"}],
		[17,[Vector3.ONE,Vector4.ZERO,"WINDUP"],{"armor":1023}],
	]
	var model_ok := true
	for sample in samples:
		if NetLimits.message_size(sample) != var_to_bytes(sample).size():
			model_ok = false
	check(model_ok, "The packer measures the same bytes the RPC encoder writes")

	# --- packing a full delve wave -----------------------------------------
	var wave: Array = []
	for index in 30:
		wave.append({"id":index,"pos":Vector3(index,1.0,-index),"yaw":1.5,"state":"WINDUP",
			"time":0.5,"health":88.0,"alive":true,"weapon":"sword","depth":3,"role":"devil"})
	var packed: Array = NetLimits.batches(wave,[123456])
	check(packed.size() > 1, "A thirty-body wave splits into several datagrams")
	check(_worst_batch(packed,[123456]) <= NetLimits.PAYLOAD, "Every wave datagram stays inside the clamped payload")
	check(_worst_batch(packed,[123456]) <= NetLimits.MTU, "No wave datagram needs ENet fragmentation")
	var seen := 0
	var ordered := true
	for batch in packed:
		for entry in batch:
			if int(entry.id) != seen:
				ordered = false
			seen += 1
	check(seen == wave.size(), "Packing loses no bodies")
	check(ordered, "Packing keeps the wave order")
	check(NetLimits.batches([]).is_empty(), "An empty wave sends nothing")
	# One oversized entry is still handed back alone instead of vanishing.
	var huge: Dictionary = {"blob":"x".repeat(NetLimits.PAYLOAD)}
	var lone: Array = NetLimits.batches([huge],[])
	check(lone.size() == 1 and lone[0].size() == 1, "An oversized entry is returned alone, never dropped")

	# --- live payloads ------------------------------------------------------
	_remove_test_save()
	var state = root.get_node("PlayerState")
	state.save_path = TestSave
	state.reset(false)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout

	# The arena and frontier share this fighter snapshot shape.
	var seat: Dictionary = game._local_seat_snapshot()
	print("NET_LIMITS_SEAT_BYTES ", NetLimits.message_size([1,0,seat]), " PAYLOAD ", NetLimits.PAYLOAD)
	check(NetLimits.fits([1,0,seat]), "The fighter snapshot fits the payload budget")
	check(NetLimits.message_size([1,0,seat]) <= NetLimits.MTU, "The fighter snapshot needs no fragmentation")
	# A remote-driven seat also echoes the owning peer's acknowledgement.
	var acked := seat.duplicate()
	acked["ack"] = [987654, Vector3(12.5,1.5,-33.25), Vector3(3.25,0.0,-1.5)]
	print("NET_LIMITS_ACK_BYTES ", NetLimits.message_size([1,0,acked]), " PAYLOAD ", NetLimits.PAYLOAD)
	check(NetLimits.fits([1,0,acked]), "The lag-compensation acknowledgement fits the payload budget")

	# The packed-size shortcut must agree with Godot's own encoder exactly.
	var probe := PackedFloat32Array([1.5, 2.5, 3.5, 0.0, -1.25])
	check(NetLimits.size(probe) == var_to_bytes(probe).size(),
		"The packed float size shortcut matches the engine encoder")

	var heaviest := 0
	var kinds := {}
	for enemy in game.enemies:
		if not is_instance_valid(enemy):
			continue
		var snapshot = enemy.snapshot(int(kinds.size()))
		var bytes := NetLimits.message_size([1,[snapshot]])
		heaviest = maxi(heaviest,bytes)
		kinds[int(enemy.get("kind"))] = true
	check(not kinds.is_empty(), "The frontier fields mobs to measure")
	print("NET_LIMITS_MOB_MAX ", heaviest, " PAYLOAD ", NetLimits.PAYLOAD)
	check(heaviest <= NetLimits.PAYLOAD, "Every mob snapshot fits the payload budget on its own")
	check(kinds.has(8), "The measured set includes a ranger clone")
	check(kinds.has(3) or kinds.has(4) or kinds.has(5), "The measured set includes an imported devil")

	# The frontier's mob datagram is byte-budgeted: five busy bodies are more
	# than one clamped payload, so the batch count carries fewer.
	var pack_source: Array = []
	for enemy in game.enemies:
		if not is_instance_valid(enemy):
			continue
		var snapshot = enemy.snapshot(pack_source.size())
		pack_source.append(snapshot)
		if pack_source.size() == 5:
			break
	var mob_batches: Array = NetLimits.batches(pack_source)
	check(mob_batches.size() >= 1, "The frontier packs its mob snapshots")
	check(_worst_batch(mob_batches,[]) <= NetLimits.PAYLOAD, "Every mob datagram stays inside the clamped payload")
	var packed_count := 0
	for batch in mob_batches:
		packed_count += batch.size()
	check(packed_count == pack_source.size(), "The mob packer loses no mobs")

	game.queue_free()
	await process_frame
	_remove_test_save()
	state.reset(false)
	print("NET_LIMITS_REGRESSION checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
