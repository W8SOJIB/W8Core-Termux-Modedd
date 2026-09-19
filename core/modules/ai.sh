#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/colors"

LOG_FILE="$CORE_CACHE/install_ai.log"

install_ai() {
  separator
  box "Installing AI Tools"
  separator
  echo

  log_info "Select AI tool to install:"
  echo
  mkdir -p "$(dirname "$LOG_FILE")"

  read_select "AI tool" SELECTED_AI_TOOL \
    "OpenCode (recommended)" \
    "Claude Code" \
    "Kilo Code CLI" \
    "Cline"

  local install_rc=0

  case "$SELECTED_AI_TOOL" in
  *OpenCode*)
    _install_selected_ai_tool "opencode"
    install_rc=$?
    ;;
  *Claude*)
    _install_selected_ai_tool "claude-code"
    install_rc=$?
    ;;
  *Kilo*)
    _install_selected_ai_tool "kilocode-cli"
    install_rc=$?
    ;;
  *Cline*)
    _install_selected_ai_tool "cline"
    install_rc=$?
    ;;
  esac

  separator
  echo
  if [[ $install_rc -eq 0 ]]; then
    log_success "$SELECTED_AI_TOOL installed successfully"
  else
    log_error "$SELECTED_AI_TOOL failed to install"
  fi

  return $install_rc
}

_install_selected_ai_tool() {
  import "@/tools/ai/all"
  _install_ai_tool "$1"
  local rc=$?

  if [[ $rc -eq 2 ]]; then
    return 0
  fi

  return $rc
}
_install_ai_tools_wrapper() {
  import "@/tools/ai/all"
  install_all_ai_tools
}

uninstall_ai() {
  if ! command -v opencode &>/dev/null && ! command -v claude &>/dev/null && ! command -v kilo &>/dev/null && ! command -v cline &>/dev/null; then
    log_info "AI Tools are not installed"
    return 0
  fi
  separator
  box "Uninstalling AI Tools"
  separator
  echo

  log_info "Uninstalling AI tools..."

  _uninstall_ai_tools_wrapper
  log_success "AI tools uninstalled"
}

_uninstall_ai_tools_wrapper() {
  import "@/tools/ai/all"
  uninstall_all_ai_tools
}

update_ai() {
  separator
  box "Updating AI Tools"
  separator
  echo

  log_info "Updating AI tools..."

  _update_ai_tools_wrapper
  log_success "AI tools updated"
}

_update_ai_tools_wrapper() {
  import "@/tools/ai/all"
  update_all_ai_tools
}

reinstall_ai() {
  separator
  box "Reinstalling AI Tools"
  separator
  echo

  log_info "Reinstalling AI tools..."
  echo

  _reinstall_ai_tools_wrapper
  log_success "AI tools reinstalled successfully"
  separator
  echo
  list_item "Claude Code"
  list_item "OpenCode"
  list_item "Kilo Code CLI"
  list_item "Cline"
  echo
}

_reinstall_ai_tools_wrapper() {
  import "@/tools/ai/all"
  reinstall_all_ai_tools
}
