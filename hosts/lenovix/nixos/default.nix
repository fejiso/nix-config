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

  # Intel Core i5-6500T (Skylake)
  hardware.cpu.tune = {
    cpu = "skylake";
    group = "x86-64-v3";
  };

  # Export the SDRplay RSP1 over Netbird with server-side VFO/decimation and compression.
  # Lazy acquisition leaves it free for SDR++, SoapySDR, and local tools when idle.
  sdr.sdrangelServer = {
    enable = true;
    hardwareType = "SoapySDR";
    serial = "sdrplay-0";
  };

  # Export attached pre-1.0 TTGO LoRa32 MeshCore kiss_modem over NetBird (:7620 on wt0)
  services.kiss-modem.enable = true;

  # System state version
  system.stateVersion = "25.05";
}
