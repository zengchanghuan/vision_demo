#!/bin/bash
# 快速启动脚本 - 一键运行手势分析工具

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# 检查Python环境
check_python() {
    if command -v python3 &> /dev/null; then
        print_success "Python3已安装"
        return 0
    else
        print_error "未找到Python3"
        return 1
    fi
}

# 检查依赖
check_dependencies() {
    print_info "检查Python依赖..."
    
    if python3 -c "import pandas, numpy, matplotlib" 2>/dev/null; then
        print_success "所有依赖已安装"
        return 0
    else
        print_warning "缺少依赖包"
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    print_info "正在安装依赖..."
    
    if [ -d "venv" ]; then
        print_info "使用现有虚拟环境"
        source venv/bin/activate
    else
        print_info "创建虚拟环境..."
        python3 -m venv venv
        source venv/bin/activate
    fi
    
    pip install -q -r requirements.txt
    
    if [ $? -eq 0 ]; then
        print_success "依赖安装完成"
        return 0
    else
        print_error "依赖安装失败"
        return 1
    fi
}

# 显示主菜单
show_menu() {
    clear
    print_header "🤖 手势分析工具快速启动"
    echo ""
    echo "请选择工具："
    echo ""
    echo "  [1] 🎯 交互式分析器 (推荐新手)"
    echo "      引导式菜单，一步步完成分析"
    echo ""
    echo "  [2] 🤖 智能分析器"
    echo "      自动检测手势类型，生成HTML报告"
    echo ""
    echo "  [3] 📊 完整分析器"
    echo "      指定手势类型，详细统计分析"
    echo ""
    echo "  [4] 🔄 自动化监控"
    echo "      实时监控日志文件并自动分析"
    echo ""
    echo "  [5] 🧪 测试工具"
    echo "      使用示例日志测试功能"
    echo ""
    echo "  [6] 📚 查看文档"
    echo ""
    echo "  [0] 🚪 退出"
    echo ""
}

# 运行交互式分析器
run_interactive() {
    print_header "启动交互式分析器"
    python3 interactive_analyzer.py
}

# 运行智能分析器
run_smart() {
    print_header "智能分析器"
    echo ""
    read -p "请输入日志文件路径: " log_file
    
    if [ ! -f "$log_file" ]; then
        print_error "文件不存在"
        read -p "按Enter继续..."
        return
    fi
    
    python3 smart_analyzer.py "$log_file"
    
    read -p "按Enter继续..."
}

# 运行完整分析器
run_full() {
    print_header "完整分析器"
    echo ""
    read -p "请输入日志文件路径: " log_file
    
    if [ ! -f "$log_file" ]; then
        print_error "文件不存在"
        read -p "按Enter继续..."
        return
    fi
    
    echo ""
    echo "选择目标手势："
    echo "  [1] V手势"
    echo "  [2] OK手势"
    echo "  [3] 手掌张开"
    echo "  [4] 拳头"
    echo "  [5] 食指"
    echo "  [6] 自动检测"
    echo ""
    read -p "请选择 [6]: " gesture_choice
    gesture_choice=${gesture_choice:-6}
    
    case $gesture_choice in
        1) gesture="V" ;;
        2) gesture="OK" ;;
        3) gesture="Palm" ;;
        4) gesture="Fist" ;;
        5) gesture="Idx" ;;
        *) gesture="" ;;
    esac
    
    if [ -z "$gesture" ]; then
        python3 analyze_gesture_log.py --log-file "$log_file"
    else
        python3 analyze_gesture_log.py --log-file "$log_file" --gt-gesture "$gesture"
    fi
    
    read -p "按Enter继续..."
}

# 运行自动化监控
run_auto() {
    print_header "自动化监控"
    echo ""
    read -p "请输入要监控的日志文件路径: " log_file
    
    if [ ! -f "$log_file" ]; then
        print_warning "文件尚不存在，将等待文件创建..."
    fi
    
    echo ""
    read -p "触发阈值（日志条数）[30]: " threshold
    threshold=${threshold:-30}
    
    python3 auto_workflow.py --log-file "$log_file" --threshold "$threshold"
}

# 测试工具
run_test() {
    print_header "测试工具"
    echo ""
    
    if [ ! -f "test_gesture.log" ]; then
        print_error "未找到测试日志文件"
        read -p "按Enter继续..."
        return
    fi
    
    print_info "使用test_gesture.log进行测试..."
    echo ""
    
    python3 smart_analyzer.py test_gesture.log
    
    print_success "测试完成！"
    read -p "按Enter继续..."
}

# 查看文档
view_docs() {
    clear
    print_header "📚 文档列表"
    echo ""
    echo "  [1] 数据分析实战指南.md - 完整操作教程"
    echo "  [2] LOG_ANALYSIS_GUIDE.md - 详细使用指南"
    echo "  [3] PYTHON_TOOL_SUMMARY.md - 工具功能总结"
    echo "  [4] README.md - 项目概览"
    echo "  [0] 返回"
    echo ""
    read -p "请选择: " doc_choice
    
    case $doc_choice in
        1) open "数据分析实战指南.md" 2>/dev/null || cat "数据分析实战指南.md" | less ;;
        2) open "LOG_ANALYSIS_GUIDE.md" 2>/dev/null || cat "LOG_ANALYSIS_GUIDE.md" | less ;;
        3) open "PYTHON_TOOL_SUMMARY.md" 2>/dev/null || cat "PYTHON_TOOL_SUMMARY.md" | less ;;
        4) open "README.md" 2>/dev/null || cat "README.md" | less ;;
    esac
}

# 主程序
main() {
    # 检查Python
    if ! check_python; then
        print_error "请先安装Python3"
        exit 1
    fi
    
    # 检查依赖
    if ! check_dependencies; then
        echo ""
        read -p "是否自动安装依赖？[Y/n]: " install_choice
        install_choice=${install_choice:-Y}
        
        if [[ $install_choice =~ ^[Yy]$ ]]; then
            if ! install_dependencies; then
                print_error "无法安装依赖，请手动执行: pip install -r requirements.txt"
                exit 1
            fi
        else
            print_warning "缺少依赖，部分功能可能无法使用"
        fi
    fi
    
    # 主循环
    while true; do
        show_menu
        read -p "👉 请输入选项: " choice
        
        case $choice in
            1) run_interactive ;;
            2) run_smart ;;
            3) run_full ;;
            4) run_auto ;;
            5) run_test ;;
            6) view_docs ;;
            0) 
                print_info "再见！"
                exit 0
                ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main
