extends CanvasLayer

const GAME_SCENE = "res://scenes/game/game.tscn"
const GAME_ROOM_SCENE = "res://scenes/ui/game_room.tscn"
const TRYOUT_SCENE = "res://scenes/game/tryout.tscn"

func _ready() -> void:
	multiplayer.multiplayer_peer = null

	var saved_name := _load_name()
	PlayerPrefs.player_name = saved_name
	%NameInput.text = saved_name
	PlayerPrefs.archetype = _load_archetype()
	PlayerPrefs.control_scheme = _load_scheme()

	var scheme_sel := %SchemeSelect
	scheme_sel.add_item("Keyboard (Space/Shift)", PlayerPrefs.SCHEME_KEYBOARD)
	scheme_sel.add_item("Mouse (LMB/RMB)", PlayerPrefs.SCHEME_MOUSE)
	scheme_sel.add_item("Gamepad (Twin-stick)", PlayerPrefs.SCHEME_PAD)
	scheme_sel.select(PlayerPrefs.control_scheme)
	scheme_sel.item_selected.connect(func(_i: int) -> void:
		PlayerPrefs.control_scheme = scheme_sel.get_selected_id()
		_save_scheme(PlayerPrefs.control_scheme))

	var arch_sel := %ArchetypeSelect
	for name in Constants.ARCHETYPE_NAMES:
		arch_sel.add_item(name)
	arch_sel.select(PlayerPrefs.archetype)
	arch_sel.item_selected.connect(func(idx: int) -> void:
		PlayerPrefs.archetype = idx
		_save_archetype(idx))

	WebRTCSignaling.lobby_created.connect(_on_lobby_created)
	WebRTCSignaling.game_ready.connect(_on_game_ready)
	WebRTCSignaling.error.connect(_on_signaling_error)

func _exit_tree() -> void:
	if WebRTCSignaling.lobby_created.is_connected(_on_lobby_created):
		WebRTCSignaling.lobby_created.disconnect(_on_lobby_created)
	if WebRTCSignaling.game_ready.is_connected(_on_game_ready):
		WebRTCSignaling.game_ready.disconnect(_on_game_ready)
	if WebRTCSignaling.error.is_connected(_on_signaling_error):
		WebRTCSignaling.error.disconnect(_on_signaling_error)

func _load_name() -> String:
	if OS.get_name() == "Web":
		return str(JavaScriptBridge.eval("localStorage.getItem('mobber_name') || ''"))
	var cfg := ConfigFile.new()
	if cfg.load("user://prefs.cfg") == OK:
		return cfg.get_value("player", "name", "")
	return ""

func _load_archetype() -> int:
	if OS.get_name() == "Web":
		var val: String = str(JavaScriptBridge.eval("localStorage.getItem('mobber_arch') || '0'"))
		return val.to_int()
	var cfg := ConfigFile.new()
	if cfg.load("user://prefs.cfg") == OK:
		return cfg.get_value("player", "archetype", 0)
	return 0

func _load_scheme() -> int:
	if OS.get_name() == "Web":
		var val: String = str(JavaScriptBridge.eval("localStorage.getItem('mobber_scheme') || '0'"))
		return val.to_int()
	var cfg := ConfigFile.new()
	if cfg.load("user://prefs.cfg") == OK:
		return cfg.get_value("player", "control_scheme", 0)
	return 0

func _save_archetype(arch: int) -> void:
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("localStorage.setItem('mobber_arch','%d')" % arch)
	else:
		var cfg := ConfigFile.new()
		cfg.load("user://prefs.cfg")
		cfg.set_value("player", "archetype", arch)
		cfg.save("user://prefs.cfg")

func _save_scheme(scheme: int) -> void:
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("localStorage.setItem('mobber_scheme','%d')" % scheme)
	else:
		var cfg := ConfigFile.new()
		cfg.load("user://prefs.cfg")
		cfg.set_value("player", "control_scheme", scheme)
		cfg.save("user://prefs.cfg")

func _on_name_changed(new_text: String) -> void:
	PlayerPrefs.player_name = new_text
	if OS.get_name() == "Web":
		var safe := new_text.replace("\\", "\\\\").replace("'", "\\'")
		JavaScriptBridge.eval("localStorage.setItem('mobber_name','%s')" % safe)
	else:
		var cfg := ConfigFile.new()
		cfg.load("user://prefs.cfg")
		cfg.set_value("player", "name", new_text)
		cfg.save("user://prefs.cfg")

func _on_host_pressed() -> void:
	$VBox/StatusLabel.text = "Creating room..."
	WebRTCSignaling.host(Constants.SIGNALING_URL)

func _on_join_pressed() -> void:
	var code: String
	if OS.get_name() == "Web":
		code = str(JavaScriptBridge.eval("window.prompt('Enter room code:') || ''"))
	else:
		code = DisplayServer.clipboard_get()
	code = code.strip_edges()
	if code.is_empty():
		return
	$VBox/StatusLabel.text = "Joining room %s..." % code
	WebRTCSignaling.join(Constants.SIGNALING_URL, code)

func _on_lobby_created(code: String) -> void:
	PlayerPrefs.room_code = code
	get_tree().change_scene_to_file(GAME_ROOM_SCENE)

func _on_game_ready() -> void:
	get_tree().change_scene_to_file(GAME_ROOM_SCENE)

func _on_signaling_error(msg: String) -> void:
	$VBox/StatusLabel.text = msg

func _on_try_archetype_pressed() -> void:
	get_tree().change_scene_to_file(TRYOUT_SCENE)

