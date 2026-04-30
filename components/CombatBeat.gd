extends Node2D
class_name CombatBeat
##
## Flashbulb burst rendered at a contested hex during a clash. Used by
## CouncilResolution to mark dislodgement moments in the playback Tween.
##
## Lifecycle: create, play() animates a quick burst (radial expansion +
## fade), then queue_free()s itself when done.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

@export var burst_color: Color = Tokens.BLOOD :
	set(value): burst_color = value; queue_redraw()

@export_range(0.0, 1.0, 0.01) var t: float = 0.0 :
	set(value): t = clamp(value, 0.0, 1.0); queue_redraw()


func play(duration: float = 0.6) -> void:
	## Tween from t=0 → t=1 over `duration` seconds, then free.
	var tween := create_tween()
	tween.tween_property(self, "t", 1.0, duration).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(queue_free)


func _draw() -> void:
	if t <= 0.0 or t >= 1.0:
		return
	# Outer ring: expands and fades.
	var radius_outer: float = lerp(8.0, 48.0, t)
	var alpha_outer: float = lerp(0.9, 0.0, t)
	draw_arc(Vector2.ZERO, radius_outer, 0, TAU, 32,
		Color(burst_color.r, burst_color.g, burst_color.b, alpha_outer), 3.0)
	# Inner flash: bright early, fades fast.
	var radius_inner: float = lerp(4.0, 22.0, t)
	var alpha_inner: float = lerp(0.95, 0.0, t * 1.5)
	if alpha_inner > 0.0:
		draw_circle(Vector2.ZERO, radius_inner,
			Color(Tokens.CANDLE.r, Tokens.CANDLE.g, Tokens.CANDLE.b, alpha_inner))
	# Crater dot: stays for the second half.
	if t > 0.5:
		var crater_alpha: float = lerp(0.0, 0.6, (t - 0.5) * 2.0)
		draw_circle(Vector2.ZERO, 6.0,
			Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, crater_alpha))
