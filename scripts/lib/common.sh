#!/usr/bin/env bash
# scripts/lib/common.sh
# 共通ロジック & ユーティリティ
set -euo pipefail

# ANSI カラー
readonly COLOR_RESET="\033[0m"
readonly COLOR_RED="\033[31m"
readonly COLOR_GREEN="\033[32m"
readonly COLOR_YELLOW="\033[33m"
readonly COLOR_BLUE="\033[34m"

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# 必須コマンド存在確認
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "Required command '$cmd' is not installed or not in PATH."
    fi
}

# プロジェクトルートパスの解決
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "${script_dir}/../.." && pwd
}
