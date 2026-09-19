#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/colors"

LOG_FILE="$CORE_CACHE/install_ai.log"
CLAUDE_DATA_DIR="$HOME/.local/share/core-termux-data/claude"

_claude_detect_ubuntu_root() {
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

_claude_proot_ubuntu() {
  proot-distro login \
    --shared-tmp \
    ubuntu \
    -- "$@"
}

_get_latest_claude_version() {
  local version=""

  # Method 1: Follow HTTP redirect on /releases/latest
  version=$(curl -sI --connect-timeout 6 -H "User-Agent: W8Core-Termux" https://github.com/anthropics/claude-code/releases/latest 2>/dev/null |
    grep -i '^location:' | sed -E 's/.*tag\/(.*)/\1/' | tr -d '\r\n ')

  # Method 2: GitHub API with User-Agent
  if [ -z "$version" ]; then
    local api_args=(-H "User-Agent: W8Core-Termux")
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      api_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    fi
    version=$(curl -fsSL --connect-timeout 10 "${api_args[@]}" https://api.github.com/repos/anthropics/claude-code/releases/latest 2>/dev/null |
      grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '\r\n ')
  fi

  # Method 3: Releases page HTML
  if [ -z "$version" ]; then
    version=$(curl -fsSL --connect-timeout 10 -H "User-Agent: W8Core-Termux" https://github.com/anthropics/claude-code/releases 2>/dev/null |
      grep -o '/releases/tag/v[0-9][^"'\'' ]*' | head -n 1 | cut -d/ -f4 | tr -d '\r\n ')
  fi

  echo "$version"
}

_claude_install_deps_native() {
  loading "Installing glibc and dependencies" _claude_install_deps_native_impl
}

_claude_install_deps_native_impl() {
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
    ["clang"]="clang"
    ["curl"]="curl"
    ["tar"]="tar"
  )

  local pkg_name bin_name
  for pkg_name in "${!DEPS[@]}"; do
    bin_name="${DEPS[$pkg_name]}"
    if [[ -n "$bin_name" ]] && command -v "$bin_name" &>/dev/null; then
      continue
    fi
    if ! yes | pkg install "$pkg_name" &>>"$LOG_FILE"; then
      log_error "Failed to install $pkg_name"
      return 1
    fi
  done

  return 0
}

_download_claude_binary() {
  loading "Downloading Claude Code (latest)" _download_claude_binary_impl
}

_download_claude_binary_impl() {
  mkdir -p "$CLAUDE_DATA_DIR"
  mkdir -p "$(dirname "$LOG_FILE")"

  local arch
  case "$(uname -m)" in
    aarch64|arm64) arch="arm64" ;;
    x86_64|amd64) arch="x64" ;;
    *) arch="arm64" ;;
  esac

  local tarball="claude-linux-$arch.tar.gz"
  local latest_version
  latest_version=$(_get_latest_claude_version)

  local urls=()
  if [ -n "$latest_version" ]; then
    urls+=("https://github.com/anthropics/claude-code/releases/download/$latest_version/$tarball")
  fi
  urls+=("https://github.com/anthropics/claude-code/releases/latest/download/$tarball")

  rm -f "$CLAUDE_DATA_DIR/$tarball"

  local downloaded=false
  local url
  for url in "${urls[@]}"; do
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -H "User-Agent: W8Core-Termux" "$url" -o "$CLAUDE_DATA_DIR/$tarball" &>>"$LOG_FILE"; then
      if [ -s "$CLAUDE_DATA_DIR/$tarball" ] && tar -ztf "$CLAUDE_DATA_DIR/$tarball" &>/dev/null; then
        downloaded=true
        break
      fi
    fi
    if curl -fLk --retry 2 --retry-delay 2 --connect-timeout 20 -H "User-Agent: W8Core-Termux" "$url" -o "$CLAUDE_DATA_DIR/$tarball" &>>"$LOG_FILE"; then
      if [ -s "$CLAUDE_DATA_DIR/$tarball" ] && tar -ztf "$CLAUDE_DATA_DIR/$tarball" &>/dev/null; then
        downloaded=true
        break
      fi
    fi
  done

  if [ "$downloaded" != "true" ] || [ ! -s "$CLAUDE_DATA_DIR/$tarball" ]; then
    log_error "Failed to download Claude Code binary"
    rm -f "$CLAUDE_DATA_DIR/$tarball"
    return 1
  fi

  if ! tar -zxf "$CLAUDE_DATA_DIR/$tarball" -C "$CLAUDE_DATA_DIR" &>>"$LOG_FILE"; then
    log_error "Failed to extract Claude Code binary"
    rm -f "$CLAUDE_DATA_DIR/$tarball"
    return 1
  fi

  rm -f "$CLAUDE_DATA_DIR/$tarball"

  if [ ! -f "$CLAUDE_DATA_DIR/claude" ]; then
    log_error "Claude Code binary not found after extraction"
    return 1
  fi

  chmod +x "$CLAUDE_DATA_DIR/claude"
  return 0
}

_compile_claude_helper() {
  loading "Compiling helper" _compile_claude_helper_impl
}

_compile_claude_helper_impl() {
  local HELPER_SRC="$CORE_PATH/tools/ai/claude-code/helper/claude_helper.c"
  if [ ! -f "$HELPER_SRC" ]; then
    log_error "Helper source not found at $HELPER_SRC"
    return 1
  fi

  if ! clang -O2 -o "$PREFIX/bin/claude" "$HELPER_SRC" &>>"$LOG_FILE"; then
    log_error "Failed to compile claude helper"
    return 1
  fi

  chmod +x "$PREFIX/bin/claude"
  return 0
}

_install_claude_native() {
  _claude_install_deps_native || return 1
  _download_claude_binary || return 1
  _compile_claude_helper || return 1
  log_success "Claude Code installed natively"
  log_info "To run Claude Code, use command: ${D_CYAN}claude${NC}"
  return 0
}

_install_claude_proot() {
  loading "Installing Claude Code (proot-distro)" _install_claude_proot_impl || return 1
  log_info "To run Claude Code, use command: ${D_CYAN}claude${NC}"
  return 0
}

_install_claude_proot_impl() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if ! command -v proot-distro &>/dev/null; then
    yes | pkg install proot-distro &>>"$LOG_FILE"
  fi

  local ubuntu_root
  ubuntu_root="$(_claude_detect_ubuntu_root)"

  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    log_info "Existing Ubuntu container detected at $ubuntu_root (skipping container download)"
  else
    if ! proot-distro list 2>/dev/null | grep -Eiq 'ubuntu.*\(installed\)|\* ubuntu'; then
      log_info "Downloading and installing Ubuntu container via proot-distro..."
      proot-distro install ubuntu &>>"$LOG_FILE"
    fi
    ubuntu_root="$(_claude_detect_ubuntu_root)"
  fi

  if [ -z "$ubuntu_root" ] || [ ! -d "$ubuntu_root" ]; then
    log_error "Ubuntu rootfs not found"
    return 1
  fi

  _claude_proot_ubuntu /bin/bash -c \
    'apt-get update && apt-get upgrade -y && apt-get install -y curl ca-certificates' \
    &>>"$LOG_FILE"

  _claude_proot_ubuntu /bin/bash -c '
		export SHELL=/bin/bash
		export TMPDIR=/tmp
		export HOME=/root
		curl -fsSL https://claude.ai/install.sh | bash
	' &>>"$LOG_FILE"

  if ! _claude_proot_ubuntu test -x /root/.local/bin/claude &>>"$LOG_FILE"; then
    log_error "Claude Code binary not found after install"
    return 1
  fi

  local wrapper_src="$CORE_PATH/tools/ai/claude-code/bin/claude"
  if [ ! -f "$wrapper_src" ]; then
    log_error "Wrapper template not found at $wrapper_src"
    return 1
  fi
  sed "s|__UBUNTU_ROOTFS__|$ubuntu_root|g" "$wrapper_src" >"$PREFIX/bin/claude"
  chmod +x "$PREFIX/bin/claude"

  if ! grep -q '.local/bin' "$ubuntu_root/root/.bashrc" 2>/dev/null; then
    printf '\n# claude-code\nexport PATH=/root/.local/bin:$PATH\n' >>"$ubuntu_root/root/.bashrc"
  fi

  return 0
}

install_claude_code() {
  if command -v claude &>/dev/null || [ -d "$CLAUDE_DATA_DIR" ]; then
    log_warn "Existing Claude Code install detected; reinstalling"
    rm -f "$PREFIX/bin/claude"
    rm -rf "$CLAUDE_DATA_DIR"
  fi

  # Fast scan for existing Ubuntu container
  local ubuntu_root
  ubuntu_root="$(_claude_detect_ubuntu_root)"

  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    log_success "Found existing Ubuntu container at: $ubuntu_root"
    log_info "Auto-selecting Ubuntu container (skipping container re-download)"
    _install_claude_proot
    return $?
  fi

  log_info "Select installation method for Claude Code:"

  read_select "Installation method" SELECTED_METHOD \
    "Native (recommended) - Run with glibc support" \
    "Proot-distro (alternative) - Ubuntu container"

  case "$SELECTED_METHOD" in
  *Native*)
    _install_claude_native
    ;;
  *Proot-distro*)
    _install_claude_proot
    ;;
  esac
}

uninstall_claude_code() {
  log_info "Uninstalling Claude Code..."
  mkdir -p "$(dirname "$LOG_FILE")"

  if [ ! -f "$PREFIX/bin/claude" ]; then
    log_warn "Claude Code is not installed"
    return 1
  fi

  if [ -f "$CLAUDE_DATA_DIR/claude" ]; then
    rm -f "$PREFIX/bin/claude"
    rm -rf "$CLAUDE_DATA_DIR"
    log_success "Claude Code (native) uninstalled"
    return 0
  fi

  _claude_proot_ubuntu /bin/bash -c \
    'rm -f /root/.local/bin/claude && rm -rf /root/.claude && rm -rf /root/.local/share/claude' \
    &>>"$LOG_FILE"

  local ubuntu_bashrc
  ubuntu_bashrc="$(_claude_detect_ubuntu_root)/root/.bashrc"

  if [ -f "$ubuntu_bashrc" ]; then
    sed -i '/# claude-code/d; /export PATH=\/root\/.local\/bin/d' "$ubuntu_bashrc"
  fi

  if rm -f "$PREFIX/bin/claude" &>>"$LOG_FILE"; then
    log_success "Claude Code (proot-distro) uninstalled"
    return 0
  else
    log_error "Failed to uninstall Claude Code"
    return 1
  fi
}

update_claude_code() {
  log_info "Updating Claude Code..."
  mkdir -p "$(dirname "$LOG_FILE")"

  if [ -f "$CLAUDE_DATA_DIR/claude" ]; then
    _install_claude_native
    return $?
  fi

  _claude_proot_ubuntu /bin/bash -c '
		export HOME=/root
		curl -fsSL https://claude.ai/install.sh | bash
	' &>>"$LOG_FILE"

  if ! _claude_proot_ubuntu test -x /root/.local/bin/claude &>>"$LOG_FILE"; then
    log_error "Claude Code binary not found after update"
    return 1
  fi

  log_success "Claude Code (proot-distro) updated"
  return 0
}

reinstall_claude_code() {
  uninstall_claude_code
  install_claude_code
}
