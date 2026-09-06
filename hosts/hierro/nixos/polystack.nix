{
  inputs,
  config,
  ...
}:
# polystack on hierro: the fleet's ROOT site — trade host (~4ms from
# clob.polymarket.com) + the zenoh router every leaf peers with.
{
  services.polystack-zenohd.enable = true; # wt0:7447, mesh-only

  # The trading key lives in the POLYSTACK repo (its own .sops.yaml pins the
  # recipients: admin user + trade hosts) — the encrypted file rides the
  # flake input; this host only declares which key to decrypt.
  sops.secrets.polymarket_private_key = {
    sopsFile = "${inputs.polystack}/config/secrets/polystack.yaml";
    key = "polymarket_private_key";
  };

  services.polystack.instances.main = {
    enable = true;
    mode = "trade";
    configFile = "${inputs.polystack}/config/fleet.toml";
    host = "hierro";
    loadCredentials = [ "POLYMARKET_PRIVATE_KEY:${config.sops.secrets.polymarket_private_key.path}" ];
  };

  # hierro's hourly nix-builder pre-builds fleet closures: fetching the
  # git+ssh forgejo inputs as root needs the read-only deploy key.
  # SETUP (manual, once): register /root/.ssh/forgejo_deploy.pub as a
  # read-only deploy key on fer/polystack AND fer/polyboh in forgejo.
  system.activationScripts.rootForgejoSsh = ''
    mkdir -p /root/.ssh
    cat > /root/.ssh/config <<'CFG'
Host hierro.netbird.cloud localhost
  Port 2222
  User forgejo
  IdentityFile /root/.ssh/forgejo_deploy
  StrictHostKeyChecking accept-new
CFG
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/config
  '';
}
