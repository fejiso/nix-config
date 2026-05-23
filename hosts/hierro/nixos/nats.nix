{ config, lib, pkgs, ... }:
{
  services.nats = {
    enable = true;
    jetstream = true;
    # JetStream store_dir defaults to dataDir (/var/lib/nats); module owns it.
    settings = {
      server_name = lib.mkForce "hierro-nats";
      listen = lib.mkForce "0.0.0.0:4222";
      http = "0.0.0.0:8222";
    };
  };

  networking.firewall.interfaces.wt0.allowedTCPPorts = [
    4222 # client
    8222 # monitoring
  ];
}
