#!/usr/bin/env bash
#
# bts_extract.sh - 从 Android target_files 包中提取镜像并生成指纹
#
# 用法: bts_extract.sh <target_files.zip>
#
# 依赖:
#   必须: unzip, zip, python3
#   可选: simg2img (sparse 镜像转换), debugfs (ext4 文件读取)
#
set -euo pipefail

# ============================================================================
# 颜色定义
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# 工具函数
# ============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

die() {
    log_error "$*"
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# 依赖检查
# ============================================================================
check_dependencies() {
    local missing=()
    local required_cmds=(unzip zip python3)

    for cmd in "${required_cmds[@]}"; do
        if ! check_command "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "缺少必要命令: ${missing[*]}\n请运行安装脚本或手动安装"
    fi

    # 可选依赖提示
    if ! check_command simg2img; then
        log_warn "simg2img 未安装，sparse 镜像将无法转换"
    fi
    if ! check_command debugfs; then
        log_warn "debugfs 未安装，无法从 ext4 镜像提取指纹"
    fi
}

# ============================================================================
# 输入验证
# ============================================================================
get_target_zip() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        read -rp "请输入 target_files 包路径: " target
    fi

    [[ -z "$target" ]] && die "未提供文件路径"

    target=$(realpath "$target" 2>/dev/null) || die "路径无效: $target"
    [[ -f "$target" ]] || die "文件不存在: $target"

    echo "$target"
}

# ============================================================================
# 从 SYSTEM/build.prop 提取原型指纹
# ============================================================================
extract_proto_fingerprint() {
    local zip_path="$1"

    python3 - "$zip_path" <<'PYTHON'
import sys
import zipfile

zip_path = sys.argv[1]

with zipfile.ZipFile(zip_path) as z:
    text = z.read("SYSTEM/build.prop").decode(errors="ignore")

fp = brand = name = device = aos_ver = build_id = inc = None

for line in text.splitlines():
    if line.startswith("ro.build.fingerprint="):
        fp = line.split("=", 1)[1].strip()
        break
    if line.startswith("ro.system.build.fingerprint="):
        fp = line.split("=", 1)[1].strip()
    if line.startswith("ro.system.build.version.release="):
        aos_ver = line.split("=", 1)[1].strip()
    if line.startswith("ro.system.build.id="):
        build_id = line.split("=", 1)[1].strip()
    if line.startswith("ro.system.build.version.incremental="):
        inc = line.split("=", 1)[1].strip()

for line in text.splitlines():
    key, _, val = line.partition("=")
    val = val.strip()
    if key in ("ro.product.brand", "ro.system.product.brand"):
        brand = brand or val
    elif key in ("ro.product.name", "ro.system.product.name"):
        name = name or val
    elif key in ("ro.product.device", "ro.system.product.device"):
        device = device or val

if fp:
    print(fp)
else:
    ver = aos_ver or "unknown"
    bid = build_id or "unknown"
    incr = inc or "unknown"
    print(f"{brand}/{name}/{device}:{ver}/{bid}/{incr}:user/release-keys")
PYTHON
}

# ============================================================================
# 从 OEM 镜像提取指纹
# ============================================================================
extract_fp_from_oem() {
    local img_path="$1"
    local proto_template="$2"
    shift 2
    local auth_paths=("$@")

    python3 - "$img_path" "$proto_template" "${auth_paths[@]}" <<'PYTHON'
import sys
import subprocess
import os
from shutil import which

img = sys.argv[1]
proto = sys.argv[2]
paths = sys.argv[3:]


def try_debugfs(img_file, path):
    """尝试用 debugfs 读取文件内容"""
    try:
        return subprocess.check_output(
            ["debugfs", "-R", f"cat {path}", img_file],
            stderr=subprocess.DEVNULL,
            text=True
        )
    except Exception:
        return None


def maybe_unsparse(img_file):
    """如果是 sparse 镜像，尝试转换"""
    if not which("simg2img"):
        return img_file
    raw = img_file + ".raw"
    try:
        subprocess.check_call(
            ["simg2img", img_file, raw],
            stderr=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL
        )
        return raw if os.path.isfile(raw) else img_file
    except Exception:
        return img_file


def parse_build_prop(content):
    """解析 build.prop 内容"""
    fp = brand = name = device = None
    fp_keys = (
        "ro.build.fingerprint",
        "ro.system.build.fingerprint",
        "ro.vendor.build.fingerprint"
    )
    brand_keys = ("ro.product.brand", "ro.system.product.brand", "ro.vendor.product.brand")
    name_keys = ("ro.product.name", "ro.system.product.name", "ro.vendor.product.name")
    device_keys = ("ro.product.device", "ro.system.product.device", "ro.vendor.product.device")

    for line in content.splitlines():
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        val = val.strip()

        if key in fp_keys and not fp:
            fp = val
        elif key in brand_keys and not brand:
            brand = val
        elif key in name_keys and not name:
            name = val
        elif key in device_keys and not device:
            device = val

    return fp, brand, name, device


def rebuild_fingerprint(proto_fp, brand, name, device):
    """用模板重建指纹，替换 brand/name/device"""
    try:
        proto_parts = proto_fp.split("/", 2)
        if len(proto_parts) != 3:
            return proto_fp

        p_brand, p_name, p_rest = proto_parts
        p_device, _, p_tail = p_rest.partition(":")

        new_brand = brand or p_brand
        new_name = name or p_name
        new_device = device or p_device

        result = f"{new_brand}/{new_name}/{new_device}"
        if p_tail:
            result += f":{p_tail}"
        return result
    except Exception:
        return proto_fp


# 主逻辑
raw = maybe_unsparse(img)
content = None

for p in paths:
    content = try_debugfs(raw, p)
    if content:
        break

if content:
    fp, brand, name, device = parse_build_prop(content)
    if fp:
        print(fp)
    else:
        print(rebuild_fingerprint(proto, brand, name, device))
else:
    print(proto)
PYTHON
}

# ============================================================================
# 主流程
# ============================================================================
main() {
    log_info "BTS Extract - Android 镜像提取工具"
    echo

    # 检查依赖
    check_dependencies

    # 获取输入文件
    local target_zip
    target_zip=$(get_target_zip "${1:-}")
    log_info "处理文件: $target_zip"

    # 输出目录设置
    local out_dir="bts_out"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local out_zip="BTS_${timestamp}.zip"
    local fp_file="fingerprint.txt"

    mkdir -p "$out_dir"

    # 收集需要解压的文件
    local -a files=(IMAGES/boot.img IMAGES/system.img IMAGES/vendor.img)
    while IFS= read -r line; do
        [[ -n "$line" ]] && files+=("$line")
    done < <(zipinfo -1 "$target_zip" "IMAGES/oem*.img" 2>/dev/null || true)

    # 过滤存在的文件
    local -a existing=()
    for f in "${files[@]}"; do
        if zipinfo -1 "$target_zip" "$f" >/dev/null 2>&1; then
            existing+=("$f")
        fi
    done

    if [[ ${#existing[@]} -eq 0 ]]; then
        die "IMAGES/ 下未找到 boot/system/vendor/oem*.img"
    fi

    log_info "找到 ${#existing[@]} 个镜像文件"

    # 解压文件
    log_info "正在解压..."
    unzip -o -j "$target_zip" "${existing[@]}" -d "$out_dir"

    # 提取原型指纹
    log_info "提取系统指纹..."
    local proto_template
    proto_template=$(extract_proto_fingerprint "$target_zip")

    # 定义搜索路径
    local -a auth_paths=(
        "/system/build.prop"
        "/build.prop"
        "/system/system/build.prop"
        "/oem/build.prop"
        "/vendor/build.prop"
        "/system/etc/build.prop"
        "/oem.prop"
    )

    # 写入指纹文件
    local fp_out="$out_dir/$fp_file"
    : > "$fp_out"

    log_info "处理 OEM 镜像..."
    for img in "$out_dir"/oem*.img; do
        [[ -f "$img" ]] || continue
        local fp
        fp=$(extract_fp_from_oem "$img" "$proto_template" "${auth_paths[@]}" 2>/dev/null || true)
        [[ -n "$fp" ]] && echo "$fp" >> "$fp_out"
    done

    # 清理临时 .raw 文件
    rm -f "$out_dir"/*.raw 2>/dev/null || true

    # 打包镜像
    log_info "正在打包..."
    (
        cd "$out_dir"
        # shellcheck disable=SC2046
        zip -q "$out_zip" $(printf "%s\n" "${existing[@]##*/}")
    )

    # 清理中间文件
    rm -f "$out_dir"/{boot,system,vendor}.img "$out_dir"/oem*.img 2>/dev/null || true

    # 输出结果
    echo
    log_success "处理完成!"
    echo
    echo "  镜像包:     $out_dir/$out_zip"
    echo "  指纹文件:   $fp_out"
    echo
    echo "指纹内容:"
    echo "----------------------------------------"
    cat "$fp_out"
    echo "----------------------------------------"
}

main "$@"
