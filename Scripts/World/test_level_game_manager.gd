extends Node2D

func _ready():
	print("Main level ready")
	print("Music node exists: ", Music != null)
	Music.play_combat_music()
	
	# Wait a moment and check if it's playing
	await get_tree().create_timer(0.5).timeout
	print("Music is playing: ", Music.playing)
	

func _on_button_pressed():
	get_tree().reload_current_scene()
	

func _on_button_2_pressed():
	get_tree().quit()
