#!/usr/bin/env bash
#
# BTS Extract 一键安装脚本
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/<用户>/<仓库>/main/install.sh | bash
#   或
#   wget -qO- https://raw.githubusercontent.com/<用户>/<仓库>/main/install.sh | bash
#
# 支持环境: WSL1, WSL2, Ubuntu, Debian, 其他基于 apt 的 Linux 发行版
#
set -euo pipefail

# ============================================================================
# 配置
# ============================================================================
REPO_RAW_URL="${BTS_REPO_URL:-https://zhifu1996.github.io/BTS}"
INSTALL_DIR="${BTS_INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_NAME="bts_extract.sh"

# ============================================================================
# 颜色定义
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# 工具函数
# ============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

print_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
 ____  _____ ____    _____      _                  _
| __ )|_   _/ ___|  | ____|_  _| |_ _ __ __ _  ___| |_
|  _ \  | | \___ \  |  _| \ \/ / __| '__/ _` |/ __| __|
| |_) | | |  ___) | | |___ >  <| |_| | | (_| | (__| |_
|____/  |_| |____/  |_____/_/\_\\__|_|  \__,_|\___|\__|

EOF
    echo -e "${NC}"
    echo "Android 镜像提取工具 - 一键安装"
    echo "================================================"
    echo
}

die() {
    log_error "$*"
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# 环境检测
# ============================================================================
detect_environment() {
    local env_type="linux"

    if [[ -f /proc/version ]]; then
        if grep -qi microsoft /proc/version 2>/dev/null; then
            if [[ -d /run/WSL ]]; then
                env_type="wsl2"
            else
                env_type="wsl1"
            fi
        fi
    fi

    echo "$env_type"
}

detect_package_manager() {
    if check_command apt-get; then
        echo "apt"
    elif check_command dnf; then
        echo "dnf"
    elif check_command yum; then
        echo "yum"
    elif check_command pacman; then
        echo "pacman"
    elif check_command zypper; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# ============================================================================
# 依赖安装
# ============================================================================
install_dependencies() {
    local pkg_manager="$1"
    local env_type="$2"

    log_info "检测到环境: $env_type"
    log_info "包管理器: $pkg_manager"
    echo

    # 必须依赖
    local required_pkgs=()
    # 可选依赖
    local optional_pkgs=()

    case "$pkg_manager" in
        apt)
            required_pkgs=(unzip zip python3)
            optional_pkgs=(android-sdk-libsparse-utils e2fsprogs)
            ;;
        dnf|yum)
            required_pkgs=(unzip zip python3)
            optional_pkgs=(android-tools e2fsprogs)
            ;;
        pacman)
            required_pkgs=(unzip zip python)
            optional_pkgs=(android-tools e2fsprogs)
            ;;
        zypper)
            required_pkgs=(unzip zip python3)
            optional_pkgs=(e2fsprogs)
            ;;
        *)
            log_warn "未知的包管理器，请手动安装: unzip zip python3 simg2img debugfs"
            return 1
            ;;
    esac

    # 检查哪些需要安装
    local to_install=()
    local optional_to_install=()

    for pkg in "${required_pkgs[@]}"; do
        local cmd="$pkg"
        [[ "$pkg" == "python3" || "$pkg" == "python" ]] && cmd="python3"
        if ! check_command "$cmd"; then
            to_install+=("$pkg")
        fi
    done

    if ! check_command simg2img; then
        for pkg in "${optional_pkgs[@]}"; do
            if [[ "$pkg" == *sparse* ]] || [[ "$pkg" == "android-tools" ]] || [[ "$pkg" == "android-sdk-libsparse-utils" ]]; then
                optional_to_install+=("$pkg")
                break
            fi
        done
    fi

    if ! check_command debugfs; then
        for pkg in "${optional_pkgs[@]}"; do
            if [[ "$pkg" == "e2fsprogs" ]]; then
                optional_to_install+=("$pkg")
                break
            fi
        done
    fi

    # 安装必须依赖
    if [[ ${#to_install[@]} -gt 0 ]]; then
        log_info "安装必要依赖: ${to_install[*]}"

        case "$pkg_manager" in
            apt)
                sudo apt-get update -qq
                sudo apt-get install -y -qq "${to_install[@]}"
                ;;
            dnf)
                sudo dnf install -y -q "${to_install[@]}"
                ;;
            yum)
                sudo yum install -y -q "${to_install[@]}"
                ;;
            pacman)
                sudo pacman -Sy --noconfirm "${to_install[@]}"
                ;;
            zypper)
                sudo zypper install -y "${to_install[@]}"
                ;;
        esac

        log_success "必要依赖安装完成"
    else
        log_success "必要依赖已满足"
    fi

    # 安装可选依赖
    if [[ ${#optional_to_install[@]} -gt 0 ]]; then
        log_info "安装可选依赖: ${optional_to_install[*]}"

        case "$pkg_manager" in
            apt)
                sudo apt-get install -y -qq "${optional_to_install[@]}" 2>/dev/null || \
                    log_warn "部分可选依赖安装失败，某些功能可能受限"
                ;;
            dnf)
                sudo dnf install -y -q "${optional_to_install[@]}" 2>/dev/null || \
                    log_warn "部分可选依赖安装失败"
                ;;
            yum)
                sudo yum install -y -q "${optional_to_install[@]}" 2>/dev/null || \
                    log_warn "部分可选依赖安装失败"
                ;;
            pacman)
                sudo pacman -Sy --noconfirm "${optional_to_install[@]}" 2>/dev/null || \
                    log_warn "部分可选依赖安装失败"
                ;;
            zypper)
                sudo zypper install -y "${optional_to_install[@]}" 2>/dev/null || \
                    log_warn "部分可选依赖安装失败"
                ;;
        esac
    fi

    # WSL1 特殊提示
    if [[ "$env_type" == "wsl1" ]]; then
        echo
        log_warn "WSL1 环境检测到，以下功能可能受限:"
        log_warn "  - debugfs 可能无法正常工作"
        log_warn "  - 建议升级到 WSL2 以获得完整功能"
    fi
}

# ============================================================================
# 下载安装脚本
# ============================================================================
install_script() {
    log_info "创建安装目录: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    local script_path="$INSTALL_DIR/$SCRIPT_NAME"

    # 检查是否是本地安装（用于开发测试）
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local local_script="$script_dir/$SCRIPT_NAME"

    if [[ -f "$local_script" ]]; then
        log_info "检测到本地脚本，使用本地安装模式"
        cp "$local_script" "$script_path"
    else
        log_info "从远程下载脚本..."

        if check_command curl; then
            curl -fsSL "$REPO_RAW_URL/$SCRIPT_NAME" -o "$script_path" || \
                die "下载失败，请检查网络连接或仓库地址"
        elif check_command wget; then
            wget -qO "$script_path" "$REPO_RAW_URL/$SCRIPT_NAME" || \
                die "下载失败，请检查网络连接或仓库地址"
        else
            die "需要 curl 或 wget 来下载脚本"
        fi
    fi

    chmod +x "$script_path"
    log_success "脚本已安装到: $script_path"

    # 检查 PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo
        log_warn "$INSTALL_DIR 不在 PATH 中"
        log_info "请将以下内容添加到 ~/.bashrc 或 ~/.zshrc:"
        echo
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo
        log_info "然后运行: source ~/.bashrc"
    fi
}

# ============================================================================
# 打印使用说明
# ============================================================================
print_usage() {
    echo
    echo -e "${GREEN}${BOLD}安装完成!${NC}"
    echo
    echo "================================================"
    echo -e "${BOLD}使用方法:${NC}"
    echo "================================================"
    echo
    echo "  ${CYAN}bts_extract.sh <target_files.zip>${NC}"
    echo
    echo "示例:"
    echo "  bts_extract.sh ./xiaomi-target-files.zip"
    echo
    echo "输出:"
    echo "  - bts_out/BTS_<时间戳>.zip    打包后的镜像文件"
    echo "  - bts_out/fingerprint.txt     提取的设备指纹"
    echo
    echo "================================================"
    echo -e "${BOLD}依赖状态:${NC}"
    echo "================================================"
    echo

    # 检查各依赖状态
    local deps=(
        "unzip:必须:解压 target_files"
        "zip:必须:打包输出镜像"
        "python3:必须:解析 build.prop"
        "simg2img:可选:转换 sparse 镜像"
        "debugfs:可选:读取 ext4 镜像内容"
    )

    for dep_info in "${deps[@]}"; do
        IFS=':' read -r cmd level desc <<< "$dep_info"
        if check_command "$cmd"; then
            echo -e "  ${GREEN}✓${NC} $cmd ($level) - $desc"
        else
            if [[ "$level" == "必须" ]]; then
                echo -e "  ${RED}✗${NC} $cmd ($level) - $desc"
            else
                echo -e "  ${YELLOW}○${NC} $cmd ($level) - $desc"
            fi
        fi
    done

    echo
    echo "================================================"
    echo
}

# ============================================================================
# 主流程
# ============================================================================
main() {
    print_banner

    # 检测环境
    local env_type
    env_type=$(detect_environment)

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    # 安装依赖
    if [[ "$pkg_manager" != "unknown" ]]; then
        install_dependencies "$pkg_manager" "$env_type"
    else
        log_warn "无法自动安装依赖，请手动安装"
    fi

    echo

    # 安装脚本
    install_script

    # 打印使用说明
    print_usage
}

main "$@"
