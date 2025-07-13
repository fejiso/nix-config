{
  config, pkgs, ...
}:

{
  sops.secrets.netbird_setup_key = { 
    sopsFile = ../../secrets/netbird.env;
    neededForUsers = true;
  };

  services.netbird = {
    enable = true;
    package = pkgs.netbird;
    settings = {
      managementURL = "https://api.netbird.io:443";
      adminURL = "https://app.netbird.io:443";
      setupKeys = [
        config.sops.secrets.netbird_setup_key
      ];
    };
  };
}
