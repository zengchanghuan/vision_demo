# Vision 手势识别 Demo

纯 Swift Vision 手势识别 Demo，使用 UIKit。

## 功能

- ✌️ V 手势识别
- 👌 OK 手势识别
- 🖐 张开手掌识别

## 文件结构

- `HandGestureType.swift` - 手势枚举
- `HandGestureClassifier.swift` - 基于 Vision 关键点的规则分类器
- `CameraViewController.swift` - 相机 + Vision 推理 + UI

## 使用说明

1. 在 Xcode 中新建 iOS App 工程（Interface: Storyboard）
2. 将这三个 Swift 文件添加到工程中
3. 在 `Info.plist` 中添加相机权限：

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>用于识别手势</string>
   ```

4. 在 Storyboard 中将默认 ViewController 的 Class 设置为 `CameraViewController`
5. 在真机上运行（模拟器没有摄像头）

## 系统要求

- iOS 15.0+
- Xcode 15+

