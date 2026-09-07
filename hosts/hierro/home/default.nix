# Hierro home-manager configuration (server). It now uses the CLI `default`
# home (no Wayland/desktop modules), so there's nothing GUI to disable.
{ pkgs, ... }: {
  home.packages = with pkgs; [
    # server-only extras go here
  ];

  # Silverbullet notes (user service; mesh-only via the wt0 firewall rule in
  # hosts/hierro/nixos/default.nix, basic auth via SB_USER from sops).
  # Port 3004: 3000 is taken by Forgejo on this host.
  services.silverbullet = {
    enable = true;
    host = "0.0.0.0";
    port = 3004;
    spaceDir = "/home/z-247/dev/silverbullet";
  };
}
