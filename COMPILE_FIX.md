# 编译错误修复说明

## 错误描述
```
/Users/zengchanghuan/Desktop/workspace/swift_project/vision_demo/vision_demo/CameraViewController.swift:963:13: 
Expected expression
            , .calibration:
            ^
```

## 问题原因
在 Swift 的 switch-case 语句中，不能直接在 case 标签内使用条件编译指令（`#if DEBUG`）来拼接多个 case 值。

**错误的写法：**
```swift
switch currentMode {
case .handGesture:
    #if DEBUG
    , .calibration:    // ❌ 语法错误
    #endif
    // code...
```

## 解决方案
将条件编译指令放在整个 case 语句外层，根据编译条件选择不同的 case 组合。

**正确的写法：**
```swift
switch currentMode {
#if DEBUG
case .handGesture, .calibration:    // ✅ Debug 模式：两个 case
#else
case .handGesture:                  // ✅ Release 模式：一个 case
#endif
    // code...
```

## 修复位置
- **文件**: `vision_demo/CameraViewController.swift`
- **行数**: 第960-965行
- **方法**: `processSampleBuffer(_:)`

## 验证
修复后，代码应该可以在 Debug 和 Release 模式下正常编译：
- **Debug 模式**: `.handGesture` 和 `.calibration` 两个 case 都会执行相同的代码
- **Release 模式**: 只有 `.handGesture` case 可用（`.calibration` 不存在）

## 其他相关修改
这是条件编译在整个项目中的一致应用方式，确保：
1. Debug 模式显示 4 个 Tab（手势识别 / 人脸跟随 / 目标跟踪 / 统计标定）
2. Release 模式只显示 3 个 Tab（隐藏统计标定）
3. 所有调试UI只在 Debug 模式下可见

## 编译命令
在 Xcode 中直接按 Cmd+B 编译，或在终端运行：
```bash
xcodebuild -project vision_demo.xcodeproj -scheme vision_demo build
```

修复完成！✅
