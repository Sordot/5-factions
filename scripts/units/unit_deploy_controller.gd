class_name UnitDeployController
extends RefCounted

const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")


static func can_toggle_deploy(unit: Unit) -> bool:
	return unit.data != null and unit.data.can_deploy and not unit.is_dead and not unit.is_staffed


static func get_deploy_progress(unit: Unit) -> float:
	var dur: float = maxf(0.1, unit._deploy_duration_active)
	if unit.deploy_state == Unit.DeployState.DEPLOYING:
		return 1.0 - clampf(unit._deploy_timer / dur, 0.0, 1.0)
	if unit.deploy_state == Unit.DeployState.UNDEPLOYING:
		return clampf(unit._deploy_timer / dur, 0.0, 1.0)
	if unit.deploy_state == Unit.DeployState.DEPLOYED:
		return 1.0
	return 0.0


static func request_deploy(unit: Unit) -> void:
	if not can_toggle_deploy(unit):
		return
	if unit.deploy_state == Unit.DeployState.DEPLOYED or unit.deploy_state == Unit.DeployState.DEPLOYING:
		return
	var total_dur: float = maxf(0.1, unit.data.deploy_duration)
	if unit.deploy_state == Unit.DeployState.UNDEPLOYING:
		unit._deploy_timer = maxf(0.05, unit._deploy_duration_active - unit._deploy_timer)
	else:
		unit._deploy_duration_active = total_dur
		unit._deploy_timer = unit._deploy_duration_active
	unit.clear_command_queue()
	unit._cancel_active_tasks(false)
	unit.command_state = Unit.CommandState.IDLE
	unit.current_target = null
	unit.stop_component_navigation()
	unit.velocity = Vector2.ZERO
	unit.deploy_state = Unit.DeployState.DEPLOYING
	if AudioManager != null:
		AudioManager.play_sfx(&"deploy_lock", -3.0, 0.03, unit.global_position, true)
	unit.queue_redraw()
	unit.deploy_state_changed.emit(unit, unit.deploy_state)
	unit.status_changed.emit(unit)


static func request_undeploy(unit: Unit) -> void:
	if not can_toggle_deploy(unit):
		return
	if unit.deploy_state == Unit.DeployState.MOBILE or unit.deploy_state == Unit.DeployState.UNDEPLOYING:
		return
	var total_dur: float = maxf(0.1, unit.data.deploy_duration)
	if unit.deploy_state == Unit.DeployState.DEPLOYING:
		unit._deploy_timer = maxf(0.05, unit._deploy_duration_active - unit._deploy_timer)
	else:
		unit._deploy_duration_active = total_dur
		unit._deploy_timer = unit._deploy_duration_active
	if unit.combat_component != null:
		unit.combat_component.cancel_attack_animation()
	unit.deploy_state = Unit.DeployState.UNDEPLOYING
	if AudioManager != null:
		AudioManager.play_sfx(&"deploy_release", -3.0, 0.03, unit.global_position, true)
	unit.queue_redraw()
	unit.deploy_state_changed.emit(unit, unit.deploy_state)
	unit.status_changed.emit(unit)


static func toggle_deploy(unit: Unit) -> void:
	if unit.deploy_state == Unit.DeployState.MOBILE or unit.deploy_state == Unit.DeployState.UNDEPLOYING:
		request_deploy(unit)
	else:
		request_undeploy(unit)


static func tick(unit: Unit, delta: float) -> void:
	if not unit.is_deploy_transitioning():
		return
	unit.velocity = Vector2.ZERO
	unit._deploy_timer = maxf(0.0, unit._deploy_timer - delta)
	unit.queue_redraw()
	if unit._deploy_timer <= 0.0:
		if unit.deploy_state == Unit.DeployState.DEPLOYING:
			unit.deploy_state = Unit.DeployState.DEPLOYED
			trigger_anchor_impact(unit)
		elif unit.deploy_state == Unit.DeployState.UNDEPLOYING:
			unit.deploy_state = Unit.DeployState.MOBILE
		if unit._entity_visuals != null and is_instance_valid(unit._entity_visuals):
			unit._entity_visuals.queue_redraw()
		unit.queue_redraw()
		unit.deploy_state_changed.emit(unit, unit.deploy_state)
		unit.status_changed.emit(unit)


static func trigger_anchor_impact(unit: Unit) -> void:
	if not unit.is_inside_tree():
		return
	var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_friendly_view: bool = viewer < 0 or (TeamManager.are_allies(viewer, int(unit.team)) if TeamManager != null else (unit.team == Unit.Team.PLAYER))
	if not is_friendly_view and not unit.visible:
		return
	var host: Node = unit.get_parent()
	if host != null:
		var fx: CombatVFX = VFXPool.acquire_combat_vfx(52) if VFXPool != null else null
		if fx == null:
			fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
			fx.z_index = 52
			host.add_child(fx)
		var rad: float = (unit.data.collision_radius if unit.data != null else 22.0) * 1.45
		fx.setup_anchor_thud(unit.global_position, rad, Color(1.0, 0.624, 0.110, 1.0))
	if AudioManager != null:
		AudioManager.play_sfx(&"deploy_anchor_lock", -3.0, 0.04, unit.global_position, true)
	var cam: Node = unit.get_tree().get_first_node_in_group("rts_camera")
	if cam != null and cam.has_method("add_camera_shake"):
		cam.call("add_camera_shake", 1.6, 0.10, unit.global_position)
