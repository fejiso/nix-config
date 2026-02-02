{ config, lib, pkgs, hostname, ... }:

{
  imports = [
    ../../common/home
  ];

  # Minimal home-manager setup for embedded device
  # Most configuration inherited from common/home
  # stateVersion inherited from common/home
}
