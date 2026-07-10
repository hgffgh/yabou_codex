extends Node
## Wraps Steamworks (via GodotSteam) init and calls. Every call is guarded by
## is_steam_available so the game runs fine with Steam closed during dev/iteration.

signal steam_availability_changed(available: bool)

var is_steam_available: bool = false

func _ready() -> void:
	_init_steam()

func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		push_warning("SteamManager: GodotSteam addon not loaded; running without Steam.")
		is_steam_available = false
		steam_availability_changed.emit(false)
		return

	var steam := Engine.get_singleton("Steam")
	var init_result: Dictionary = steam.steamInitEx()
	is_steam_available = init_result.get("status", 1) == 0
	if is_steam_available:
		print("SteamManager: Steam initialized (app id %s)" % steam.getAppID())
	else:
		push_warning("SteamManager: Steam init failed (%s); running without Steam." % init_result.get("verbal", "unknown"))
	steam_availability_changed.emit(is_steam_available)

func unlock_achievement(achievement_id: String) -> void:
	if not is_steam_available:
		return
	var steam := Engine.get_singleton("Steam")
	steam.setAchievement(achievement_id)
	steam.storeStats()

func _process(_delta: float) -> void:
	if is_steam_available:
		Engine.get_singleton("Steam").run_callbacks()
