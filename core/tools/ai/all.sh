#!/bin/bash

import "@/utils/log"

LOG_FILE="$CORE_CACHE/install_ai.log"

AI_TOOLS=(
  "claude-code"
  "opencode"
  "kilocode-cli"
  "cline"
)

source "$(dirname "$BASH_SOURCE")/claude-code/install.sh"
source "$(dirname "$BASH_SOURCE")/opencode/install.sh"
source "$(dirname "$BASH_SOURCE")/kilocode-cli/install.sh"
source "$(dirname "$BASH_SOURCE")/cline/install.sh"

_install_ai_tool() {
  case "$1" in
  claude-code) install_claude_code ;;
  opencode) install_opencode ;;
  kilocode-cli) install_kilocode_cli ;;
  cline) install_cline ;;
  *) log_warn "Unknown AI tool: --$1"; return 2 ;;
  esac
}

_uninstall_ai_tool() {
  case "$1" in
  claude-code) uninstall_claude_code ;;
  opencode) uninstall_opencode ;;
  kilocode-cli) uninstall_kilocode_cli ;;
  cline) uninstall_cline ;;
  *) log_warn "Unknown AI tool: --$1"; return 2 ;;
  esac
}

_update_ai_tool() {
  case "$1" in
  claude-code) update_claude_code ;;
  opencode) update_opencode ;;
  kilocode-cli) update_kilocode_cli ;;
  cline) update_cline ;;
  *) log_warn "Unknown AI tool: --$1"; return 2 ;;
  esac
}

_reinstall_ai_tool() {
  case "$1" in
  claude-code) reinstall_claude_code ;;
  opencode) reinstall_opencode ;;
  kilocode-cli) reinstall_kilocode_cli ;;
  cline) reinstall_cline ;;
  *) log_warn "Unknown AI tool: --$1"; return 2 ;;
  esac
}

_run_all_ai_tools() {
  local action="$1"
  local success_count=0
  local failed_count=0
  local tool

  for tool in "${AI_TOOLS[@]}"; do
    "_${action}_ai_tool" "$tool"
    case $? in
    0) ((success_count++)) ;;
    1) ((failed_count++)) ;;
    esac
  done

  return 0
}

install_all_ai_tools() {
  _run_all_ai_tools install
}

uninstall_all_ai_tools() {
  _run_all_ai_tools uninstall
}

update_all_ai_tools() {
  _run_all_ai_tools update
}

reinstall_all_ai_tools() {
  _run_all_ai_tools reinstall
}