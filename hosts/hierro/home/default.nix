# Hierro home-manager configuration (server). It now uses the CLI `default`
# home (no Wayland/desktop modules), so there's nothing GUI to disable.
{ pkgs, ... }: {
  home.packages = with pkgs; [
    # server-only extras go here
  ];
}
