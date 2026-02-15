#compdef rwm
# Zsh completion for rwm (Ruby Workspace Manager)
# Add the completions directory to your fpath in .zshrc:
#   fpath=($(gem contents ruby_workspace_manager | grep completions/rwm.zsh | xargs dirname) $fpath)
#   autoload -Uz compinit && compinit

_rwm_find_workspace_root() {
  local dir="${PWD}"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]]; then
      echo "$dir"
      return
    fi
    dir="${dir:h}"
  done
}

_rwm_complete_packages() {
  local root
  root="$(_rwm_find_workspace_root)"
  [[ -z "$root" ]] && return

  local -a packages
  local dir
  for dir in "$root"/libs/*(N/) "$root"/apps/*(N/); do
    [[ -f "$dir/Gemfile" ]] && packages+=("${dir:t}")
  done
  _describe 'package' packages
}

_rwm() {
  local -a commands=(
    'init:Initialize a new rwm workspace'
    'bootstrap:Install deps and run bootstrap tasks in all packages'
    'new:Scaffold a new app or lib'
    'info:Show details about a package'
    'graph:Build and save the dependency graph'
    'check:Validate dependency graph and conventions'
    'list:List all packages in the workspace'
    'run:Run a rake task across all or one package'
    'affected:Show packages affected by current changes'
    'cache:Manage task cache'
    'test:Shortcut for rwm run test'
    'spec:Shortcut for rwm run spec'
    'build:Shortcut for rwm run build'
    'help:Show help'
    'version:Show version'
  )

  local -a global_flags=(
    '--verbose[Enable debug logging]'
    '--help[Show help]'
    '--version[Show version]'
  )

  local -a run_flags=(
    '--affected[Only run on affected packages]'
    '--committed[Only consider committed changes]'
    '--base[Compare against REF instead of auto-detected base]:ref'
    '--dry-run[Show what would run without executing]'
    '--no-cache[Bypass task-level caching]'
    '--buffered[Buffer output per-package and print on completion]'
    '--concurrency[Max parallel workers]:number'
  )

  # If we haven't completed the first argument yet, offer commands
  if (( CURRENT == 2 )); then
    _describe 'command' commands
    return
  fi

  local cmd="${words[2]}"

  case "$cmd" in
    init)
      _arguments -s \
        '--vscode[Generate VSCode .code-workspace file]' \
        $global_flags
      ;;
    bootstrap | check | list | help | version)
      ;;
    new)
      local -a types=('app:Application package' 'lib:Library package')
      case $CURRENT in
        3) _describe 'type' types ;;
        4) _message 'package name' ;;
      esac
      ;;
    info)
      if (( CURRENT == 3 )); then
        _rwm_complete_packages
      fi
      ;;
    graph)
      _arguments -s \
        '--dot[Output in Graphviz DOT format]' \
        '--mermaid[Output in Mermaid format]' \
        $global_flags
      ;;
    affected)
      _arguments -s \
        '--base[Compare against REF instead of auto-detected base]:ref' \
        '--committed[Only consider committed changes]' \
        $global_flags
      ;;
    cache)
      case $CURRENT in
        3) local -a subcmds=('clean:Clear cached task results')
           _describe 'subcommand' subcmds ;;
        4) _rwm_complete_packages ;;
      esac
      ;;
    run)
      _arguments -s \
        $run_flags \
        '1:task' \
        '2:package:_rwm_complete_packages'
      ;;
    test | spec | build)
      _arguments -s \
        $run_flags \
        '1:package:_rwm_complete_packages'
      ;;
  esac
}

_rwm "$@"
