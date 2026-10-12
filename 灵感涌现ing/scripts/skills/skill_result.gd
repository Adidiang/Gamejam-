extends RefCounted
var modifiers: Array = []
var temporary: Array = []

func add(path: Array, operation: String, amount: float) -> void:
	modifiers.append({"path": path, "operation": operation, "amount": amount})
