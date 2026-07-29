# bash completion for nwctl
_nwctl()
{
    local cur prev command username
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]:-}"

    case "${prev}" in
        --src|--rosbag-path)
            compopt -o filenames 2>/dev/null || true
            COMPREPLY=( $(compgen -d -- "${cur}") )
            return
            ;;
        --map-name|--bag)
            compopt -o filenames 2>/dev/null || true
            COMPREPLY=( $(compgen -d -- "${cur}") )
            return
            ;;
        --rate)
            COMPREPLY=( $(compgen -W "0.5 1.0 2.0" -- "${cur}") )
            return
            ;;
        --domain-id)
            COMPREPLY=( $(compgen -W "0 1 2 3 4 5 6 7 8 9 10 20 30 200" -- "${cur}") )
            return
            ;;
        --profile)
            COMPREPLY=( $(compgen -W "auto cpu nvidia" -- "${cur}") )
            return
            ;;
        completion)
            COMPREPLY=( $(compgen -W "bash zsh" -- "${cur}") )
            return
            ;;
    esac

    if (( COMP_CWORD == 1 )); then
        local users
        users="$(nwctl _complete users 2>/dev/null)"
        COMPREPLY=( $(compgen -W "register update set-domain unregister list status disk cleanup pull check-env completion version help ${users}" -- "${cur}") )
        return
    fi

    command="${COMP_WORDS[1]}"
    case "${command}" in
        register|update)
            COMPREPLY=( $(compgen -W "--src" -- "${cur}") )
            ;;
        set-domain)
            COMPREPLY=( $(compgen -W "--domain-id --production" -- "${cur}") )
            ;;
        unregister)
            COMPREPLY=( $(compgen -W "--keep-workspace" -- "${cur}") )
            ;;
        cleanup)
            COMPREPLY=( $(compgen -W "--dry-run" -- "${cur}") )
            ;;
        pull)
            COMPREPLY=( $(compgen -W "--profile" -- "${cur}") )
            ;;
        check-env)
            COMPREPLY=( $(compgen -W "all shell planning-sim rosbag-replay --profile" -- "${cur}") )
            ;;
        completion)
            COMPREPLY=( $(compgen -W "bash zsh" -- "${cur}") )
            ;;
        list|status|disk|version|-h|--help|help)
            ;;
        *)
            username="${command}"
            if (( COMP_CWORD == 2 )); then
                COMPREPLY=( $(compgen -W "shell planning-sim rosbag-replay stop clean" -- "${cur}") )
            else
                COMPREPLY=( $(compgen -W "--map-name --rosbag-path --bag --rate --profile" -- "${cur}") )
            fi
            ;;
    esac
}

complete -F _nwctl nwctl
