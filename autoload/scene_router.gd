extends Node
## Central scene-transition API. Scenes never reference each other's paths
## directly; they call through here so navigation stays in one place.
## Also owns a persistent fade overlay (survives scene changes since this
## is an autoload) so every transition gets a brief fade-to-black instead
## of an instant cut.

const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const FACTION_SETUP := "res://scenes/faction_setup/faction_setup.tscn"
const STRATEGIC_MAP := "res://scenes/strategic_map/strategic_map.tscn"
const RESULTS_SCREEN := "res://scenes/results/results_screen.tscn"

const FADE_OUT_TIME := 0.18
const FADE_IN_TIME := 0.28

var _fade_rect: ColorRect

func _ready() -> void:
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 100
	add_child(fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	fade_layer.add_child(_fade_rect)
	UIUtils.fill_parent(_fade_rect)

func goto_main_menu() -> void:
	_change_scene(MAIN_MENU)

func goto_faction_setup() -> void:
	_change_scene(FACTION_SETUP)

func goto_strategic_map() -> void:
	_change_scene(STRATEGIC_MAP)

func goto_results() -> void:
	_change_scene(RESULTS_SCREEN)

func _change_scene(path: String) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_OUT_TIME)
	await tween.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var tween_in := create_tween()
	tween_in.tween_property(_fade_rect, "color:a", 0.0, FADE_IN_TIME)
