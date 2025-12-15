{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    initExtra = ''
      # Update GPG_TTY for each new shell
      export GPG_TTY=$(tty)

      # Refresh gpg-agent tty in case it's running
      gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
    '';
  };
}
