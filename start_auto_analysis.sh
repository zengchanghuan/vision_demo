#!/bin/bash
#
# 🚀 一键启动：手势识别App + 自动监控分析系统（已修复安装错误）
#
# 功能：
# 1. 构建并启动iOS App
# 2. 自动启动监控脚本
# 3. 实时分析手势日志
# 4. 自动打开分析报告
#

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 项目路径
PROJECT_DIR="$HOME/Desktop/workspace/swift_project/vision_demo"
XCODE_PROJECT="$PROJECT_DIR/vision_demo.xcodeproj"
SCHEME="vision_demo"
DEVICE_ID="00008101-001574E10182001E"  # 您的设备ID
BUILD_OUTPUT="$PROJECT_DIR/build"  # 指定构建输出目录

# 脚本路径
MONITOR_SCRIPT="$PROJECT_DIR/tools/watch_live.py"
VENV_PATH="$HOME/.cursor/worktrees/vision_demo/vwn/venv/bin/activate"

echo ""
echo "════════════════════════════════════════════════════════"
echo -e "${BLUE}🚀 自动启动：手势识别App + 实时监控分析${NC}"
echo "════════════════════════════════════════════════════════"
echo ""

# 检查项目目录
if [ ! -d "$PROJECT_DIR" ]; then
    echo -e "${RED}❌ 项目目录不存在: $PROJECT_DIR${NC}"
    exit 1
fi

cd "$PROJECT_DIR"

# 步骤1: 检查监控脚本是否已在运行
echo -e "${YELLOW}📋 步骤1/4: 检查现有监控进程...${NC}"
EXISTING_PID=$(ps aux | grep "watch_live.py" | grep -v grep | awk '{print $2}' || true)

if [ -n "$EXISTING_PID" ]; then
    echo -e "${GREEN}   ✓ 监控脚本已在运行 (PID: $EXISTING_PID)${NC}"
    echo -e "${YELLOW}   是否要停止并重启? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "   停止现有监控进程..."
        kill $EXISTING_PID 2>/dev/null || true
        sleep 2
    else
        echo "   保持现有监控进程运行"
        SKIP_MONITOR=1
    fi
else
    echo "   ✓ 没有运行中的监控进程"
fi

# 步骤2: 构建App
echo ""
echo -e "${YELLOW}📋 步骤2/4: 构建App到真机...${NC}"
echo "   项目: $XCODE_PROJECT"
echo "   Scheme: $SCHEME"
echo "   设备: $DEVICE_ID"
echo "   构建输出: $BUILD_OUTPUT"
echo ""

# 清理旧的构建输出
rm -rf "$BUILD_OUTPUT"

# 使用 -derivedDataPath 指定构建输出路径
xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS,id=$DEVICE_ID" \
    -derivedDataPath "$BUILD_OUTPUT" \
    -allowProvisioningUpdates \
    clean build \
    | grep -E "(Building|Succeeded|Failed|Error|note:)" || true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}❌ 构建失败${NC}"
    exit 1
fi

echo -e "${GREEN}   ✓ App构建成功${NC}"

# 步骤3: 安装到设备
echo ""
echo -e "${YELLOW}📋 步骤3/4: 安装App到设备...${NC}"

# 方法1: 使用指定的构建输出路径
APP_PATH="$BUILD_OUTPUT/Build/Products/Debug-iphoneos/vision_demo.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${YELLOW}   ⚠️  在指定路径未找到，尝试搜索...${NC}"
    # 方法2: 在DerivedData中搜索
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "vision_demo.app" -type d -mmin -5 2>/dev/null | head -1)
    
    if [ -z "$APP_PATH" ]; then
        echo -e "${YELLOW}   ⚠️  在DerivedData未找到，尝试在构建目录搜索...${NC}"
        # 方法3: 在构建目录中搜索
        APP_PATH=$(find "$BUILD_OUTPUT" -name "vision_demo.app" -type d 2>/dev/null | head -1)
    fi
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ 错误: 找不到编译后的 .app 文件${NC}"
    echo -e "${YELLOW}   已尝试以下位置:${NC}"
    echo "   1. $BUILD_OUTPUT/Build/Products/Debug-iphoneos/vision_demo.app"
    echo "   2. ~/Library/Developer/Xcode/DerivedData/vision_demo-*/Build/Products/Debug-iphoneos/vision_demo.app"
    echo "   3. 搜索 $BUILD_OUTPUT 目录"
    echo ""
    echo -e "${YELLOW}   提示: 请检查构建是否真正成功${NC}"
    exit 1
fi

echo -e "${GREEN}   ✓ 找到App: $APP_PATH${NC}"
echo "   文件大小: $(du -sh "$APP_PATH" | cut -f1)"

# 验证是否是有效的.app包
if [ ! -f "$APP_PATH/Info.plist" ]; then
    echo -e "${RED}❌ 错误: $APP_PATH 不是有效的.app包（缺少Info.plist）${NC}"
    exit 1
fi

echo "   正在安装到设备 $DEVICE_ID ..."
INSTALL_OUTPUT=$(xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1)
INSTALL_EXIT_CODE=$?

if [ $INSTALL_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}   ✓ App安装成功${NC}"
else
    echo -e "${YELLOW}   ⚠️  安装返回错误码 $INSTALL_EXIT_CODE${NC}"
    echo "   输出: $INSTALL_OUTPUT"
    
    # 检查是否是已安装的错误（这种情况可以继续）
    if echo "$INSTALL_OUTPUT" | grep -q "already installed"; then
        echo -e "${GREEN}   ✓ App已存在设备上，将使用现有版本${NC}"
    elif echo "$INSTALL_OUTPUT" | grep -q "3002"; then
        echo -e "${RED}❌ CoreDevice错误3002: 提供的文件类型不被识别${NC}"
        echo "   路径: $APP_PATH"
        exit 1
    else
        echo -e "${YELLOW}   ⚠️  继续尝试启动App...${NC}"
    fi
fi

# 步骤4: 启动App
echo ""
echo -e "${YELLOW}📋 步骤4/4: 启动App...${NC}"

LAUNCH_OUTPUT=$(xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --terminate-existing \
    xfs365.com.cn.vision-demo 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✓ App启动成功${NC}"
    echo "$LAUNCH_OUTPUT" | grep -i "launched" || echo "   $LAUNCH_OUTPUT"
else
    echo -e "${RED}❌ App启动失败${NC}"
    echo "   $LAUNCH_OUTPUT"
    exit 1
fi

sleep 3

# 步骤5: 启动监控脚本
if [ -z "$SKIP_MONITOR" ]; then
    echo ""
    echo -e "${YELLOW}📋 步骤5/5: 启动监控脚本...${NC}"
    echo "   监控: Xcode终端日志"
    echo "   输出: live_analysis/"
    echo "   触发: 每20条新日志"
    echo ""
    
    # 检查虚拟环境
    if [ ! -f "$VENV_PATH" ]; then
        echo -e "${RED}❌ 虚拟环境不存在: $VENV_PATH${NC}"
        exit 1
    fi
    
    # 检查监控脚本
    if [ ! -f "$MONITOR_SCRIPT" ]; then
        echo -e "${RED}❌ 监控脚本不存在: $MONITOR_SCRIPT${NC}"
        exit 1
    fi
    
    # 在后台启动监控
    source "$VENV_PATH"
    nohup python3 "$MONITOR_SCRIPT" > /tmp/gesture_monitor.log 2>&1 &
    MONITOR_PID=$!
    
    echo -e "${GREEN}   ✓ 监控脚本已启动 (PID: $MONITOR_PID)${NC}"
    sleep 2
    
    # 显示监控日志的前几行
    echo ""
    echo -e "${BLUE}📊 监控日志输出:${NC}"
    tail -5 /tmp/gesture_monitor.log 2>/dev/null || echo "   等待日志输出..."
else
    echo ""
    echo -e "${YELLOW}📋 步骤5/5: 跳过（监控已在运行）${NC}"
    MONITOR_PID=$(ps aux | grep "watch_live.py" | grep -v grep | awk '{print $2}')
fi

# 完成
echo ""
echo "════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ 启动完成！${NC}"
echo "════════════════════════════════════════════════════════"
echo ""
echo -e "${BLUE}📱 App状态:${NC}"
echo "   • App正在真机上运行"
echo "   • 日志正在自动写入"
echo "   • Bundle ID: xfs365.com.cn.vision-demo"
echo ""
echo -e "${BLUE}🔍 监控状态:${NC}"
echo "   • 监控脚本：运行中 (PID: $MONITOR_PID)"
echo "   • 检查频率：每秒一次"
echo "   • 分析触发：每20条新日志"
echo ""
echo -e "${BLUE}📊 查看结果:${NC}"
echo "   • 实时日志: tail -f /tmp/gesture_monitor.log"
echo "   • 分析报告: open live_analysis/"
echo "   • 最新报告: ./view_latest_report.sh"
echo ""
echo -e "${BLUE}🛑 停止系统:${NC}"
echo "   • 停止App: Ctrl+C 或 关闭Xcode控制台"
echo "   • 停止监控: kill $MONITOR_PID"
echo "   • 停止所有: ./stop_monitoring.sh"
echo ""
echo -e "${YELLOW}💡 提示: 现在在App中做手势，系统会自动分析！${NC}"
echo ""
