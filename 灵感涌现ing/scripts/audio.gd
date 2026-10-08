extends Node
## Small original synthesized UI tones. No copyrighted recordings.
var enabled := true
var players: Array[AudioStreamPlayer] = []

func play(kind: String = "tap") -> void:
	if not enabled:
		return
	var frequencies: Array = [440.0]
	if kind == "learn":
		frequencies = [523.25, 659.25, 783.99]
	elif kind == "finish":
		frequencies = [392.0, 523.25, 659.25, 783.99]
	elif kind == "turn":
		frequencies = [392.0, 523.25]
	var rate := 22050
	var note_duration := 0.1 if kind == "tap" else 0.15
	var samples := int(rate * note_duration * frequencies.size())
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	for i in range(samples):
		var note := mini(frequencies.size() - 1, int(float(i) / (rate * note_duration)))
		var t := float(i) / rate - note * note_duration
		var envelope := minf(t * 90.0, 1.0) * exp(-t * 25.0)
		var value := int(sin(TAU * frequencies[note] * t) * envelope * 4600.0)
		bytes.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = stream
	player.volume_db = -10.0
	player.finished.connect(player.queue_free)
	player.play()
