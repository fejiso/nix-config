{ lib, config, ... }:
{
  programs.git = {
    settings.user.name = lib.mkForce "Fernando Jiménez";
  };
}