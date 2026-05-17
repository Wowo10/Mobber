extends Node

signal lobby_created(code: String)
signal game_ready()
signal error(msg: String)

const _CMD_JOIN      = 0
const _CMD_ID        = 1
const _CMD_PEER_CONNECT    = 2
const _CMD_PEER_DISCONNECT = 3
const _CMD_OFFER     = 4
const _CMD_ANSWER    = 5
const _CMD_CANDIDATE = 6
const _CMD_SEAL      = 7

const _ICE_SERVERS = [{"urls": ["stun:stun.l.google.com:19302"]}]

var _ws = null
var _mp = null
var _conns: Dictionary = {}
var _is_host: bool = false
var _lobby_code: String = ""
var _joined: bool = false
var _mp_assigned: bool = false


func _ready() -> void:
	set_process(false)


func host(url: String) -> void:
	_is_host = true
	_lobby_code = ""
	_open(url)


func join(url: String, code: String) -> void:
	_is_host = false
	_lobby_code = code
	_open(url)


func _open(url: String) -> void:
	_ws = WebSocketPeer.new()
	_mp = WebRTCMultiplayerPeer.new()
	_conns.clear()
	_joined = false
	_mp_assigned = false
	var err: int = _ws.connect_to_url(url)
	if err != OK:
		error.emit("Cannot reach signaling server: %s" % error_string(err))
		return
	set_process(true)


func _process(_delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _joined:
				_send({type = _CMD_JOIN, id = 1, data = _lobby_code})
				_joined = true
			while _ws.get_available_packet_count() > 0:
				var txt: String = _ws.get_packet().get_string_from_utf8()
				var msg = JSON.parse_string(txt)
				if msg is Dictionary:
					_on_msg(msg)
		WebSocketPeer.STATE_CLOSED:
			if not _mp_assigned:
				set_process(false)
				error.emit("Signaling server disconnected")

	if not _mp_assigned and _conns.size() > 0:
		_mp.poll()
		var all_connected := true
		for conn in _conns.values():
			if conn.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED:
				all_connected = false
				break
		if all_connected:
			_mp_assigned = true
			multiplayer.multiplayer_peer = _mp
			if _is_host:
				_send({type = _CMD_SEAL, id = 0, data = ""})
			game_ready.emit()
			set_process(false)


func _on_msg(msg: Dictionary) -> void:
	var type: int = msg.get("type", -1)
	var id: int   = msg.get("id", 0)
	var data: String = msg.get("data", "")
	match type:
		_CMD_ID:
			if _is_host:
				_mp.create_server()
			else:
				_mp.create_client(id)
		_CMD_JOIN:
			if _is_host:
				lobby_created.emit(data)
		_CMD_PEER_CONNECT:
			_add_peer(id)
		_CMD_PEER_DISCONNECT:
			if _conns.has(id):
				_conns[id].close()
				_conns.erase(id)
				_mp.remove_peer(id)
		_CMD_OFFER:
			if _conns.has(id):
				_conns[id].set_remote_description("offer", data)
		_CMD_ANSWER:
			if _conns.has(id):
				_conns[id].set_remote_description("answer", data)
		_CMD_CANDIDATE:
			if _conns.has(id):
				var parts := data.split("\n", false, 2)
				if parts.size() == 3:
					_conns[id].add_ice_candidate(parts[0], int(parts[1]), parts[2])


func _add_peer(peer_id: int) -> void:
	if _conns.has(peer_id):
		return
	var conn = WebRTCPeerConnection.new()
	conn.initialize({"iceServers": _ICE_SERVERS})
	_conns[peer_id] = conn
	_mp.add_peer(conn, peer_id)

	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		var cmd := _CMD_OFFER if type == "offer" else _CMD_ANSWER
		_send({type = cmd, id = peer_id, data = sdp})
	)
	conn.ice_candidate_created.connect(func(media: String, index: int, sdp_name: String):
		_send({type = _CMD_CANDIDATE, id = peer_id, data = "%s\n%d\n%s" % [media, index, sdp_name]})
	)

	if _is_host:
		conn.create_offer()


func _send(msg: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))
