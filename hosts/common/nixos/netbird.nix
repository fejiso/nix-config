{
  config, pkgs, ...
}:

{
  services.netbird.enable = true;
  
  # systemd.services.netbird.serviceConfig.EnvironmentFile = config.sops.secrets.netbird-env.path;
}
