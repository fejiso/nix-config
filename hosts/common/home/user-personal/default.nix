{ lib, config, ... }:
{
  programs.git = {
    userName = lib.mkForce "z-247";
  };
}