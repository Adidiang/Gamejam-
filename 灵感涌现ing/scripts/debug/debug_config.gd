extends RefCounted
## 调试功能的唯一总开关：打包正式版时把 ENABLED 改成 false，
## 调试按钮、调试面板与全部调试操作一起失效，不需要改动其他任何文件。
## 用 static var 而不是 const，是为了让测试可以在同一进程里临时关掉它，验证正式版路径。
static var ENABLED := true
## 正式版额外保险：导出 Release 模板后，即使忘记关闭 ENABLED，调试功能也不会生效。
## OS.is_debug_build() 在编辑器与开发版模板里为 true，在 Release 模板里为 false。
const ALLOW_IN_RELEASE := false
