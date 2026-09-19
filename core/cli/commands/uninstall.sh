#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/colors"

uninstall_main() {

  if [[ $# -eq 0 ]]; then
    _uninstall_core_system
    return
  fi

  # Separate module target from tool flags
  local module_target=""
  local -a tool_flags=()

  for arg in "$@"; do
    if [[ "$arg" == --* ]]; then
      local flag="${arg#--}"
      tool_flags+=("$flag")
    elif [[ -z "$module_target" ]]; then
      module_target="$arg"
    fi
  done

  # If no module target specified, show error
  if [[ -z "$module_target" ]]; then
    log_error "No target specified"
    echo "Run 'core uninstall' to see available targets"
    return 1
  fi

  # If no tool flags, uninstall entire module (original behavior)
  if [[ ${#tool_flags[@]} -eq 0 ]]; then
    _uninstall_full_module "$module_target"
  else
    # Uninstall specific tools
    _uninstall_specific_tools "$module_target" "${tool_flags[@]}"
  fi
}

# Uninstall entire module (original behavior)
_uninstall_full_module() {
  local target="$1"

  case "$target" in
  core)
    _uninstall_core_system
    ;;
  lang)
    import "@/modules/lang"
    uninstall_lang
    ;;
  db)
    import "@/modules/db"
    uninstall_db
    ;;
  ai)
    import "@/modules/ai"
    uninstall_ai
    ;;
  editor)
    import "@/modules/editor"
    uninstall_editor
    ;;
  dev)
    import "@/modules/dev"
    uninstall_dev
    ;;
  npm)
    import "@/modules/npm"
    uninstall_npm
    ;;
  shell)
    import "@/modules/shell"
    uninstall_shell
    ;;
  ui)
    import "@/modules/ui"
    uninstall_ui
    ;;
  auto)
    import "@/modules/auto"
    uninstall_auto
    ;;
  *)
    log_warn "Unknown uninstall target: $target"
    echo "Run 'core uninstall' to see available targets"
    ;;
  esac
}

_uninstall_core_system() {
  separator
  box "Uninstalling W8Core-Termux-Moded"
  separator
  echo

  log_warn "Removing Core command, repository, data, cache, and config"
  echo

  rm -f "$PREFIX/bin/core"
  rm -rf "$HOME/.local/share/core-termux"
  rm -rf "$HOME/.local/share/core-termux-data"
  rm -rf "$HOME/.cache/core-termux"
  rm -rf "$HOME/.config/core-termux"

  log_success "W8Core-Termux-Moded removed completely"
  echo
}

# Uninstall specific tools within a module
_uninstall_specific_tools() {
  local module="$1"
  shift
  local -a tools=("$@")

  case "$module" in
  ai)
    import "@/tools/ai/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      claude-code)
        uninstall_claude_code
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      opencode)
        uninstall_opencode
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      kilocode-cli)
        uninstall_kilocode_cli
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      cline)
        uninstall_cline
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown AI tool: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count AI tool(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count tool(s) failed to uninstall"
    fi
    echo
    ;;  db)
    import "@/tools/db/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      postgresql)
        uninstall_postgresql
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      mariadb)
        uninstall_mariadb
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      sqlite)
        uninstall_sqlite
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      mongodb)
        uninstall_mongodb
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown database: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count database(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count database(s) failed to uninstall"
    fi
    echo
    ;;
  dev)
    import "@/tools/dev/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      gh)
        uninstall_gh
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      wget)
        uninstall_wget
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      curl)
        uninstall_curl
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      lsd)
        uninstall_lsd
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      bat)
        uninstall_bat
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      proot)
        uninstall_proot
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      ncurses)
        uninstall_ncurses
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      tmate)
        uninstall_tmate
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      cloudflared)
        uninstall_cloudflared
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      translate)
        uninstall_translate
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      html2text)
        uninstall_html2text
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      jq)
        uninstall_jq
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      bc)
        uninstall_bc
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      tree)
        uninstall_tree
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      fzf)
        uninstall_fzf
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      imagemagick)
        uninstall_imagemagick
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      shfmt)
        uninstall_shfmt
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      make)
        uninstall_make
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      udocker)
        uninstall_udocker
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown tool: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count tool(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count tool(s) failed to uninstall"
    fi
    echo
    ;;
  npm)
    import "@/tools/npm/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      typescript)
        uninstall_typescript
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      nestjs)
        uninstall_nestjs
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      prettier)
        uninstall_prettier
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      live-server)
        uninstall_live_server
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      localtunnel)
        uninstall_localtunnel
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      vercel)
        uninstall_vercel
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      markserv)
        uninstall_markserv
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      psqlformat)
        uninstall_psqlformat
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      ncu)
        uninstall_ncu
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      ngrok)
        uninstall_ngrok
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      turbopack)
        uninstall_turbopack
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown node module: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count Node.js module(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count module(s) failed to uninstall"
    fi
    echo
    ;;
  lang)
    import "@/tools/lang/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      nodejs)
        uninstall_npmjs
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      python)
        uninstall_python
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      perl)
        uninstall_perl
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      php)
        uninstall_php
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      rust)
        uninstall_rust
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      clang)
        uninstall_clang
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      golang)
        uninstall_golang
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown language: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count language(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count language(s) failed to uninstall"
    fi
    echo
    ;;
  shell)
    import "@/tools/shell/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      powerlevel10k)
        uninstall_powerlevel10k
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      zsh-defer)
        uninstall_zsh_defer
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      zsh-autosuggestions)
        uninstall_zsh_autosuggestions
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      zsh-syntax-highlighting)
        uninstall_zsh_syntax_highlighting
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      history-substring)
        uninstall_history_substring
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      zsh-completions)
        uninstall_zsh_completions
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      fzf-tab)
        uninstall_fzf_tab
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      you-should-use)
        uninstall_you_should_use
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      zsh-autopair)
        uninstall_zsh_autopair
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      better-npm)
        uninstall_better_npm
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown plugin: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count plugin(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count plugin(s) failed to uninstall"
    fi
    echo
    ;;
  editor)
    import "@/tools/editor/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      neovim)
        uninstall_neovim
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      nvchad)
        uninstall_nvchad
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown editor component: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count editor component(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count component(s) failed to uninstall"
    fi
    echo
    ;;
  ui)
    import "@/tools/ui/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      font)
        uninstall_font
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      extra-keys)
        uninstall_extra_keys
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      cursor)
        uninstall_cursor
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      banner)
        uninstall_banner
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown UI component: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count UI component(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count component(s) failed to uninstall"
    fi
    echo
    ;;
  auto)
    import "@/tools/auto/all"
    local uninstalled_count=0
    local failed_count=0

    for tool in "${tools[@]}"; do
      case "$tool" in
      n8n)
        uninstall_n8n
        case $? in 0) ((uninstalled_count++));; 1) ((failed_count++));; esac
        ;;
      *)
        log_warn "Unknown automation tool: --$tool"
        ;;
      esac
    done

    echo
    if [[ $uninstalled_count -gt 0 ]]; then
      log_success "$uninstalled_count automation tool(s) uninstalled"
    fi
    if [[ $failed_count -gt 0 ]]; then
      log_warn "$failed_count tool(s) failed to uninstall"
    fi
    echo
    ;;
  *)
    log_warn "Unknown uninstall target: $module"
    echo "Run 'core uninstall' to see available targets"
    ;;
  esac
}
