{ config, lib, pkgs, hostname, ... }:

{
  imports = [
  ];

  # Minimal home-manager setup for embedded device
  # Most configuration inherited from common/home
  # stateVersion inherited from common/home

  # Override heavy packages if needed for embedded device
  # Example: programs.someHeavyTool.enable = lib.mkForce false;
}
