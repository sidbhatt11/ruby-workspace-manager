# Bash completion for rwm (Ruby Workspace Manager)
# Source this file in your .bashrc or .bash_profile:
#   source "$(gem contents ruby_workspace_manager | grep rwm.bash)"

_rwm_find_workspace_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
}

_rwm_packages() {
  local root
  root="$(_rwm_find_workspace_root)"
  [[ -z "$root" ]] && return

  local dir
  for dir in "$root"/libs/*/ "$root"/apps/*/; do
    [[ -d "$dir" && -f "$dir/Gemfile" ]] && echo "${dir%/}" | xargs basename
  done
}

_rwm() {
  local cur prev words cword
  _init_completion || return

  local commands="init bootstrap new info graph check list run affected cache test spec build help version"
  local global_flags="--verbose --help --version"

  # Find the command (first non-flag argument after rwm)
  local cmd="" cmd_index=0
  local i
  for ((i = 1; i < cword; i++)); do
    case "${words[i]}" in
      --verbose) ;;
      -*) ;;
      *)
        cmd="${words[i]}"
        cmd_index=$i
        break
        ;;
    esac
  done

  # No command yet — complete commands and global flags
  if [[ -z "$cmd" ]]; then
    COMPREPLY=($(compgen -W "$commands $global_flags" -- "$cur"))
    return
  fi

  # Per-command completions
  case "$cmd" in
    init)
      COMPREPLY=($(compgen -W "--vscode" -- "$cur"))
      ;;
    bootstrap | check | list | help | version)
      ;;
    new)
      local pos=$((cword - cmd_index))
      if [[ $pos -eq 1 ]]; then
        COMPREPLY=($(compgen -W "app lib" -- "$cur"))
      fi
      ;;
    info)
      local pos=$((cword - cmd_index))
      if [[ $pos -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$(_rwm_packages)" -- "$cur"))
      fi
      ;;
    graph)
      COMPREPLY=($(compgen -W "--dot --mermaid" -- "$cur"))
      ;;
    affected)
      case "$prev" in
        --base) ;;
        *)
          COMPREPLY=($(compgen -W "--base --committed" -- "$cur"))
          ;;
      esac
      ;;
    cache)
      local pos=$((cword - cmd_index))
      if [[ $pos -eq 1 ]]; then
        COMPREPLY=($(compgen -W "clean" -- "$cur"))
      elif [[ $pos -eq 2 ]]; then
        COMPREPLY=($(compgen -W "$(_rwm_packages)" -- "$cur"))
      fi
      ;;
    run)
      local run_flags="--affected --committed --base --dry-run --no-cache --buffered --concurrency"
      case "$prev" in
        --base | --concurrency)
          # These flags expect a value; don't complete
          ;;
        *)
          # Count positional args (skip flags and flag values)
          local positionals=0
          local skip_next=false
          for ((i = cmd_index + 1; i < cword; i++)); do
            if $skip_next; then
              skip_next=false
              continue
            fi
            case "${words[i]}" in
              --base | --concurrency)
                skip_next=true
                ;;
              -*)
                ;;
              *)
                ((positionals++))
                ;;
            esac
          done

          if [[ "$cur" == -* ]]; then
            COMPREPLY=($(compgen -W "$run_flags" -- "$cur"))
          elif [[ $positionals -eq 0 ]]; then
            # First positional: task name (no completion — user-defined)
            :
          elif [[ $positionals -eq 1 ]]; then
            # Second positional: package name
            COMPREPLY=($(compgen -W "$(_rwm_packages)" -- "$cur"))
          fi
          ;;
      esac
      ;;
    test | spec | build)
      local run_flags="--affected --committed --base --dry-run --no-cache --buffered --concurrency"
      case "$prev" in
        --base | --concurrency)
          ;;
        *)
          local positionals=0
          local skip_next=false
          for ((i = cmd_index + 1; i < cword; i++)); do
            if $skip_next; then
              skip_next=false
              continue
            fi
            case "${words[i]}" in
              --base | --concurrency)
                skip_next=true
                ;;
              -*)
                ;;
              *)
                ((positionals++))
                ;;
            esac
          done

          if [[ "$cur" == -* ]]; then
            COMPREPLY=($(compgen -W "$run_flags" -- "$cur"))
          elif [[ $positionals -eq 0 ]]; then
            COMPREPLY=($(compgen -W "$(_rwm_packages)" -- "$cur"))
          fi
          ;;
      esac
      ;;
  esac
}

complete -F _rwm rwm
