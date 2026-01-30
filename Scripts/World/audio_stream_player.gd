extends AudioStreamPlayer

var combat_music1 = preload("res://Audio/Music/Echoes of the Ronin.mp3")
var combat_music2 = preload("res://Audio/Music/Blades of Vengeance.mp3")
var menu_music = preload("res://Audio/Music/Valley of the Wandering Blade.mp3")

var menu_music_library = menu_music
var combat_music_library = [combat_music1, combat_music2]
var background_music_library = []

func play_menu_music():
	stream = menu_music
	play()

func play_combat_music():
	if combat_music_library.is_empty():
		return
	
	var random_index = randi() % combat_music_library.size()
	stream = combat_music_library[random_index]
	play()

func play_background_music():
	if background_music_library.is_empty():
		return
	
	# Randomly select one track from the library
	var random_index = randi() % background_music_library.size()
	stream = background_music_library[random_index]
	play()
