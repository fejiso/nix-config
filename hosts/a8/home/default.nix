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
    ../../../hosts/common/home
  ];

  # Server-specific packages (CLI only)
  home.packages = with pkgs; [
    # Server administration tools
    docker-compose
    kubectl
    helm
    terraform
    ansible
    
    # Monitoring tools
    htop
    iotop
    nethogs
    
    # Network tools
    nmap
    tcpdump
    wireshark-cli
  ];

  # Disable GUI-related services
  services.redshift.enable = lib.mkForce false;
}
