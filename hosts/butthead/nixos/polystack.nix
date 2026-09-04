{
  inputs,
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
  };

  # state_dir (/var/lib/polystack-main) onto the big array: bind mount, so the
  # unit's StateDirectory machinery (DynamicUser chown) works unchanged.
  systemd.tmpfiles.rules = [ "d /mnt/storage/polystack 0755 root root -" ];
  fileSystems."/var/lib/polystack-main" = {
    device = "/mnt/storage/polystack";
    options = [ "bind" ];
  };
}
