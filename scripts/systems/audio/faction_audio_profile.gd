class_name FactionAudioProfile
extends RefCounted

## Base contract for faction-specific procedural SFX, unit barks, and dynamic ambient loops.
## Register subclasses via AudioManager.register_audio_profile(profile).


func get_profile_id() -> StringName:
	return &""


func get_stream_prefix() -> String:
	return ""


func register_cooldowns(_cooldowns_ms: Dictionary) -> void:
	pass


func build_weapon_and_ability_sfx(_sfx_bank: Dictionary) -> void:
	pass


func build_bark_sfx(_sfx_bank: Dictionary) -> void:
	pass


func build_ambient_layers() -> Dictionary:
	return {}


## Optional weapon SFX routing hook for unit_data.weapon_sfx_id or unit_type_id fallback.
## Return {"sfx_id": StringName, "db": float, "jitter": float} when handled, or empty Dictionary.
func resolve_weapon_sfx(_sfx_id: StringName, _unit_type_id: StringName) -> Dictionary:
	return {}


## Optional ability SFX routing hook.
## Return {"sfx_id": StringName, "db": float, "jitter": float} when handled, or empty Dictionary.
func resolve_ability_sfx(_ability_id: StringName) -> Dictionary:
	return {}
