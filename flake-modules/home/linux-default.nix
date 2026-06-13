{ config, ... }: {
  # `linux-default` is the home-manager class for Linux hosts: it includes
  # everything in `default` plus the Wayland-only modules (kanshi/niri/sway
  # plus the body in linux-base.nix). Hosts on Linux (every NixOS host) get
  # this via `flake-modules/system/home-manager.nix`; darwin hosts get bare
  # `default` instead.
  flake.modules.homeManager.linux-default = {
    imports = [
      config.flake.modules.homeManager.default
      config.flake.modules.homeManager.kanshi
      config.flake.modules.homeManager.niri
      config.flake.modules.homeManager.sway
      config.flake.modules.homeManager.hyprlock
      config.flake.modules.homeManager.noctalia
      config.flake.modules.homeManager.bose-soundtouch
    ];
  };
}
