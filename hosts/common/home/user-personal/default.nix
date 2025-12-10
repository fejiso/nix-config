{ lib, config, ... }:
{
  programs.git = {
    settings.user.name = lib.mkForce "z-247";
  };
}