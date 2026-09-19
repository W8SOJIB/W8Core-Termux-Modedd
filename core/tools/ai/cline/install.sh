#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/colors"

LOG_FILE="$CORE_CACHE/install_ai.log"

_cline_detect_ubuntu_root() {
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

_cline_proot_ubuntu() {
  proot-distro login \
    --shared-tmp \
    ubuntu \
    -- "$@"
}

_cline_install_deps_native() {
  loading "Installing dependencies" _cline_install_deps_native_impl
}

_cline_install_deps_native_impl() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if [[ ! -f $PREFIX/etc/tls/cert.pem ]]; then
    yes | pkg install ca-certificates &>>"$LOG_FILE" || true
  fi

  declare -A DEPS=(
    ["nodejs-lts"]="node"
    ["git"]="git"
    ["ripgrep"]="rg"
    ["curl"]="curl"
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

_install_cline_npm() {
  loading "Installing Cline CLI (latest)" _install_cline_npm_impl
}

_install_cline_npm_impl() {
  export GYP_DEFINES="android_ndk_path=''"
  export ANDROID_API_LEVEL=24

  if ! npm install -g cline@latest &>>"$LOG_FILE"; then
    log_error "Failed to install Cline CLI"
    return 1
  fi

  if ! command -v cline &>/dev/null && [ ! -f "$PREFIX/bin/cline" ]; then
    log_error "Cline binary not found after npm install"
    return 1
  fi

  return 0
}

_install_cline_native() {
  _cline_install_deps_native || return 1
  _install_cline_npm || return 1
  log_success "Cline installed natively"
  log_info "To run Cline, use command: ${D_CYAN}cline${NC}"
  return 0
}

_install_cline_proot() {
  loading "Installing Cline (proot-distro)" _install_cline_proot_impl || return 1
  log_info "To run Cline, use command: ${D_CYAN}cline${NC}"
  return 0
}

_install_cline_proot_impl() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if ! command -v proot-distro &>/dev/null; then
    yes | pkg install proot-distro &>>"$LOG_FILE"
  fi

  local ubuntu_root
  ubuntu_root="$(_cline_detect_ubuntu_root)"

  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    log_info "Existing Ubuntu container detected at $ubuntu_root (skipping container download)"
  else
    if ! proot-distro list 2>/dev/null | grep -Eiq 'ubuntu.*\(installed\)|\* ubuntu'; then
      log_info "Downloading and installing Ubuntu container via proot-distro..."
      proot-distro install ubuntu &>>"$LOG_FILE"
    fi
    ubuntu_root="$(_cline_detect_ubuntu_root)"
  fi

  if [ -z "$ubuntu_root" ] || [ ! -d "$ubuntu_root" ]; then
    log_error "Ubuntu rootfs not found"
    return 1
  fi

  _cline_proot_ubuntu /bin/bash -c \
    'apt-get update && apt-get install -y curl ca-certificates nodejs npm git' \
    &>>"$LOG_FILE"

  _cline_proot_ubuntu /bin/bash -c \
    'npm install -g cline@latest' \
    &>>"$LOG_FILE"

  local wrapper_src="$CORE_PATH/tools/ai/cline/bin/cline"
  if [ ! -f "$wrapper_src" ]; then
    log_error "Wrapper template not found at $wrapper_src"
    return 1
  fi

  sed "s|__UBUNTU_ROOTFS__|$ubuntu_root|g" "$wrapper_src" >"$PREFIX/bin/cline"
  chmod +x "$PREFIX/bin/cline"

  log_success "Cline installed in Ubuntu container"
  return 0
}

install_cline() {
  if command -v cline &>/dev/null; then
    log_warn "Existing Cline install detected; reinstalling"
    rm -f "$PREFIX/bin/cline" 2>/dev/null || true
  fi

  # Fast scan for existing Ubuntu container
  local ubuntu_root
  ubuntu_root="$(_cline_detect_ubuntu_root)"

  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    log_success "Found existing Ubuntu container at: $ubuntu_root"
    log_info "Auto-selecting Ubuntu container for Cline (skipping container re-download)"
    _install_cline_proot
    return $?
  fi

  log_info "Select installation method for Cline:"

  read_select "Installation method" SELECTED_METHOD \
    "Native (recommended) - Node.js npm package" \
    "Proot-distro (alternative) - Ubuntu container"

  case "$SELECTED_METHOD" in
  *Native*)
    _install_cline_native
    ;;
  *Proot-distro*)
    _install_cline_proot
    ;;
  esac
}

uninstall_cline() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if ! command -v cline &>/dev/null && [ ! -f "$PREFIX/bin/cline" ]; then
    log_warn "Cline is not installed"
    return 1
  fi

  loading "Uninstalling Cline" _uninstall_cline_impl
}

_uninstall_cline_impl() {
  # Native npm uninstall
  if command -v npm &>/dev/null; then
    npm uninstall -g cline &>>"$LOG_FILE" || true
  fi

  # Proot uninstall if container exists
  local ubuntu_root
  ubuntu_root="$(_cline_detect_ubuntu_root)"
  if [ -n "$ubuntu_root" ] && [ -d "$ubuntu_root" ]; then
    _cline_proot_ubuntu /bin/bash -c 'npm uninstall -g cline' &>>"$LOG_FILE" || true
  fi

  rm -f "$PREFIX/bin/cline" 2>/dev/null || true
  hash -d cline 2>/dev/null || true
  hash -r 2>/dev/null || true

  log_success "Cline uninstalled"
  return 0
}

update_cline() {
  mkdir -p "$(dirname "$LOG_FILE")"

  if ! command -v cline &>/dev/null && [ ! -f "$PREFIX/bin/cline" ]; then
    log_warn "Cline is not installed"
    return 1
  fi

  loading "Updating Cline to latest version" _update_cline_impl
}

_update_cline_impl() {
  local is_proot=false
  if [ -f "$PREFIX/bin/cline" ] && grep -q "proot-distro login" "$PREFIX/bin/cline" 2>/dev/null; then
    is_proot=true
  fi

  if [ "$is_proot" = "true" ]; then
    _cline_proot_ubuntu /bin/bash -c 'npm install -g cline@latest' &>>"$LOG_FILE"
    log_success "Cline (proot) updated to latest"
    return 0
  fi

  export GYP_DEFINES="android_ndk_path=''"
  export ANDROID_API_LEVEL=24

  if ! npm install -g cline@latest &>>"$LOG_FILE"; then
    log_error "Failed to update Cline"
    return 1
  fi

  log_success "Cline updated to latest"
  return 0
}

reinstall_cline() {
  uninstall_cline
  install_cline
}
