# Lenovix specific NixOS configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    # Add appropriate nixos-hardware module for your specific Lenovo model
    # inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-carbon-gen11
  ];

  # Host-specific networking
  networking.hostName = "lenovix";

  # Export the Airspy over Netbird with server-side VFO/decimation and compression.
  # Lazy acquisition leaves it free for SDR++, SoapySDR, and local tools when idle.
  sdr.sdrangelServer = {
    enable = true;
    hardwareType = "Airspy";
    serial = "4a464c83631200b";
  };

  # Tdarr worker node (native NixOS service)
  services.tdarr-worker = {
    enable = true;
  };

  # System state version
  system.stateVersion = "25.05";
}
