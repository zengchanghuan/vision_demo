#!/bin/bash
# 测试分析脚本 - 使用test_gesture.log

PROJECT_DIR="$HOME/Desktop/workspace/swift_project/vision_demo"
VENV_PYTHON="$HOME/.cursor/worktrees/vision_demo/vwn/venv/bin/python3"
LOG_FILE="$PROJECT_DIR/test_gesture.log"
OUTPUT_DIR="$PROJECT_DIR/live_analysis"

cd "$PROJECT_DIR"

echo "🧪 测试分析脚本"
echo "==============="
echo "日志文件: $LOG_FILE"
echo "输出目录: $OUTPUT_DIR"
echo ""

# 检查日志文件
if [ ! -f "$LOG_FILE" ]; then
    echo "❌ 日志文件不存在: $LOG_FILE"
    exit 1
fi

LOG_LINES=$(wc -l < "$LOG_FILE")
DEBUG_LINES=$(grep -c "HandGestureDebug" "$LOG_FILE" 2>/dev/null || echo "0")

echo "📊 日志统计:"
echo "   总行数: $LOG_LINES"
echo "   调试行数: $DEBUG_LINES"
echo ""

if [ "$DEBUG_LINES" -eq 0 ]; then
    echo "⚠️  日志文件中没有 [HandGestureDebug] 行"
    echo "   请确保日志文件格式正确"
    exit 1
fi

# 使用虚拟环境中的Python运行分析
echo "🔄 运行分析..."
"$VENV_PYTHON" analyze_gesture_log.py \
    --log-file "$LOG_FILE" \
    --gt-gesture V \
    --output-dir "$OUTPUT_DIR"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 分析完成！"
    echo ""
    echo "📊 查看报告:"
    echo "   ./view_latest_report.sh"
    echo ""
    echo "📂 分析结果目录:"
    ls -lh "$OUTPUT_DIR"/*.md "$OUTPUT_DIR"/*.csv 2>/dev/null | tail -5
else
    echo ""
    echo "❌ 分析失败，请检查错误信息"
    exit 1
fi
