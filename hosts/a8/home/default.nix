# A8 specific home-manager configuration (server/headless)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
  ];

  # Server-specific packages (CLI only)
  home.packages = with pkgs; [
    # Server administration tools
    
    # Monitoring tools
    htop
    iotop
    nethogs
    
    # Network tools
    nmap
    tcpdump
  ];

  # Disable GUI-related services
  services.redshift.enable = lib.mkForce false;
}
