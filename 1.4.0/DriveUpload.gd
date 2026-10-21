extends Node
## Personal-device bridge. Configure locally; never commit an upload key.
const MAX_BYTES := 15 * 1024 * 1024
var endpoint := ""
var upload_key := ""
var pending: Array[String] = []
var active := false

func _ready() -> void:
	var config := ConfigFile.new()
	var path := "user://drive_upload.cfg" if FileAccess.file_exists("user://drive_upload.cfg") else "res://drive_upload.cfg"
	if config.load(path) == OK:
		endpoint = str(config.get_value("drive", "endpoint", "")).strip_edges()
		upload_key = str(config.get_value("drive", "upload_key", "")).strip_edges()

func is_configured() -> bool:
	return endpoint.begins_with("https://script.google.com/macros/s/") and endpoint.ends_with("/exec") and upload_key.length() >= 32

func enqueue(path: String) -> void:
	if not is_configured(): return
	if not pending.has(path): pending.append(path)
	if not active: _drain()

func _drain() -> void:
	active = true
	while not pending.is_empty():
		var path: String = pending.pop_front()
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_report(false, "Drive upload failed; local export could not be read.")
			continue
		if file.get_length() > MAX_BYTES:
			file.close()
			_report(false, "Saved locally; STL exceeds the 15 MB Drive upload limit.")
			continue
		var bytes := file.get_buffer(file.get_length())
		var read_error := file.get_error()
		file.close()
		if read_error != OK:
			_report(false, "Drive upload failed; local export could not be read.")
			continue
		var payload := JSON.stringify({"key": upload_key, "name": path.get_file(), "data": Marshalls.raw_to_base64(bytes)})
		var request := HTTPRequest.new()
		request.timeout = 90.0
		# Handle the Apps Script response redirect explicitly: Godot keeps POST
		# on HTTP 302, but Google's content endpoint requires GET.
		request.max_redirects = 0
		request.body_size_limit = 64 * 1024
		add_child(request)
		var error := request.request(endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)
		if error != OK:
			request.queue_free()
			_report(false, "Saved locally; Drive upload could not start. Check Wi-Fi and export again.")
			continue
		var response: Array = await request.request_completed
		for _redirect in range(5):
			if response[1] not in [301, 302, 303]: break
			var location := ""
			for header in response[2]:
				if String(header).to_lower().begins_with("location:"):
					location = String(header).substr(9).strip_edges()
			# Never resend the key/body to a redirect. Only read Google's result.
			if not location.begins_with("https://script.googleusercontent.com/"): break
			error = request.request(location, [], HTTPClient.METHOD_GET)
			if error != OK: break
			response = await request.request_completed
		request.queue_free()
		var parser := JSON.new()
		var parsed := parser.parse((response[3] as PackedByteArray).get_string_from_utf8())
		var reply: Variant = parser.data if parsed == OK else null
		if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200 and reply is Dictionary and reply.get("ok", false) == true and reply.get("name", "") == path.get_file():
			_report(true, "Uploaded to Google Drive · " + path.get_file())
		else:
			_report(false, "Saved locally; Drive upload failed. Check Wi-Fi/setup and export again.")
	active = false

func _report(success: bool, message: String) -> void:
	# Do not log response bodies, configuration, or the upload credential.
	print(message)
	SignalBus.export_finished.emit(success, message)
