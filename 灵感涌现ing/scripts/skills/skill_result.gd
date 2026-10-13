extends RefCounted
var modifiers: Array = []
var temporary: Array = []
## 特殊结果由执行器统一提交，效果脚本仍只操作阶段快照。
var outcomes: Array = []

func add(path: Array, operation: String, amount: float) -> void:
	modifiers.append({"path": path, "operation": operation, "amount": amount})
