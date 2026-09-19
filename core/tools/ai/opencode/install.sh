#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/colors"

LOG_FILE="$CORE_CACHE/install_ai.log"
OPENCODE_DATA_DIR="$HOME/.local/share/core-termux-data/opencode"

_opencode_detect_ubuntu_root() {
  # 1. Fast direct path checks (0ms)
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

  # 2. Check if proot-distro lists ubuntu as installed
  if command -v proot-distro &>/dev/null; then
    if proot-distro list 2>/dev/null | grep -Eiq 'ubuntu.*\(installed\)|\* ubuntu|alias: ubuntu'; then
      local pd_root="$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"
      if [ -d "$pd_root" ]; then
        echo "$pd_root"
        return 0
      fi
    fi
  fi

  # 3. Scoped search (shallow search in $PREFIX/var/lib)
  local root
  if [ -d "$PREFIX/var/lib" ]; then
    root="$(find "$PREFIX/var/lib" -maxdepth 4 -type d \( -name "ubuntu" -o -name "rootfs" \) 2>/dev/null | grep -E 'ubuntu.*rootfs|installed-rootfs/ubuntu' | head -1)"
    if [ -n "$root" ] && [ -d "$root" ] && [ -d "$root/bin" ]; then
      echo "$root"
      return 0
    fi
  fi

  # 4. Fallback search (scoped to /data/data/com.termux/files)
  root="$(find /data/data/com.termux/files -maxdepth 5 -type d -path "*/installed-rootfs/ubuntu" 2>/dev/null | head -1)"
  if [ -n "$root" ] && [ -d "$root" ]; then
    echo "$root"
    return 0
  fi

  return 1
}

_opencode_proot_ubuntu() {
  proot-distro login \
    --shared-tmp \
    ubuntu \
    -- "$@"
}

_cleanup_legacy_opencode_path() {
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
      sed -i '/\.opencode\/bin/d' "$rc" 2>/dev/null || true
    fi
  done
  hash -d opencode 2>/dev/null || true
  hash -r 2>/dev/null || true
}

_cleanup_legacy_opencode() {
  # If ~/.opencode/bin/opencode exists and is not a symlink to our helper, remove the broken raw binary
  if [ -f "$HOME/.opencode/bin/opencode" ] && [ ! -L "$HOME/.opencode/bin/opencode" ]; then
    rm -f "$HOME/.opencode/bin/opencode"
  fi
  _cleanup_legacy_opencode_path
}

_get_latest_opencode_version() {
  local version=""

  # Method 1: Follow HTTP redirect on /releases/latest (fastest & lightweight, avoids API rate limits)
  version=$(curl -sI --connect-timeout 6 -H "User-Agent: W8Core-Termux" https://github.com/anomalyco/opencode/releases/latest 2>/dev/null |
    grep -i '^location:' | sed -E 's/.*tag\/(.*)/\1/' | tr -d '\r\n ')

  # Method 2: GitHub API with User-Agent header
  if [ -z "$version" ]; then
    local api_args=(-H "User-Agent: W8Core-Termux")
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      api_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    fi
    version=$(curl -fsSL --connect-timeout 10 "${api_args[@]}" https://api.github.com/repos/anomalyco/opencode/releases/latest 2>/dev/null |
      grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '\r\n ')
  fi

  # Method 3: Scrape releases page HTML
  if [ -z "$version" ]; then
    version=$(curl -fsSL --connect-timeout 10 -H "User-Agent: W8Core-Termux" https://github.com/anomalyco/opencode/releases 2>/dev/null |
      grep -o '/releases/tag/v[0-9][^"'\'' ]*' | head -n 1 | cut -d/ -f4 | tr -d '\r\n ')
  fi

  echo "$version"
}

_opencode_install_deps_native() {
  loading "Installing glibc and dependencies" _opencode_install_deps_native_impl
}

_opencode_install_deps_native_impl() {
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
    if ! yes | pkg install ca-certificates &>>"$LOG_FILE"; then
      log_error "Failed to install ca-certificates"
      return 1
    fi
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

_download_opencode_binary() {
  loading "Downloading OpenCode" _download_opencode_binary_impl
}

_download_opencode_binary_impl() {
  mkdir -p "$OPENCODE_DATA_DIR"
  mkdir -p "$(dirname "$LOG_FILE")"

  local arch
  case "$(uname -m)" in
    aarch64|arm64)
      arch="arm64"
      ;;
    x86_64|amd64)
      arch="x64"
      ;;
    *)
      log_error "Unsupported architecture: $(uname -m). OpenCode requires 64-bit (arm64 or x64)."
      return 1
      ;;
  esac

  local tarball="opencode-linux-$arch.tar.gz"
  local latest_version
  latest_version=$(_get_latest_opencode_version)

  local urls=()
  if [ -n "$latest_version" ]; then
    urls+=("https://github.com/anomalyco/opencode/releases/download/$latest_version/$tarball")
  fi
  urls+=("https://github.com/anomalyco/opencode/releases/latest/download/$tarball")

  rm -f "$OPENCODE_DATA_DIR/$tarball"

  local downloaded=false
  local url
  for url in "${urls[@]}"; do
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -H "User-Agent: W8Core-Termux" "$url" -o "$OPENCODE_DATA_DIR/$tarball" &>>"$LOG_FILE"; then
      if [ -s "$OPENCODE_DATA_DIR/$tarball" ] && tar -ztf "$OPENCODE_DATA_DIR/$tarball" &>/dev/null; then
        downloaded=true
        break
      fi
    fi

    # SSL / CA fallback
    if curl -fLk --retry 2 --retry-delay 2 --connect-timeout 20 -H "User-Agent: W8Core-Termux" "$url" -o "$OPENCODE_DATA_DIR/$tarball" &>>"$LOG_FILE"; then
      if [ -s "$OPENCODE_DATA_DIR/$tarball" ] && tar -ztf "$OPENCODE_DATA_DIR/$tarball" &>/dev/null; then
        downloaded=true
        break
      fi
    fi
  done

  if [ "$downloaded" != "true" ] || [ ! -s "$OPENCODE_DATA_DIR/$tarball" ]; then
    log_error "Failed to download OpenCode binary"
    rm -f "$OPENCODE_DATA_DIR/$tarball"
    return 1
  fi

  if ! tar -zxf "$OPENCODE_DATA_DIR/$tarball" -C "$OPENCODE_DATA_DIR" &>>"$LOG_FILE"; then
    log_error "Failed to extract OpenCode binary"
    rm -f "$OPENCODE_DATA_DIR/$tarball"
    return 1
  fi

  rm -f "$OPENCODE_DATA_DIR/$tarball"

  if [ ! -f "$OPENCODE_DATA_DIR/opencode" ]; then
    log_error "OpenCode binary not found after extraction"
    return 1
  fi

  chmod +x "$OPENCODE_DATA_DIR/opencode"
  return 0
}

_compile_opencode_helper() {
  loading "Compiling helper" _compile_opencode_helper_impl
}

_compile_opencode_helper_impl() {
  local HELPER_SRC="$CORE_PATH/tools/ai/opencode/helper/opencode_helper.c"
  if [ ! -f "$HELPER_SRC" ]; then
    log_error "Helper source not found at $HELPER_SRC"
    return 1
  fi

  if ! clang -O2 -o "$PREFIX/bin/opencode" "$HELPER_SRC" &>>"$LOG_FILE"; then
    log_error "Failed to compile opencode helper"
    return 1
  fi

  chmod +x "$PREFIX/bin/opencode"

  # Link ~/.opencode/bin/opencode to $PREFIX/bin/opencode for active terminal sessions
  mkdir -p "$HOME/.opencode/bin" 2>/dev/null || true
  ln -sf "$PREFIX/bin/opencode" "$HOME/.opencode/bin/opencode" 2>/dev/null || true

  # Clean up legacy PATH exports from shell config files
  _cleanup_legacy_opencode_path

  return 0
}

_install_opencode_native() {
  _opencode_install_deps_native || return 1
  _download_opencode_binary || return 1
  _compile_opencode_helper || return 1
  log_success "OpenCode installed natively"
  log_info "To run OpenCode, use command: ${D_CYAN}opencode${NC}"
  return 0
}

_install_opencode_proot() {
  loading "Installing OpenCode (proot-distro)" _install_opencode_proot_impl || return 1
  log_info "To run OpenCode, use command: ${D_CYAN}opencode${NC}"
  return 0
}

_install_opencode_proot_impl() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if ! command -v proot-distro &>/dev/null; then
    yes | pkg install proot-distro &>>"$LOG_FILE"
  fi

  local ubuntu_root
  ubuntu_root="$(_opencode_detect_ubuntu_root)"

  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    log_info "Existing Ubuntu container detected at $ubuntu_root (skipping container download)"
  else
    if ! proot-distro list 2>/dev/null | grep -Eiq 'ubuntu.*\(installed\)|\* ubuntu'; then
      log_info "Downloading and installing Ubuntu container via proot-distro..."
      proot-distro install ubuntu &>>"$LOG_FILE"
    fi
    ubuntu_root="$(_opencode_detect_ubuntu_root)"
  fi

  if [ -z "$ubuntu_root" ] || [ ! -d "$ubuntu_root" ]; then
    log_error "Ubuntu rootfs not found"
    return 1
  fi

  _opencode_proot_ubuntu /bin/bash -c \
    'apt-get update && apt-get upgrade -y && apt-get install -y curl ca-certificates' \
    &>>"$LOG_FILE"

  _opencode_proot_ubuntu /bin/bash -c '
		export SHELL=/bin/bash
		export TMPDIR=/tmp
		export HOME=/root
		curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
	' &>>"$LOG_FILE"

  local opencode_bin="$ubuntu_root/root/.opencode/bin/opencode"

  if [ ! -f "$opencode_bin" ]; then
    log_error "OpenCode binary not found after install"
    return 1
  fi

  local wrapper_src="$CORE_PATH/tools/ai/opencode/bin/opencode"
  if [ ! -f "$wrapper_src" ]; then
    log_error "Wrapper template not found at $wrapper_src"
    return 1
  fi
  sed "s|__UBUNTU_ROOTFS__|$ubuntu_root|g" "$wrapper_src" >"$PREFIX/bin/opencode"
  chmod +x "$PREFIX/bin/opencode"

  if ! grep -q '.opencode/bin' "$ubuntu_root/root/.bashrc" 2>/dev/null; then
    printf '\n# opencode\nexport PATH=/root/.opencode/bin:$PATH\n' >>"$ubuntu_root/root/.bashrc"
  fi

  # Forward ~/.opencode/bin/opencode to $PREFIX/bin/opencode for active terminal sessions
  mkdir -p "$HOME/.opencode/bin" 2>/dev/null || true
  ln -sf "$PREFIX/bin/opencode" "$HOME/.opencode/bin/opencode" 2>/dev/null || true
  _cleanup_legacy_opencode_path

  return 0
}

install_opencode() {
  _cleanup_legacy_opencode

  if command -v opencode &>/dev/null || [ -d "$OPENCODE_DATA_DIR" ]; then
    log_warn "Existing OpenCode install detected; reinstalling"
    rm -f "$PREFIX/bin/opencode"
    rm -rf "$OPENCODE_DATA_DIR"
  fi

  log_info "Select installation method for OpenCode:"

  read_select "Installation method" SELECTED_METHOD \
    "Native (recommended) - Direct glibc, fastest, zero lag, runs anywhere" \
    "Proot-distro (alternative) - Ubuntu container"

  case "$SELECTED_METHOD" in
  *Proot-distro*)
    _install_opencode_proot
    ;;
  *Native*|*)
    _install_opencode_native
    ;;
  esac
}

uninstall_opencode() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if [ ! -f "$PREFIX/bin/opencode" ] && [ ! -d "$OPENCODE_DATA_DIR" ] && [ ! -f "$HOME/.opencode/bin/opencode" ]; then
    log_warn "OpenCode is not installed"
    return 1
  fi

  loading "Uninstalling OpenCode" _uninstall_opencode_impl
}

_uninstall_opencode_impl() {
  rm -f "$PREFIX/bin/opencode"
  rm -rf "$OPENCODE_DATA_DIR"
  rm -rf "$HOME/.opencode/bin"
  _cleanup_legacy_opencode_path

  local ubuntu_root
  ubuntu_root="$(_opencode_detect_ubuntu_root)"
  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    _opencode_proot_ubuntu /bin/bash -c 'rm -rf /root/.opencode' &>>"$LOG_FILE" || true
    local ubuntu_bashrc="$ubuntu_root/root/.bashrc"
    if [ -f "$ubuntu_bashrc" ]; then
      sed -i '/# opencode/d; /export PATH=\/root\/.opencode\/bin/d' "$ubuntu_bashrc" 2>/dev/null || true
    fi
  fi

  log_success "OpenCode uninstalled"
  return 0
}

update_opencode() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if [ -f "$OPENCODE_DATA_DIR/opencode" ]; then
    _install_opencode_native
    return $?
  fi

  loading "Updating OpenCode (proot-distro)" _update_opencode_proot_impl
}

_update_opencode_proot_impl() {
  _opencode_proot_ubuntu /bin/bash -c 'rm -rf /root/.opencode' &>>"$LOG_FILE"

  _opencode_proot_ubuntu /bin/bash -c '
		export SHELL=/bin/bash
		export TMPDIR=/tmp
		export HOME=/root
		curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
	' &>>"$LOG_FILE"

  local ubuntu_root
  ubuntu_root="$(_opencode_detect_ubuntu_root)"
  local opencode_bin="$ubuntu_root/root/.opencode/bin/opencode"

  if [ ! -f "$opencode_bin" ]; then
    log_error "OpenCode binary not found after update"
    return 1
  fi

  log_success "OpenCode (proot-distro) updated"
  return 0
}

reinstall_opencode() {
  uninstall_opencode
  install_opencode
}
