{ ... }: {
  flake.modules.homeManager.zsh =
{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    initContent = ''
      # Update GPG_TTY for each new shell
      export GPG_TTY=$(tty)

      # Refresh gpg-agent tty in case it's running
      gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1

      # Hand off to fish for interactive use. On corp machines (devdesktop,
      # work-laptop) the login shell is zsh, so fish's interactiveShellInit —
      # which sets up PATH (incl. ~/.toolbox/bin) — never runs unless we exec
      # into it here. Only for interactive shells; skipped when launched from
      # fish (so `zsh` from a fish prompt still drops you into zsh) or when
      # NO_FISH is set as an escape hatch. exec replaces the process, so there
      # is no loop — fish does not source zshrc.
      if [[ $- == *i* && -z "$NO_FISH" ]] && command -v fish >/dev/null 2>&1; then
        case "$(ps -o comm= -p $PPID 2>/dev/null)" in
          *fish) ;;
          *) exec fish ;;
        esac
      fi
    '';
  };
}
;
}
