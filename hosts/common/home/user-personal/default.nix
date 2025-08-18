{ lib, config, ... }:
{
  programs.git = {
    userName = lib.mkForce "z-247";
  };
  sops.gnupg.home = "${config.home.homeDirectory}/.gnupg";
}