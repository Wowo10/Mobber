extends CanvasLayer

const GAME_SCENE = "res://scenes/game/game.tscn"

func _ready() -> void:
	# Null any leftover peer from a previous game so SceneMultiplayer is clean.
	# We do this here rather than in game.gd _leave_game so the scene change
	# happens while the peer is still live — letting SceneMultiplayer disconnect
	# its tree_exited hooks on tracked nodes before they exit the tree.
	multiplayer.multiplayer_peer = null

func _on_host_pressed() -> void:
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
	var ip = %IPInput.text.strip_edges()
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

func _on_connected() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_failed() -> void:
	$VBox/StatusLabel.text = "Connection failed."
	multiplayer.multiplayer_peer = null
