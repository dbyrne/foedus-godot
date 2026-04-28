## Tiny procedural-tone synth for UI feedback.
##
## Avoids shipping audio files: each "sound" is a queue of (freq, duration)
## notes that the manager renders into a streaming AudioStream by pushing
## sine-wave samples in _process(). One generator/player owned by the node;
## monophonic but plenty for click/submit/advance/game-over.
##
## Public API:
##   click(), submit(), advance(), game_over_won(), game_over_lost()
class_name SoundManager
extends Node

const MIX_RATE: float = 44100.0
const ATTACK_S: float = 0.005
const RELEASE_S: float = 0.030

var generator: AudioStreamGenerator
var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback

# Pending notes; each is [freq_hz, duration_s, amp].
var _queue: Array = []
# Current note in flight.
var _cur_freq: float = 0.0
var _cur_amp: float = 0.0
var _cur_total_frames: int = 0
var _cur_remaining: int = 0
var _cur_played: int = 0


func _ready() -> void:
	generator = AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.5
	player = AudioStreamPlayer.new()
	player.stream = generator
	player.volume_db = -8.0
	add_child(player)
	player.play()
	playback = player.get_stream_playback()


func _process(_delta: float) -> void:
	if playback == null:
		return
	var available: int = playback.get_frames_available()
	for i in range(available):
		if _cur_remaining <= 0:
			# Pull the next note from the queue if any.
			if not _queue.is_empty():
				var n: Array = _queue.pop_front()
				_cur_freq = float(n[0])
				_cur_total_frames = int(float(n[1]) * MIX_RATE)
				_cur_remaining = _cur_total_frames
				_cur_played = 0
				_cur_amp = float(n[2])
			else:
				playback.push_frame(Vector2.ZERO)
				continue
		var t: float = float(_cur_played) / MIX_RATE
		var dur: float = float(_cur_total_frames) / MIX_RATE
		var env: float = 1.0
		if t < ATTACK_S:
			env = t / ATTACK_S
		elif t > dur - RELEASE_S:
			env = max(0.0, (dur - t) / RELEASE_S)
		var s: float = sin(2.0 * PI * _cur_freq * t) * _cur_amp * env
		playback.push_frame(Vector2(s, s))
		_cur_remaining -= 1
		_cur_played += 1


# --- public API: queue notes ---


func play_tone(freq_hz: float, duration_s: float = 0.08, amp: float = 0.25) -> void:
	_queue.append([freq_hz, duration_s, amp])


func play_arpeggio(freqs: Array, note_duration: float = 0.08,
		amp: float = 0.25) -> void:
	for f in freqs:
		play_tone(float(f), note_duration, amp)


# --- common UI sounds ---


func click() -> void:
	play_tone(880.0, 0.04, 0.18)


func submit() -> void:
	play_arpeggio([523.25, 659.25], 0.05, 0.22)


func advance() -> void:
	play_arpeggio([392.0, 523.25, 659.25], 0.06, 0.22)


func game_over_won() -> void:
	play_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.10, 0.28)


func game_over_lost() -> void:
	play_arpeggio([392.0, 329.63, 261.63], 0.16, 0.22)
