{
  config, pkgs, ...
}:

{
  sops.secrets.netbird-env = { 
    sopsFile = ../../../secrets/netbird.env;
    format = "dotenv";
    neededForUsers = true;
  };

  services.netbird = {
    enable = true;
    package = pkgs.netbird;
    clients = {
      home = {
        port = 51820;
        config = {
          environment = config.sops.secrets.netbird-env.path; 
        };
      };
    };
  };
}
