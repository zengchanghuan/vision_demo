#!/bin/bash
#
# 🛑 停止监控分析系统
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "════════════════════════════════════════════════════════"
echo -e "${YELLOW}🛑 停止监控分析系统${NC}"
echo "════════════════════════════════════════════════════════"
echo ""

# 查找并停止监控进程
MONITOR_PIDS=$(ps aux | grep "watch_live.py" | grep -v grep | awk '{print $2}')

if [ -z "$MONITOR_PIDS" ]; then
    echo -e "${GREEN}✓ 没有运行中的监控进程${NC}"
else
    echo -e "${YELLOW}找到监控进程:${NC}"
    echo "$MONITOR_PIDS" | while read pid; do
        echo "  PID: $pid"
    done
    echo ""
    echo -e "${YELLOW}正在停止...${NC}"
    
    echo "$MONITOR_PIDS" | while read pid; do
        kill $pid 2>/dev/null
        echo -e "${GREEN}  ✓ 已停止 PID $pid${NC}"
    done
    
    sleep 2
    
    # 检查是否成功停止
    REMAINING=$(ps aux | grep "watch_live.py" | grep -v grep | awk '{print $2}')
    if [ -z "$REMAINING" ]; then
        echo -e "${GREEN}✅ 所有监控进程已停止${NC}"
    else
        echo -e "${RED}⚠️  部分进程可能需要强制停止:${NC}"
        echo "$REMAINING" | while read pid; do
            echo "  kill -9 $pid"
        done
    fi
fi

echo ""
echo -e "${YELLOW}📊 最终分析报告:${NC}"
cd ~/Desktop/workspace/swift_project/vision_demo

# 如果有日志，进行最终分析
if [ -f "logs/live.log" ] && [ -s "logs/live.log" ]; then
    echo "  正在生成最终分析报告..."
    
    # 激活虚拟环境并运行分析
    VENV_PYTHON="$HOME/.cursor/worktrees/vision_demo/vwn/venv/bin/python3"
    if [ -f "$VENV_PYTHON" ]; then
        # 使用虚拟环境中的Python
        "$VENV_PYTHON" analyze_gesture_log.py \
            --log-file logs/live.log \
            --gt-gesture V \
            --output-dir live_analysis > /tmp/final_analysis.log 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ 最终分析完成${NC}"
            echo ""
            echo -e "${YELLOW}📂 分析结果:${NC}"
            ls -lh live_analysis/ 2>/dev/null | tail -5 || echo "  未找到分析结果"
            echo ""
            echo -e "${YELLOW}🔍 查看报告:${NC}"
            echo "  ./view_latest_report.sh"
        else
            echo -e "${RED}  ✗ 分析失败${NC}"
            echo "  日志: cat /tmp/final_analysis.log"
        fi
    else
        echo -e "${YELLOW}  ⚠️  虚拟环境不存在: $VENV_PYTHON${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠️  没有找到日志文件${NC}"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ 系统已停止${NC}"
echo "════════════════════════════════════════════════════════"
echo ""
