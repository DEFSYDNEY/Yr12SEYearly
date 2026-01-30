extends Sprite2D

func _ready():
	Music.play_menu_music()


func _on_new_game_pressed():
	get_tree().change_scene_to_file("res://Levels/test_level.tscn")


func _on_credits_pressed():
	print("Tests")


func _on_quit_pressed():
	get_tree().quit()
