extends CanvasLayer

const GAME_SCENE = "res://scenes/game/game.tscn"

var _is_web: bool = false

func _ready() -> void:
	multiplayer.multiplayer_peer = null
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
		var err := peer.create_server(Constants.NET_PORT, 2)
		if err != OK:
			$VBox/StatusLabel.text = "Failed to host: %s" % error_string(err)
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer_joined)

func _on_peer_joined(_id: int) -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

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
	%CodeDisplay.text = "Room Code: %s" % code
	%CodeDisplay.visible = true
	$VBox/StatusLabel.text = "Waiting for opponent..."

func _on_game_ready() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_signaling_error(msg: String) -> void:
	$VBox/StatusLabel.text = msg
	%CodeDisplay.visible = false

func _on_connected() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_failed() -> void:
	$VBox/StatusLabel.text = "Connection failed."
	multiplayer.multiplayer_peer = null
