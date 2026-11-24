class_name RepairComponent
extends Node

const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")
const WORKER_REPAIR_RATE: float = 18.0
const ENGINEER_REPAIR_RATE: float = 24.0
const BIOMASS_COST_PER_SEC: float = 2.0
const SILICA_COST_PER_SEC: float = 1.0
const BEAM_VFX_INTERVAL: float = 0.18

const ENGINEER_REPAIRABLE_UNIT_IDS: Array = [
	&"goliath_frame",
	&"arc_lancer",
	&"chrysalis_mortar",
	&"lance_rig",
	&"signal_jammer",
	&"silica_harvester",
]

signal repair_target_changed(target: Node2D)

var target_entity: Node2D = null
var is_repairing_in_place: bool = false

var _bio_accum: float = 0.0
var _sil_accum: float = 0.0
var _vfx_timer: float = 0.0


func is_active() -> bool:
	return target_entity != null and is_instance_valid(target_entity)


func can_unit_repair(owner_unit: Unit) -> bool:
	if owner_unit == null or owner_unit.is_dead or owner_unit.is_staffed or owner_unit.data == null:
		return false
	var uid: StringName = owner_unit.get_unit_type_id()
	return owner_unit.data.can_gather or owner_unit.data.can_staff_compute or uid == &"worker" or uid == &"engineer"


func is_eligible_target(owner_unit: Unit, candidate: Node2D) -> bool:
	if not can_unit_repair(owner_unit) or candidate == null or not is_instance_valid(candidate):
		return false
	if candidate == owner_unit:
		return false
	var is_engineer: bool = owner_unit.data.can_staff_compute or owner_unit.get_unit_type_id() == &"engineer"

	if candidate is Building:
		var b: Building = candidate
		if b.is_destroyed or b.is_queued_for_deletion() or not b.is_constructed:
			return false
		var allied: bool = TeamManager.are_allies(int(owner_unit.team), int(b.team)) if TeamManager != null else (b.team == owner_unit.team)
		if not allied:
			return false
		return b.current_hp < b.max_hp - 0.5

	if is_engineer and candidate is Unit:
		var u: Unit = candidate
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion() or u.data == null:
			return false
		var allied_u: bool = TeamManager.are_allies(int(owner_unit.team), int(u.team)) if TeamManager != null else (u.team == owner_unit.team)
		if not allied_u:
			return false
		if not ENGINEER_REPAIRABLE_UNIT_IDS.has(u.get_unit_type_id()):
			return false
		return u.current_hp < u.get_max_hp() - 0.5

	return false


func start_repair(owner_unit: Unit, target: Node2D) -> bool:
	if not is_eligible_target(owner_unit, target):
		return false
	target_entity = target
	is_repairing_in_place = false
	_bio_accum = 0.0
	_sil_accum = 0.0
	_vfx_timer = 0.0
	repair_target_changed.emit(target_entity)
	return true


func cancel() -> void:
	if target_entity == null and not is_repairing_in_place:
		return
	target_entity = null
	is_repairing_in_place = false
	_bio_accum = 0.0
	_sil_accum = 0.0
	repair_target_changed.emit(null)


func tick(owner_unit: Unit, delta: float) -> void:
	if owner_unit == null or owner_unit.is_dead or owner_unit.is_staffed:
		cancel()
		return
	if not is_eligible_target(owner_unit, target_entity):
		cancel()
		owner_unit.stop_component_navigation()
		if not owner_unit.advance_command_queue():
			owner_unit.command_state = Unit.CommandState.IDLE
		return

	var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var target_r: float = 20.0
	var ignore_b: Building = null
	if target_entity is Building:
		var b: Building = target_entity as Building
		target_r = b.footprint_radius
		ignore_b = b
	elif target_entity is Unit:
		var u: Unit = target_entity as Unit
		target_r = u.data.collision_radius if u.data != null else 18.0

	var reach: float = target_r + unit_r + 36.0
	var dist: float = owner_unit.global_position.distance_to(target_entity.global_position)
	if dist <= reach:
		is_repairing_in_place = true
		owner_unit.stop_component_navigation()
		owner_unit.face_world_point(target_entity.global_position, delta)
		_apply_repair_step(owner_unit, delta)
		return

	is_repairing_in_place = false
	if target_entity is Building:
		var approach: Vector2 = owner_unit.get_or_compute_approach_point(target_entity, target_r, 8.0, ignore_b, null)
		owner_unit.request_component_navigation(approach, 12.0, 4.0)
	else:
		owner_unit.request_component_navigation(target_entity.global_position, 12.0, 4.0)


func _apply_repair_step(owner_unit: Unit, delta: float) -> void:
	var econ: EconomyManager = owner_unit.get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		var avail_bio: int = econ.get_resource(int(owner_unit.team), EconomyManager.RESOURCE_BIOMASS)
		var avail_sil: int = econ.get_resource(int(owner_unit.team), EconomyManager.RESOURCE_SILICA)
		if avail_bio <= 0 and avail_sil <= 0:
			# Pause gracefully when resources hit 0
			return
		_bio_accum += BIOMASS_COST_PER_SEC * delta
		_sil_accum += SILICA_COST_PER_SEC * delta
		var spend_dict: Dictionary = {}
		if _bio_accum >= 1.0 and avail_bio > 0:
			var b_spend: int = mini(avail_bio, int(floor(_bio_accum)))
			_bio_accum -= float(b_spend)
			spend_dict[EconomyManager.RESOURCE_BIOMASS] = b_spend
		if _sil_accum >= 1.0 and avail_sil > 0:
			var s_spend: int = mini(avail_sil, int(floor(_sil_accum)))
			_sil_accum -= float(s_spend)
			spend_dict[EconomyManager.RESOURCE_SILICA] = s_spend
		if not spend_dict.is_empty():
			econ.spend_resources(int(owner_unit.team), spend_dict)

	var is_engineer: bool = owner_unit.data != null and (owner_unit.data.can_staff_compute or owner_unit.get_unit_type_id() == &"engineer")
	var hp_rate: float = ENGINEER_REPAIR_RATE if is_engineer else WORKER_REPAIR_RATE
	var repair_amount: float = hp_rate * delta

	var finished: bool = false
	if target_entity is Building:
		var b: Building = target_entity as Building
		b.repair(repair_amount)
		finished = b.current_hp >= b.max_hp - 0.5
	elif target_entity is Unit:
		var u: Unit = target_entity as Unit
		u.heal(repair_amount)
		finished = u.current_hp >= u.get_max_hp() - 0.5

	_vfx_timer -= delta
	if _vfx_timer <= 0.0:
		_vfx_timer = BEAM_VFX_INTERVAL
		_spawn_repair_beam_vfx(owner_unit, target_entity.global_position)

	if finished:
		cancel()
		owner_unit.stop_component_navigation()
		if not owner_unit.advance_command_queue():
			owner_unit.command_state = Unit.CommandState.IDLE


func _spawn_repair_beam_vfx(owner_unit: Unit, target_pos: Vector2) -> void:
	if owner_unit.get_parent() == null or not owner_unit.visible:
		return
	var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
	fx.z_index = 53
	owner_unit.get_parent().add_child(fx)
	var beam_col: Color = Color(0.24, 0.98, 0.88, 0.95) if (owner_unit.data != null and owner_unit.data.can_staff_compute) else Color(0.32, 1.0, 0.64, 0.95)
	fx.call("setup_repair_beam", owner_unit.global_position, target_pos, beam_col)
