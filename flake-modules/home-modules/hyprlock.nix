{ ... }: {
  flake.modules.homeManager.hyprlock =
  { lib, ... }:
  {
    programs.hyprlock = {
      enable = lib.mkForce false;
    };
  };
}
