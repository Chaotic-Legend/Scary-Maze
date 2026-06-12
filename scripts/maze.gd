extends Node2D

@onready var pause_container: CenterContainer = $UI/CenterContainer
@onready var paused_label: Label = $UI/CenterContainer/PausedLabel
@onready var timer_label: Label = $UI/TimerLabel
@onready var wins_label: Label = $UI/WinsLabel
@onready var fails_label: Label = $UI/FailsLabel
@onready var background_rect: TextureRect = $BackgroundLayer/BackgroundRect
@onready var background_music: AudioStreamPlayer = $BackgroundMusic
@onready var win_sound: AudioStreamPlayer = $WinSound
@onready var fail_sound: AudioStreamPlayer = $FailSound
@onready var characters_node: Node = $Characters
@export var maze_time_limit := 60.0

const ROWS = 25
const COLS = 25
const CELL_SIZE = 20
const MAZE_GENERATE_DELAY = 0.5
const EXIT_GENERATE_DELAY = 2.0
const WALL_COLOR = Color("#333333")
const PATH_COLOR = Color(0.85, 0.85, 0.85, 0.55)
const BACKGROUND_MARGIN = 250

var maze = []
var walls_container: Node2D
var boundary_container: Node2D
var player: CharacterBody2D
var exit_area: Area2D
var entrance_pos: Vector2
var exit_pos: Vector2
var transitioning = false
var is_paused = false
var timer_active = false
var time_left = 0.0
var maze_wins = 0
var maze_fails = 0
var show_line = false
var solution_path := PackedVector2Array()
var character_scenes: Array[PackedScene] = []
var current_character_scene: PackedScene = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_container.visible = false
	pause_container.process_mode = Node.PROCESS_MODE_ALWAYS
	paused_label.process_mode = Node.PROCESS_MODE_ALWAYS
	timer_label.visible = false
	timer_label.process_mode = Node.PROCESS_MODE_ALWAYS
	wins_label.process_mode = Node.PROCESS_MODE_ALWAYS
	fails_label.process_mode = Node.PROCESS_MODE_ALWAYS
	update_wins_fails_labels()
	if win_sound:
		win_sound.process_mode = Node.PROCESS_MODE_ALWAYS
	if fail_sound:
		fail_sound.process_mode = Node.PROCESS_MODE_ALWAYS
	walls_container = Node2D.new()
	walls_container.name = "Walls"
	add_child(walls_container)
	boundary_container = Node2D.new()
	boundary_container.name = "EntranceExitCollision"
	add_child(boundary_container)
	load_character_scenes()
	_setup_background()
	_setup_background_music()
	initialize_maze()
	generate_maze(false)
	var first_scene = get_random_character_scene()
	if first_scene:
		current_character_scene = first_scene
		replace_player_scene(first_scene, grid_to_world(entrance_pos) + Vector2(0, -CELL_SIZE), true)
	reset_maze_timer()
	queue_redraw()

func _process(delta):
	if Input.is_action_just_pressed("pause"):
		toggle_pause()
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("reset"):
		reset_game()
	if Input.is_action_just_pressed("show_line"):
		toggle_show_line()
	if Input.is_action_just_pressed("generate"):
		regenerate_around_player()
	update_maze_timer(delta)

func load_character_scenes():
	character_scenes.clear()
	for child in characters_node.get_children():
		if child.scene_file_path != "":
			var packed_scene: PackedScene = load(child.scene_file_path)
			if packed_scene:
				character_scenes.append(packed_scene)
		child.process_mode = Node.PROCESS_MODE_DISABLED
		child.visible = false
		for collision in child.find_children("*", "CollisionShape2D", true, false):
			collision.disabled = true
		child.queue_free()
	characters_node.process_mode = Node.PROCESS_MODE_DISABLED
	if character_scenes.is_empty():
		push_error("No character scenes found under the Characters node.\n")

func get_random_character_scene() -> PackedScene:
	if character_scenes.is_empty():
		return null
	var available_scenes = character_scenes.duplicate()
	if current_character_scene and available_scenes.size() > 1:
		available_scenes.erase(current_character_scene)
	return available_scenes.pick_random()

func toggle_pause():
	is_paused = !is_paused
	get_tree().paused = is_paused
	pause_container.visible = is_paused
	if background_music:
		background_music.stream_paused = is_paused

func reset_game():
	show_line = false
	solution_path.clear()
	get_tree().paused = false
	is_paused = false
	pause_container.visible = false
	if background_music:
		background_music.stream_paused = false
	var next_scene = get_random_character_scene()
	if next_scene:
		current_character_scene = next_scene
		replace_player_scene(next_scene, grid_to_world(entrance_pos) + Vector2(0, -CELL_SIZE), true)
	generate_maze(false)
	reset_maze_timer()
	queue_redraw()

func toggle_show_line():
	if get_tree().paused:
		return
	show_line = !show_line
	queue_redraw()

func regenerate_around_player():
	if transitioning or get_tree().paused:
		return
	transitioning = true
	generate_maze(is_player_inside_maze())
	queue_redraw()
	await get_tree().create_timer(MAZE_GENERATE_DELAY).timeout
	transitioning = false

func _setup_background():
	background_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_rect.offset_left = 0
	background_rect.offset_top = 0
	background_rect.offset_right = 0
	background_rect.offset_bottom = 0
	background_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_rect.stretch_mode = TextureRect.STRETCH_SCALE

func _setup_background_music():
	if not background_music:
		return
	background_music.process_mode = Node.PROCESS_MODE_ALWAYS
	background_music.stream_paused = false
	audio_server_unmute_music_bus()
	if background_music.stream is AudioStreamWAV:
		background_music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	if not background_music.finished.is_connected(_on_background_music_finished):
		background_music.finished.connect(_on_background_music_finished)
	call_deferred("_start_background_music")

func audio_server_unmute_music_bus():
	var bus_index = AudioServer.get_bus_index(background_music.bus)
	if bus_index != -1:
		AudioServer.set_bus_mute(bus_index, false)

func _start_background_music():
	if not background_music or not background_music.stream:
		return
	background_music.stream_paused = false
	background_music.stop()
	background_music.play(0.0)

func _on_background_music_finished():
	if background_music and background_music.stream and not background_music.stream_paused:
		background_music.play(0.0)

func play_win_sound():
	if win_sound:
		win_sound.stop()
		win_sound.play()

func play_fail_sound():
	if fail_sound:
		fail_sound.stop()
		fail_sound.play()

func initialize_maze():
	maze = []
	for r in range(ROWS):
		var row = []
		for c in range(COLS):
			row.append(1)
		maze.append(row)

func generate_maze(keep_player_inside: bool):
	var saved_player_position = Vector2.ZERO
	var saved_player_cell = Vector2i(1, 1)
	var start_cell = Vector2i(1, 1)
	if keep_player_inside and player:
		saved_player_position = player.position
		saved_player_cell = world_to_grid(saved_player_position)
		if not is_cell_inside_maze(saved_player_cell):
			keep_player_inside = false
		else:
			saved_player_cell.x = clamp(saved_player_cell.x, 1, COLS - 2)
			saved_player_cell.y = clamp(saved_player_cell.y, 1, ROWS - 2)
			start_cell = nearest_odd_cell(saved_player_cell)
	for r in range(ROWS):
		for c in range(COLS):
			maze[r][c] = 1
	maze[start_cell.y][start_cell.x] = 0
	carve_passages(start_cell.y, start_cell.x)
	create_entrance_and_exit()
	if keep_player_inside:
		keep_player_cell_open(saved_player_cell, start_cell)
	create_exit_trigger()
	create_collision_walls()
	create_entrance_exit_collision()
	if player:
		if keep_player_inside:
			player.position = saved_player_position
		else:
			player.position = grid_to_world(entrance_pos) + Vector2(0, -CELL_SIZE)

			if player.has_method("reset_to_look_down"):
				player.reset_to_look_down()
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
	update_solution_path()

func carve_passages(r, c):
	var directions = [[-2, 0], [0, 2], [2, 0], [0, -2]]
	directions.shuffle()
	for direction in directions:
		var dr = direction[0]
		var dc = direction[1]
		var new_r = r + dr
		var new_c = c + dc
		if new_r > 0 and new_r < ROWS - 1 and new_c > 0 and new_c < COLS - 1 and maze[new_r][new_c] == 1:
			maze[r + int(dr / 2)][c + int(dc / 2)] = 0
			maze[new_r][new_c] = 0
			carve_passages(new_r, new_c)

func create_entrance_and_exit():
	for c in range(1, COLS - 1):
		if maze[1][c] == 0:
			maze[0][c] = 0
			entrance_pos = Vector2(c, 0)
			break
	for c in range(COLS - 2, 0, -1):
		if maze[ROWS - 2][c] == 0:
			maze[ROWS - 1][c] = 0
			exit_pos = Vector2(c, ROWS - 1)
			break

func create_exit_trigger():
	if exit_area:
		exit_area.queue_free()
	exit_area = Area2D.new()
	exit_area.name = "Exit"
	exit_area.position = grid_to_world(exit_pos) + Vector2(0, CELL_SIZE)
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(CELL_SIZE, CELL_SIZE)
	collision.shape = shape
	exit_area.add_child(collision)
	add_child(exit_area)
	exit_area.monitoring = true
	exit_area.monitorable = true
	exit_area.body_entered.connect(_on_exit_body_entered)

func update_solution_path():
	solution_path.clear()
	var start_cell = Vector2i(int(entrance_pos.x), int(entrance_pos.y))
	if is_player_inside_maze():
		start_cell = world_to_grid(player.position)
	var end_cell = Vector2i(int(exit_pos.x), int(exit_pos.y))
	var path_cells = find_solution_path(start_cell, end_cell)
	if path_cells.is_empty():
		return
	for cell in path_cells:
		solution_path.append(grid_to_world(Vector2(cell.x, cell.y)))

func find_solution_path(start_cell: Vector2i, end_cell: Vector2i) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = []
	var came_from = {}
	frontier.append(start_cell)
	came_from[start_cell] = start_cell
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not frontier.is_empty():
		var search_cell = frontier.pop_front()
		if search_cell == end_cell:
			break
		for direction in directions:
			var next_cell = search_cell + direction
			if not is_cell_inside_maze(next_cell):
				continue
			if maze[next_cell.y][next_cell.x] == 1:
				continue
			if came_from.has(next_cell):
				continue
			came_from[next_cell] = search_cell
			frontier.append(next_cell)
	if not came_from.has(end_cell):
		return []
	var path: Array[Vector2i] = []
	var path_cell = end_cell
	while path_cell != start_cell:
		path.insert(0, path_cell)
		path_cell = came_from[path_cell]
	path.insert(0, start_cell)
	return path

func _on_exit_body_entered(body):
	if body == player and not transitioning:
		call_deferred("on_player_reached_exit")

func on_player_reached_exit():
	if transitioning:
		return
	transitioning = true
	stop_maze_timer()
	maze_wins += 1
	update_wins_fails_labels()
	play_win_sound()
	await get_tree().create_timer(EXIT_GENERATE_DELAY).timeout
	var next_scene = get_random_character_scene()
	if next_scene:
		current_character_scene = next_scene
		replace_player_scene(next_scene, grid_to_world(entrance_pos) + Vector2(0, -CELL_SIZE), true)
	generate_maze(false)
	reset_maze_timer()
	queue_redraw()
	transitioning = false

func replace_player_scene(scene: PackedScene, new_position: Vector2, look_down: bool):
	var camera: Camera2D = null
	if player:
		camera = player.get_node_or_null("Camera2D")
		if camera:
			player.remove_child(camera)
		player.queue_free()
	player = scene.instantiate()
	player.name = "Player"
	player.position = new_position
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	move_child(player, 0)
	if camera:
		player.add_child(camera)
		camera.position = Vector2.ZERO
	else:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = Vector2(6, 6)
		player.add_child(camera)
	camera.make_current()
	if look_down and player.has_method("reset_to_look_down"):
		player.reset_to_look_down()

func create_collision_walls():
	for child in walls_container.get_children():
		child.queue_free()
	for r in range(ROWS):
		for c in range(COLS):
			if maze[r][c] == 1:
				add_static_rect(
					walls_container,
					Vector2(c * CELL_SIZE + CELL_SIZE / 2.0, r * CELL_SIZE + CELL_SIZE / 2.0),
					Vector2(CELL_SIZE, CELL_SIZE))

func create_entrance_exit_collision():
	for child in boundary_container.get_children():
		child.queue_free()
	var maze_height = ROWS * CELL_SIZE
	var entrance_x = entrance_pos.x * CELL_SIZE + CELL_SIZE / 2.0
	var exit_x = exit_pos.x * CELL_SIZE + CELL_SIZE / 2.0
	var thickness = CELL_SIZE
	add_static_rect(boundary_container, Vector2(entrance_x, -CELL_SIZE * 2.5), Vector2(CELL_SIZE * 3.0, thickness))
	add_static_rect(boundary_container, Vector2(entrance_x - CELL_SIZE, -CELL_SIZE), Vector2(thickness, CELL_SIZE * 3.0))
	add_static_rect(boundary_container, Vector2(entrance_x + CELL_SIZE, -CELL_SIZE), Vector2(thickness, CELL_SIZE * 3.0))
	add_static_rect(boundary_container, Vector2(exit_x, maze_height + CELL_SIZE * 2.5), Vector2(CELL_SIZE * 3.0, thickness))
	add_static_rect(boundary_container, Vector2(exit_x - CELL_SIZE, maze_height + CELL_SIZE), Vector2(thickness, CELL_SIZE * 3.0))
	add_static_rect(boundary_container, Vector2(exit_x + CELL_SIZE, maze_height + CELL_SIZE), Vector2(thickness, CELL_SIZE * 3.0))

func add_static_rect(parent: Node, rect_position: Vector2, rect_size: Vector2):
	var body = StaticBody2D.new()
	body.position = rect_position
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = rect_size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func keep_player_cell_open(cell: Vector2i, start_cell: Vector2i):
	cell.x = clamp(cell.x, 1, COLS - 2)
	cell.y = clamp(cell.y, 1, ROWS - 2)
	maze[cell.y][cell.x] = 0
	var current = cell
	while current.x != start_cell.x:
		current.x += int(sign(start_cell.x - current.x))
		maze[current.y][current.x] = 0
	while current.y != start_cell.y:
		current.y += int(sign(start_cell.y - current.y))
		maze[current.y][current.x] = 0

func nearest_odd_cell(cell: Vector2i) -> Vector2i:
	var result = cell
	result.x = clamp(result.x, 1, COLS - 2)
	result.y = clamp(result.y, 1, ROWS - 2)
	if result.x % 2 == 0:
		result.x = clamp(result.x - 1, 1, COLS - 2)
	if result.y % 2 == 0:
		result.y = clamp(result.y - 1, 1, ROWS - 2)
	return result

func is_cell_inside_maze(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS

func is_player_inside_maze() -> bool:
	if not player:
		return false
	var cell = world_to_grid(player.position)
	return is_cell_inside_maze(cell) and player.position.y >= 0 and player.position.y < ROWS * CELL_SIZE

func update_maze_timer(delta):
	if get_tree().paused or not player:
		return
	if not timer_active and is_player_inside_maze():
		start_maze_timer()
	if not timer_active:
		return
	time_left = max(time_left - delta, 0.0)
	update_timer_label()
	if time_left <= 0.0:
		on_maze_timer_finished()

func start_maze_timer():
	timer_active = true
	time_left = maze_time_limit
	timer_label.visible = true
	update_timer_label()

func stop_maze_timer():
	timer_active = false
	timer_label.visible = false

func reset_maze_timer():
	timer_active = false
	time_left = maze_time_limit
	timer_label.visible = false
	update_timer_label()

func update_timer_label():
	timer_label.text = "TIME LEFT: %.1f" % max(time_left, 0.0)

func update_wins_fails_labels():
	wins_label.text = "MAZE WINS: %d" % maze_wins
	fails_label.text = "MAZE FAILS: %d" % maze_fails

func on_maze_timer_finished():
	if transitioning:
		return
	transitioning = true
	stop_maze_timer()
	maze_fails += 1
	update_wins_fails_labels()
	play_fail_sound()
	var next_scene = get_random_character_scene()
	if next_scene:
		current_character_scene = next_scene
		replace_player_scene(next_scene, grid_to_world(entrance_pos) + Vector2(0, -CELL_SIZE), true)
	generate_maze(false)
	reset_maze_timer()
	queue_redraw()
	transitioning = false

func grid_to_world(pos: Vector2) -> Vector2:
	return Vector2(pos.x * CELL_SIZE + CELL_SIZE / 2.0, pos.y * CELL_SIZE + CELL_SIZE / 2.0)

func world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(
		clamp(int(pos.x / CELL_SIZE), 0, COLS - 1),
		clamp(int(pos.y / CELL_SIZE), 0, ROWS - 1))

func _draw():
	for r in range(ROWS):
		for c in range(COLS):
			var color = WALL_COLOR if maze[r][c] == 1 else PATH_COLOR
			var rect = Rect2(c * CELL_SIZE, r * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			draw_rect(rect, color)
	if show_line and solution_path.size() > 1:
		draw_polyline(solution_path, Color.BLACK, 1.0, false)
