#!/bin/bash
# 查看最新的分析报告

PROJECT_DIR="$HOME/Desktop/workspace/swift_project/vision_demo"
ANALYSIS_DIR="$PROJECT_DIR/live_analysis"

# 创建目录（如果不存在）
mkdir -p "$ANALYSIS_DIR"

echo "📊 最新分析报告"
echo "==============="

# 找到最新的Markdown文件（支持多个可能的目录）
LATEST_MD=""
for dir in "$ANALYSIS_DIR" "$PROJECT_DIR/analysis_live" "$PROJECT_DIR/out"; do
    if [ -d "$dir" ]; then
        found=$(ls -t "$dir"/*_summary.md 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            LATEST_MD="$found"
            ANALYSIS_DIR="$dir"
            break
        fi
    fi
done

if [ -z "$LATEST_MD" ]; then
    echo "❌ 未找到分析报告"
    echo ""
    echo "💡 请先运行以下命令之一："
    echo "   1. ./start_auto_analysis.sh  (自动启动App和监控)"
    echo "   2. python3 tools/watch_live.py  (只启动监控)"
    echo "   3. python3 analyze_gesture_log.py <log文件> --gt-gesture V  (手动分析)"
    echo ""
    echo "📂 检查的目录："
    echo "   - $PROJECT_DIR/live_analysis"
    echo "   - $PROJECT_DIR/analysis_live"
    echo "   - $PROJECT_DIR/out"
    exit 1
fi

echo "📄 Markdown报告: $(basename "$LATEST_MD")"
CSV_FILE="${LATEST_MD/_summary.md/_samples.csv}"
if [ -f "$CSV_FILE" ]; then
    echo "📊 CSV数据文件: $(basename "$CSV_FILE")"
else
    echo "📊 CSV数据文件: 未找到"
fi
echo ""

# 显示报告摘要
cat "$LATEST_MD"
echo ""
echo "==============="
echo "🔍 查看详细数据："
echo "   Markdown: open -a TextEdit \"$LATEST_MD\""
if [ -f "$CSV_FILE" ]; then
    echo "   CSV:      open \"$CSV_FILE\""
fi
echo ""
echo "📂 分析目录: $ANALYSIS_DIR"
