extends RefCounted
## 只在生成界面文字时向下取整，不回写模型或报告。

static func text(value: float, signed_value: bool = false) -> String:
	var integer := floori(value)
	return ("%+d" if signed_value else "%d") % integer
