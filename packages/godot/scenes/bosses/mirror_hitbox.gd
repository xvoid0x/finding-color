extends StaticBody2D
## MirrorHitbox — Collision body for the Mirror Boss.
## Guardian's AttackArea calls take_damage(damage, aim_dir) on bodies
## in the "enemies" group. Forwards to parent MirrorBoss._receive_hit().

func take_damage(damage: float, _aim_dir: Vector2) -> void:
	var boss: Node2D = get_parent() as Node2D
	if boss and boss.has_method("_receive_hit"):
		boss._receive_hit(damage)
