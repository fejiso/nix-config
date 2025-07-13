# A8 specific NixOS configuration (server/headless)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    (inputs.airspy-adsb-bin + "/modules/module.nix")
  ];

  # Server-specific configuration (no GUI)
  # Enable Docker for containerized services
  virtualisation.docker.enable = true;
  
  # Additional server packages
  environment.systemPackages = with pkgs; [
    docker-compose
    nginx
    postgresql
    redis
    airspy-adsb
  ];

  # Server-specific services
  services.nginx.enable = true;
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
  };
  
  services.redis.servers."" = {
    enable = true;
    port = 6379;
  };

  services.airspy-adsb = {
    enable = true;
  };
}
