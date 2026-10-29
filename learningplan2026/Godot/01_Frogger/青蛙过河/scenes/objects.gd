extends Node2D

@export var growth_speed: float = 0.5

func _process(delta: float) -> void:
	scale += Vector2.ONE * growth_speed * delta
