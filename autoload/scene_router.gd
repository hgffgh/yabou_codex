extends Node
## Central scene-transition API. Scenes never reference each other's paths
## directly; they call through here so navigation stays in one place.

const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const FACTION_SETUP := "res://scenes/faction_setup/faction_setup.tscn"
const STRATEGIC_MAP := "res://scenes/strategic_map/strategic_map.tscn"
const RESULTS_SCREEN := "res://scenes/results/results_screen.tscn"

func goto_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)

func goto_faction_setup() -> void:
	get_tree().change_scene_to_file(FACTION_SETUP)

func goto_strategic_map() -> void:
	get_tree().change_scene_to_file(STRATEGIC_MAP)

func goto_results() -> void:
	get_tree().change_scene_to_file(RESULTS_SCREEN)
