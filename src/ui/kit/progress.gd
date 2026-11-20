class_name FcProgress
extends ProgressBar
## A progress bar (collection completion, season points, XP). Variants: ACCENT (default), SUCCESS, DANGER, GOLD.
## set_progress() jumps to a value; set_progress_animated() fills smoothly (instant when motion is reduced).

enum Variant { ACCENT, SUCCESS, DANGER, GOLD }

const VARIATIONS := {Variant.ACCENT: "", Variant.SUCCESS: "SuccessProgress", Variant.DANGER: "DangerProgress", Variant.GOLD: "GoldProgress"}

var variant: Variant = Variant.ACCENT:
	set(v):
		variant = v
		theme_type_variation = VARIATIONS[v]


func _init(bar_variant: Variant = Variant.ACCENT) -> void:
	show_percentage = false
	custom_minimum_size = Vector2(120, 12)
	variant = bar_variant


func set_progress(value: float, maximum: float) -> void:
	max_value = maxf(1.0, maximum)
	self.value = clampf(value, 0.0, max_value)


func set_progress_animated(value: float, maximum: float) -> void:
	max_value = maxf(1.0, maximum)
	FcMotion.tween_property(self, "value", clampf(value, 0.0, max_value), FcUiTokens.DUR_SLOW * 2.0)
