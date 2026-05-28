extends CanvasLayer

const GAME_SCENE = "res://scenes/game/game.tscn"
const GAME_ROOM_SCENE = "res://scenes/ui/game_room.tscn"

var _is_web: bool = false
var _room_code: String = ""
var _paste_cb: JavaScriptObject

func _ready() -> void:
	multiplayer.multiplayer_peer = null
	var sel := $VBox/ArchetypeSelect
	sel.add_item("Knight", 0)
	sel.add_item("Pirate", 1)
	sel.select(PlayerPrefs.archetype)
	sel.item_selected.connect(func(i: int) -> void: PlayerPrefs.archetype = i)

	var win_opts := [50, 75, 100, 120]
	var wsel := %WinCountSelect
	for v in win_opts:
		wsel.add_item(str(v), v)
	var default_idx := win_opts.find(PlayerPrefs.mob_win_count)
	wsel.select(default_idx if default_idx >= 0 else win_opts.find(50))
	wsel.item_selected.connect(func(_i: int) -> void: PlayerPrefs.mob_win_count = wsel.get_selected_id())
	_is_web = OS.get_name() == "Web" or Constants.FORCE_WEBRTC
	if _is_web:
		%IPInput.placeholder_text = "Room Code"
		WebRTCSignaling.lobby_created.connect(_on_lobby_created)
		WebRTCSignaling.game_ready.connect(_on_game_ready)
		WebRTCSignaling.error.connect(_on_signaling_error)

func _exit_tree() -> void:
	if _is_web:
		if WebRTCSignaling.lobby_created.is_connected(_on_lobby_created):
			WebRTCSignaling.lobby_created.disconnect(_on_lobby_created)
		if WebRTCSignaling.game_ready.is_connected(_on_game_ready):
			WebRTCSignaling.game_ready.disconnect(_on_game_ready)
		if WebRTCSignaling.error.is_connected(_on_signaling_error):
			WebRTCSignaling.error.disconnect(_on_signaling_error)

func _on_host_pressed() -> void:
	if _is_web:
		$VBox/StatusLabel.text = "Creating room..."
		WebRTCSignaling.host(Constants.SIGNALING_URL)
	else:
		$VBox/StatusLabel.text = "Hosting..."
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(Constants.NET_PORT, Constants.MAX_PLAYERS)
		if err != OK:
			$VBox/StatusLabel.text = "Failed to host: %s" % error_string(err)
			return
		multiplayer.multiplayer_peer = peer
		get_tree().change_scene_to_file(GAME_ROOM_SCENE)

func _on_paste_pressed() -> void:
	if _is_web:
		_paste_cb = JavaScriptBridge.create_callback(func(args: Array) -> void:
			var text: String = str(args[0]) if args.size() > 0 else ""
			if not text.is_empty():
				%IPInput.text = text
		)
		JavaScriptBridge.get_interface("window")["_gdPasteCb"] = _paste_cb
		JavaScriptBridge.eval("navigator.clipboard.readText().then(function(t){window._gdPasteCb(t);}).catch(function(){var t=window.prompt('Paste room code:','');if(t)window._gdPasteCb(t);})")
	else:
		%IPInput.text = DisplayServer.clipboard_get()

func _on_join_pressed() -> void:
	if _is_web:
		var code: String = %IPInput.text.strip_edges()
		if code.is_empty():
			$VBox/StatusLabel.text = "Enter a room code."
			return
		$VBox/StatusLabel.text = "Joining room %s..." % code
		WebRTCSignaling.join(Constants.SIGNALING_URL, code)
	else:
		var ip: String = %IPInput.text.strip_edges()
		if ip.is_empty():
			ip = "127.0.0.1"
		$VBox/StatusLabel.text = "Connecting to %s..." % ip
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_client(ip, Constants.NET_PORT)
		if err != OK:
			$VBox/StatusLabel.text = "Failed to connect: %s" % error_string(err)
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_failed)

func _on_lobby_created(code: String) -> void:
	PlayerPrefs.room_code = code
	get_tree().change_scene_to_file(GAME_ROOM_SCENE)

func _on_code_display_pressed() -> void:
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("navigator.clipboard.writeText('%s').catch(()=>{})" % _room_code)
	else:
		DisplayServer.clipboard_set(_room_code)
	$VBox/StatusLabel.text = "Copied!"

func _on_game_ready() -> void:
	get_tree().change_scene_to_file(GAME_ROOM_SCENE)

func _on_signaling_error(msg: String) -> void:
	$VBox/StatusLabel.text = msg
	%CodeDisplay.visible = false

func _on_connected() -> void:
	get_tree().change_scene_to_file(GAME_ROOM_SCENE)

func _on_failed() -> void:
	$VBox/StatusLabel.text = "Connection failed."
	multiplayer.multiplayer_peer = null
