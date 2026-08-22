{ ... }: {
  flake.modules.nixos.bcachefs =
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hardware.bcachefs-support;
in
{
  options.hardware.bcachefs-support = {
    enable = mkEnableOption "bcachefs filesystem support (kernel module + bcachefs-tools)";

    initrd = mkOption {
      type = types.bool;
      default = false;
      description = "Also enable bcachefs in the initrd (needed if any bcachefs filesystem is mounted early, e.g. as root)";
    };
  };

  config = mkIf cfg.enable {
    boot.supportedFilesystems = [ "bcachefs" ];
    boot.initrd.supportedFilesystems = mkIf cfg.initrd [ "bcachefs" ];

    environment.systemPackages = [ pkgs.bcachefs-tools ];
  };
}
;
}
