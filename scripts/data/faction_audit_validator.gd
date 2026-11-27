class_name FactionAuditValidator
extends RefCounted

const EXPECTED_BUILD_HOTKEYS: Array[String] = ["Q", "W", "E", "R", "T", "Y", "F", "G"]
const CANONICAL_AI_ROLES: Array[StringName] = [
	&"hub",
	&"supply",
	&"refinery",
	&"compute_hub",
	&"barracks_t1",
	&"counter_foundry",
	&"heavy_t2",
]
const FORBIDDEN_GUARDRAIL_TAGS: Array[StringName] = [&"stealth", &"cloaked", &"cloak"]


static func audit_playable_factions(factions: Array[FactionData]) -> Array[String]:
	var warnings: Array[String] = []
	var seen_dossier_slots: Dictionary = {}

	for fac: FactionData in factions:
		if fac == null or not fac.is_playable:
			continue
		var label: String = String(fac.faction_id) if fac.faction_id != &"" else fac.display_name

		# 4b. Unique dossier_slot_number & non-empty audio_timbre_profile
		if fac.dossier_slot_number <= 0:
			warnings.append("[%s] Invalid dossier_slot_number (%d)." % [label, fac.dossier_slot_number])
		elif seen_dossier_slots.has(fac.dossier_slot_number):
			warnings.append("[%s] Duplicate dossier_slot_number %d (already claimed by '%s')." % [label, fac.dossier_slot_number, String(seen_dossier_slots[fac.dossier_slot_number])])
		else:
			seen_dossier_slots[fac.dossier_slot_number] = label

		if fac.audio_timbre_profile == &"":
			warnings.append("[%s] Missing audio_timbre_profile." % label)

		# 4a. Full AI Role Coverage (7 canonical roles)
		for role: StringName in CANONICAL_AI_ROLES:
			if fac.get_ai_building_for_role(role) == null:
				warnings.append("[%s] ai_build_profile missing valid building for role '%s'." % [label, String(role)])

		# 1. Universal Command Hub Drop-Off Contract
		var hub: BuildingData = fac.get_ai_building_for_role(&"hub")
		var worker_data: UnitData = null
		if hub == null:
			warnings.append("[%s] Cannot verify Command Hub contract (missing 'hub' role)." % label)
		else:
			if not hub.is_dropoff:
				warnings.append("[%s] Command Hub '%s' must have is_dropoff = true." % [label, String(hub.building_id)])
			var dropoffs: Array[StringName] = hub.get_dropoff_resources()
			if not dropoffs.has(&"biomass") or not dropoffs.has(&"silica"):
				warnings.append("[%s] Command Hub '%s' must accept both &'biomass' and &'silica' drop-offs." % [label, String(hub.building_id)])

			# 2. Command Hub Training Role Parity (Q = Worker, W = Harvester, E = Engineer)
			var trainable: Array[UnitData] = hub.resolve_trainable_units()
			if trainable.size() < 3:
				warnings.append("[%s] Command Hub '%s' must train at least 3 units (Q=Worker, W=Harvester, E=Engineer); found %d." % [label, String(hub.building_id), trainable.size()])
			else:
				var slot_q: UnitData = trainable[0]
				var slot_w: UnitData = trainable[1]
				var slot_e: UnitData = trainable[2]
				worker_data = slot_q
				if slot_q == null or not slot_q.can_gather or slot_q.auto_gather_on_spawn:
					warnings.append("[%s] Hub Slot 0 (Q) must be primary Worker (can_gather=true, auto_gather_on_spawn=false)." % label)
				if slot_w == null or not slot_w.can_gather or not slot_w.auto_gather_on_spawn:
					warnings.append("[%s] Hub Slot 1 (W) must be automated Harvester (can_gather=true, auto_gather_on_spawn=true)." % label)
				if slot_e == null or not slot_e.can_staff_compute:
					warnings.append("[%s] Hub Slot 2 (E) must be Compute Engineer (can_staff_compute=true)." % label)

		# 3. Worker 8-Building Command Alignment (Q / W / E / R / T / Y / F / G)
		if worker_data == null:
			warnings.append("[%s] Cannot verify Worker 8-building command alignment (missing Hub Slot 0 worker)." % label)
		else:
			var build_abilities: Array[AbilityData] = []
			for ab: AbilityData in worker_data.abilities:
				if ab != null and ab.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
					build_abilities.append(ab)
			if build_abilities.size() != EXPECTED_BUILD_HOTKEYS.size():
				warnings.append("[%s] Worker '%s' has %d BUILD_PLACEMENT abilities (expected exactly %d)." % [label, String(worker_data.unit_type_id), build_abilities.size(), EXPECTED_BUILD_HOTKEYS.size()])
			var seen_hks: Dictionary = {}
			for idx: int in range(build_abilities.size()):
				var bab: AbilityData = build_abilities[idx]
				var hk: String = bab.hotkey_label.strip_edges().to_upper()
				if seen_hks.has(hk):
					warnings.append("[%s] Worker '%s' duplicate build hotkey '%s' on '%s'." % [label, String(worker_data.unit_type_id), hk, String(bab.ability_id)])
				seen_hks[hk] = true
				if idx < EXPECTED_BUILD_HOTKEYS.size() and hk != EXPECTED_BUILD_HOTKEYS[idx]:
					warnings.append("[%s] Worker '%s' build slot %d has hotkey '%s' (expected '%s')." % [label, String(worker_data.unit_type_id), idx, hk, EXPECTED_BUILD_HOTKEYS[idx]])
				if bab.building_to_build == null:
					warnings.append("[%s] Worker build ability '%s' has null building_to_build." % [label, String(bab.ability_id)])
				elif not fac.building_roster.has(bab.building_to_build):
					warnings.append("[%s] Worker build ability '%s' targets building '%s' not registered in building_roster." % [label, String(bab.ability_id), String(bab.building_to_build.building_id)])

		# 4c, 5 & 6. Roster metadata, Visual Renderer coverage, and Hard Design Guardrails
		for b: BuildingData in fac.building_roster:
			if b == null:
				continue
			if b.short_display_name.strip_edges().is_empty():
				warnings.append("[%s] Building '%s' is missing short_display_name." % [label, String(b.building_id)])
			if b.building_id != &"" and not EntityVisuals.has_renderer_for(b.building_id, true):
				warnings.append("[%s] Building '%s' has no registered FactionVisualRenderer." % [label, String(b.building_id)])

		for u: UnitData in fac.unit_roster:
			if u == null:
				continue
			if u.short_display_name.strip_edges().is_empty():
				warnings.append("[%s] Unit '%s' is missing short_display_name." % [label, String(u.unit_type_id)])
			if u.unit_type_id != &"" and not EntityVisuals.has_renderer_for(u.unit_type_id, false):
				warnings.append("[%s] Unit '%s' has no registered FactionVisualRenderer." % [label, String(u.unit_type_id)])
			for tag: StringName in u.unit_tags:
				var tl: String = String(tag).to_lower()
				if FORBIDDEN_GUARDRAIL_TAGS.has(StringName(tl)) or tl.contains("stealth") or tl.contains("cloak"):
					warnings.append("[%s] Unit '%s' violates hard guardrail with forbidden tag '%s'." % [label, String(u.unit_type_id), String(tag)])
			for ab: AbilityData in u.abilities:
				if ab == null:
					continue
				var aid_l: String = String(ab.ability_id).to_lower()
				if aid_l.contains("stealth") or aid_l.contains("cloak"):
					warnings.append("[%s] Unit '%s' ability '%s' violates hard guardrail (stealth/cloak forbidden)." % [label, String(u.unit_type_id), String(ab.ability_id)])

		for upg: UpgradeData in fac.upgrade_roster:
			if upg == null:
				continue
			if upg.short_display_name.strip_edges().is_empty():
				warnings.append("[%s] Upgrade '%s' is missing short_display_name." % [label, String(upg.upgrade_id)])

	return warnings
