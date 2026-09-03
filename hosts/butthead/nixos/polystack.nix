{
  inputs,
  ...
}:
# polystack on butthead: the home LEAF — observe/sandbox in the isolated sim
# keyspace (fleet.toml), peering at hierro's zenohd. Keyless on purpose;
# branch soaks land here (point an extra flake input at the branch and set
# this instance's `package`).
{
  services.polystack.instances.main = {
    enable = true;
    mode = "observe";
    configFile = "${inputs.polystack}/config/fleet.toml";
    host = "butthead";
  };
}
