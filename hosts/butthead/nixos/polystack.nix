{
  inputs,
  config,
  ...
}:
# polystack on butthead: the home LEAF — observe/sandbox in the isolated sim
# keyspace (fleet.toml), peering at hierro's zenohd — AND the fleet STORAGE
# NODE (the `archiver` role subscribes live+sim over the mesh and stores
# everything onto the SnapRAID array). Keyless on purpose; branch soaks land
# here (point an extra flake input at the branch and set this instance's
# `package`).
{
  services.polystack.instances.main = {
    enable = true;
    mode = "observe";
    configFile = "${inputs.polystack}/config/fleet.toml";
    host = "butthead";
    loadCredentials = [ "MONITOR_TOKEN:${config.sops.secrets.polystack_monitor_token.path}" ];
  };

  # The monitor's control-plane token (config/secrets/monitor.yaml in the
  # polystack repo; recipients: admin + butthead — the trading key stays out).
  sops.secrets.polystack_monitor_token = {
    sopsFile = "${inputs.polystack}/config/secrets/monitor.yaml";
    key = "monitor_token";
  };

  # The web inspector (mesh-only).
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 8484 ];

  # state_dir (/var/lib/polystack-main) onto the big array: bind mount, so the
  # unit's StateDirectory machinery (DynamicUser chown) works unchanged.
  systemd.tmpfiles.rules = [ "d /mnt/storage/polystack 0755 root root -" ];
  fileSystems."/var/lib/polystack-main" = {
    device = "/mnt/storage/polystack";
    fsType = "none";
    options = [ "bind" ];
  };
}
