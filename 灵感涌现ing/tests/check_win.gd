extends SceneTree
const Model = preload("res://scripts/game_model.gd")

func _init() -> void:
	if Model.DEFINITIONS.all(func(member: Dictionary): return member.stats.all(func(value: float): return value == 0)):
		print("WIN_ROUTE_CHECK: skipped; character table contains only zero-ability placeholders.")
		quit(0)
		return
	# Bounded search verifies that the one-year prototype actually has a legal winning route.
	var beam: Array = [{"state": Model.begin(Model.fresh(), "胜利路线验证", 1, 1), "route": []}]
	for month in range(1, 13):
		var candidates: Array = []
		for entry in beam:
			var base: Dictionary = entry.state
			for id in range(4):
				base = Model.learn(base, id)
			for role in [0, 3]:
				var assigned: Dictionary = Model.assign(base, 0, role)
				for pair in [[0, 1], [0, 5], [1, 2], [1, 0], [2, 3], [3, 4], [2, 0], [3, 0]]:
					var result: Dictionary = Model.resolve(assigned, pair[0], pair[1], month)
					var state: Dictionary = Model.acknowledge(result.state)
					var score: Dictionary = result.report.score
					var rank: float = float(score.total)
					if month < 12:
						# Relationship growth pays back later.
						for member in state.members:
							rank += float(member.affinity) * 0.014 * (12 - month)
					elif score.best:
						rank += 100.0
					var route: Array = entry.route.duplicate()
					route.append([role, pair[0], pair[1]])
					candidates.append({"state": state, "route": route, "rank": rank})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rank > b.rank)
		beam = candidates.slice(0, mini(80, candidates.size()))
	var winner: Dictionary = beam[0]
	var final_score: Dictionary = winner.state.report.score
	print("WIN_ROUTE_CHECK: score=%.2f, bugs=%.2f, best=%s" % [final_score.total, winner.state.work.b, str(final_score.best)])
	print("Each route entry: [A role, action member, action ID] ", winner.route)
	quit(0 if final_score.best else 1)
