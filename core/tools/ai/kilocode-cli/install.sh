#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/colors"

LOG_FILE="$CORE_CACHE/install_ai.log"
KILOCODE_DATA_DIR="$HOME/.local/share/core-termux-data/kilocode"

_kilocode_detect_ubuntu_root() {
  local candidates=(
    "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"
    "/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu"
    "$PREFIX/var/lib/containers/ubuntu/rootfs"
    "$PREFIX/var/lib/containers/ubuntu"
    "$HOME/.local/share/proot-distro/installed-rootfs/ubuntu"
    "$HOME/.local/share/containers/ubuntu/rootfs"
  )

  local path
  for path in "${candidates[@]}"; do
    if [ -d "$path" ] && [ -d "$path/bin" ]; then
      echo "$path"
      return 0
    fi
  done

  if command -v proot-distro &>/dev/null; then
    if proot-distro list 2>/dev/null | grep -Eiq 'ubuntu.*\(installed\)|\* ubuntu|alias: ubuntu'; then
      local pd_root="$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"
      if [ -d "$pd_root" ]; then
        echo "$pd_root"
        return 0
      fi
    fi
  fi

  local root
  if [ -d "$PREFIX/var/lib" ]; then
    root="$(find "$PREFIX/var/lib" -maxdepth 4 -type d \( -name "ubuntu" -o -name "rootfs" \) 2>/dev/null | grep -E 'ubuntu.*rootfs|installed-rootfs/ubuntu' | head -1)"
    if [ -n "$root" ] && [ -d "$root" ] && [ -d "$root/bin" ]; then
      echo "$root"
      return 0
    fi
  fi

  root="$(find /data/data/com.termux/files -maxdepth 5 -type d -path "*/installed-rootfs/ubuntu" 2>/dev/null | head -1)"
  if [ -n "$root" ] && [ -d "$root" ]; then
    echo "$root"
    return 0
  fi

  return 1
}

_kilocode_proot_ubuntu() {
  proot-distro login \
    --shared-tmp \
    ubuntu \
    -- "$@"
}

_get_latest_kilocode_version() {
  local version=""

  # Method 1: Follow HTTP redirect on /releases/latest
  version=$(curl -sI --connect-timeout 6 -H "User-Agent: W8Core-Termux" https://github.com/Kilo-Org/kilocode/releases/latest 2>/dev/null |
    grep -i '^location:' | sed -E 's/.*tag\/(.*)/\1/' | tr -d '\r\n ')

  # Method 2: GitHub API with User-Agent
  if [ -z "$version" ]; then
    local api_args=(-H "User-Agent: W8Core-Termux")
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      api_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    fi
    version=$(curl -fsSL --connect-timeout 10 "${api_args[@]}" https://api.github.com/repos/Kilo-Org/kilocode/releases 2>/dev/null |
      grep '"tag_name":' | grep -v 'jetbrains' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '\r\n ')
  fi

  # Method 3: Releases page HTML
  if [ -z "$version" ]; then
    version=$(curl -fsSL --connect-timeout 10 -H "User-Agent: W8Core-Termux" https://github.com/Kilo-Org/kilocode/releases 2>/dev/null |
      grep -o '/releases/tag/v[0-9][^"'\'' ]*' | head -n 1 | cut -d/ -f4 | tr -d '\r\n ')
  fi

  echo "$version"
}

_kilocode_install_deps_native() {
  loading "Installing glibc and dependencies" _kilocode_install_deps_native_impl
}

_kilocode_install_deps_native_impl() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if [[ ! -f $PREFIX/etc/apt/sources.list.d/glibc.list ]]; then
    if ! yes | pkg install glibc-repo &>>"$LOG_FILE"; then
      log_error "Failed to install glibc-repo"
      return 1
    fi
  fi

  if [[ ! -f $PREFIX/glibc/lib/libc.so.6 ]]; then
    if ! yes | pkg install glibc &>>"$LOG_FILE"; then
      log_error "Failed to install glibc"
      return 1
    fi
  fi

  if [[ ! -f $PREFIX/etc/tls/cert.pem ]]; then
    yes | pkg install ca-certificates &>>"$LOG_FILE" || true
  fi

  declare -A DEPS=(
    ["git"]="git"
    ["ripgrep"]="rg"
    ["python"]="python"
    ["clang"]="clang"
    ["jq"]="jq"
    ["nodejs-lts"]="node"
    ["curl"]="curl"
    ["tar"]="tar"
  )

  local pkg_name bin_name
  for pkg_name in "${!DEPS[@]}"; do
    bin_name="${DEPS[$pkg_name]}"
    if ! command -v "$bin_name" &>/dev/null; then
      if ! yes | pkg install "$pkg_name" &>>"$LOG_FILE"; then
        log_error "Failed to install $pkg_name"
        return 1
      fi
    fi
  done

  return 0
}

_download_kilocode_binary() {
  loading "Downloading Kilo Code CLI (latest)" _download_kilocode_binary_impl
}

_download_kilocode_binary_impl() {
  mkdir -p "$KILOCODE_DATA_DIR"
  mkdir -p "$(dirname "$LOG_FILE")"

  local arch
  case "$(uname -m)" in
    aarch64|arm64) arch="arm64" ;;
    x86_64|amd64) arch="x64" ;;
    *) arch="arm64" ;;
  esac

  local tarball="kilo-linux-$arch.tar.gz"
  local latest_version
  latest_version=$(_get_latest_kilocode_version)

  local urls=()
  if [ -n "$latest_version" ]; then
    urls+=("https://github.com/Kilo-Org/kilocode/releases/download/$latest_version/$tarball")
  fi
  urls+=("https://github.com/Kilo-Org/kilocode/releases/latest/download/$tarball")

  rm -f "$KILOCODE_DATA_DIR/$tarball"

  local downloaded=false
  local url
  for url in "${urls[@]}"; do
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -H "User-Agent: W8Core-Termux" "$url" -o "$KILOCODE_DATA_DIR/$tarball" &>>"$LOG_FILE"; then
      if [ -s "$KILOCODE_DATA_DIR/$tarball" ] && tar -ztf "$KILOCODE_DATA_DIR/$tarball" &>/dev/null; then
        downloaded=true
        break
      fi
    fi
    if curl -fLk --retry 2 --retry-delay 2 --connect-timeout 20 -H "User-Agent: W8Core-Termux" "$url" -o "$KILOCODE_DATA_DIR/$tarball" &>>"$LOG_FILE"; then
      if [ -s "$KILOCODE_DATA_DIR/$tarball" ] && tar -ztf "$KILOCODE_DATA_DIR/$tarball" &>/dev/null; then
        downloaded=true
        break
      fi
    fi
  done

  if [ "$downloaded" != "true" ] || [ ! -s "$KILOCODE_DATA_DIR/$tarball" ]; then
    log_error "Failed to download Kilo Code CLI binary"
    rm -f "$KILOCODE_DATA_DIR/$tarball"
    return 1
  fi

  if ! tar -zxf "$KILOCODE_DATA_DIR/$tarball" -C "$KILOCODE_DATA_DIR" &>>"$LOG_FILE"; then
    log_error "Failed to extract Kilo Code CLI binary"
    rm -f "$KILOCODE_DATA_DIR/$tarball"
    return 1
  fi

  rm -f "$KILOCODE_DATA_DIR/$tarball"

  if [ ! -f "$KILOCODE_DATA_DIR/kilo" ]; then
    log_error "Kilo Code CLI binary not found after extraction"
    return 1
  fi

  chmod +x "$KILOCODE_DATA_DIR/kilo"
  return 0
}

_compile_kilocode_helper() {
  loading "Compiling helper" _compile_kilocode_helper_impl
}

_compile_kilocode_helper_impl() {
  local HELPER_SRC="$CORE_PATH/tools/ai/kilocode-cli/helper/kilocode_helper.c"
  if [ ! -f "$HELPER_SRC" ]; then
    log_error "Helper source not found at $HELPER_SRC"
    return 1
  fi

  if ! clang -O2 -o "$PREFIX/bin/kilocode" "$HELPER_SRC" &>>"$LOG_FILE"; then
    log_error "Failed to compile kilocode helper"
    return 1
  fi

  chmod +x "$PREFIX/bin/kilocode"

  ln -sf "$PREFIX/bin/kilocode" "$PREFIX/bin/kilo"

  return 0
}

_install_kilocode_native() {
  _kilocode_install_deps_native || return 1
  _download_kilocode_binary || return 1
  _compile_kilocode_helper || return 1
  log_success "Kilo Code CLI installed natively"
  log_info "To run Kilo Code CLI, use command: ${D_CYAN}kilo${NC} (or ${D_CYAN}kilocode${NC})"
  return 0
}

_install_kilocode_proot() {
  loading "Installing Kilo Code CLI (proot-distro)" _install_kilocode_proot_impl || return 1
  log_info "To run Kilo Code CLI, use command: ${D_CYAN}kilo${NC} (or ${D_CYAN}kilocode${NC})"
  return 0
}

_install_kilocode_proot_impl() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if ! command -v proot-distro &>/dev/null; then
    yes | pkg install proot-distro &>>"$LOG_FILE"
  fi

  local ubuntu_root
  ubuntu_root="$(_kilocode_detect_ubuntu_root)"

  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    log_info "Existing Ubuntu container detected at $ubuntu_root (skipping container download)"
  else
    if ! proot-distro list 2>/dev/null | grep -Eiq 'ubuntu.*\(installed\)|\* ubuntu'; then
      log_info "Downloading and installing Ubuntu container via proot-distro..."
      proot-distro install ubuntu &>>"$LOG_FILE"
    fi
    ubuntu_root="$(_kilocode_detect_ubuntu_root)"
  fi

  if [ -z "$ubuntu_root" ] || [ ! -d "$ubuntu_root" ]; then
    log_error "Ubuntu rootfs not found"
    return 1
  fi

  _kilocode_proot_ubuntu /bin/bash -c \
    'apt-get update && apt-get upgrade -y && apt-get install -y curl ca-certificates tar' \
    &>>"$LOG_FILE"

  local latest_version
  latest_version=$(_get_latest_kilocode_version)
  if [ -z "$latest_version" ]; then
    log_error "Failed to fetch latest Kilo Code CLI version"
    return 1
  fi

  local arch
  case "$(uname -m)" in
    aarch64|arm64) arch="arm64" ;;
    x86_64|amd64) arch="x64" ;;
    *) arch="arm64" ;;
  esac

  local download_url="https://github.com/Kilo-Org/kilocode/releases/download/$latest_version/kilo-linux-$arch.tar.gz"

  _kilocode_proot_ubuntu /bin/bash -c "
    mkdir -p /tmp/kilocode-install &&
    curl -fsSL '$download_url' -o /tmp/kilocode-install/kilo.tar.gz &&
    tar -zxf /tmp/kilocode-install/kilo.tar.gz -C /tmp/kilocode-install &&
    mkdir -p /usr/local/bin &&
    mv /tmp/kilocode-install/kilo /usr/local/bin/kilo &&
    chmod +x /usr/local/bin/kilo &&
    rm -rf /tmp/kilocode-install
  " &>>"$LOG_FILE"

  local kilocode_bin="$ubuntu_root/usr/local/bin/kilo"

  if [ ! -f "$kilocode_bin" ]; then
    log_error "Kilo Code CLI binary not found after install"
    return 1
  fi

  local wrapper_src="$CORE_PATH/tools/ai/kilocode-cli/bin/kilocode"
  if [ ! -f "$wrapper_src" ]; then
    log_error "Wrapper template not found at $wrapper_src"
    return 1
  fi
  sed "s|__UBUNTU_ROOTFS__|$ubuntu_root|g" "$wrapper_src" >"$PREFIX/bin/kilocode"
  chmod +x "$PREFIX/bin/kilocode"

  ln -sf "$PREFIX/bin/kilocode" "$PREFIX/bin/kilo"

  return 0
}

install_kilocode_cli() {
  if command -v kilocode &>/dev/null || [ -d "$KILOCODE_DATA_DIR" ]; then
    log_warn "Existing Kilo Code CLI install detected; reinstalling"
    rm -f "$PREFIX/bin/kilocode" "$PREFIX/bin/kilo"
    rm -rf "$KILOCODE_DATA_DIR"
  fi

  # Fast scan for existing Ubuntu container
  local ubuntu_root
  ubuntu_root="$(_kilocode_detect_ubuntu_root)"

  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    log_success "Found existing Ubuntu container at: $ubuntu_root"
    log_info "Auto-selecting Ubuntu container (skipping container re-download)"
    _install_kilocode_proot
    return $?
  fi

  log_info "Select installation method for Kilo Code CLI:"

  read_select "Installation method" SELECTED_METHOD \
    "Native (recommended) - Compile with glibc support" \
    "Proot-distro (alternative) - Ubuntu container"

  case "$SELECTED_METHOD" in
  *Native*)
    _install_kilocode_native
    ;;
  *Proot-distro*)
    _install_kilocode_proot
    ;;
  esac
}

uninstall_kilocode_cli() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if [ ! -f "$PREFIX/bin/kilocode" ]; then
    log_warn "Kilo Code CLI is not installed"
    return 1
  fi

  loading "Uninstalling Kilo Code CLI" _uninstall_kilocode_cli_impl
}

_uninstall_kilocode_cli_impl() {
  if [ -f "$KILOCODE_DATA_DIR/kilo" ]; then
    rm -f "$PREFIX/bin/kilocode" "$PREFIX/bin/kilo"
    rm -rf "$KILOCODE_DATA_DIR"
    log_success "Kilo Code CLI (native) uninstalled"
    return 0
  fi

  _kilocode_proot_ubuntu /bin/bash -c 'rm -f /usr/local/bin/kilo' &>>"$LOG_FILE"

  if rm -f "$PREFIX/bin/kilocode" "$PREFIX/bin/kilo" &>>"$LOG_FILE"; then
    log_success "Kilo Code CLI (proot-distro) uninstalled"
    return 0
  else
    log_error "Failed to uninstall Kilo Code CLI"
    return 1
  fi
}

update_kilocode_cli() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if [ -f "$KILOCODE_DATA_DIR/kilo" ]; then
    _install_kilocode_native
    return $?
  fi

  loading "Updating Kilo Code CLI (proot-distro)" _update_kilocode_proot_impl
}

_update_kilocode_proot_impl() {
  local latest_version
  latest_version=$(_get_latest_kilocode_version)
  if [ -z "$latest_version" ]; then
    log_error "Failed to fetch latest Kilo Code CLI version"
    return 1
  fi

  local download_url="https://github.com/Kilo-Org/kilocode/releases/download/$latest_version/kilo-linux-arm64.tar.gz"

  _kilocode_proot_ubuntu /bin/bash -c "
    mkdir -p /tmp/kilocode-install &&
    curl -fsSL '$download_url' -o /tmp/kilocode-install/kilo.tar.gz &&
    tar -zxf /tmp/kilocode-install/kilo.tar.gz -C /tmp/kilocode-install &&
    rm -f /usr/local/bin/kilo &&
    mv /tmp/kilocode-install/kilo /usr/local/bin/kilo &&
    chmod +x /usr/local/bin/kilo &&
    rm -rf /tmp/kilocode-install
  " &>>"$LOG_FILE"

  local kilocode_bin
  kilocode_bin="$(_kilocode_detect_ubuntu_root)/usr/local/bin/kilo"

  if [ ! -f "$kilocode_bin" ]; then
    log_error "Kilo Code CLI binary not found after update"
    return 1
  fi

  log_success "Kilo Code CLI (proot-distro) updated"
  return 0
}

reinstall_kilocode_cli() {
  uninstall_kilocode_cli
  install_kilocode_cli
}
