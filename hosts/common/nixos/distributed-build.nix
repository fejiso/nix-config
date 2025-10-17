{ config, lib, pkgs, ... }:

{
  # Enable experimental features for flakes and nix-command
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Configure remote builders (replace with actual hostnames/IPs and SSH keys)
  # This is a placeholder. Users will need to add their specific build machines here.
  # Example:
  # nix.buildMachines = [
  #   { hostName = "other-nixos-host";
  #     system = "x86_64-linux";
  #     sshKey = "/etc/nixos/ssh_keys/id_ed25519_nix_build";
  #     maxJobs = 4;
  #     speedFactor = 1;
  #     mandatoryFeatures = [ "kvm" ]; # Example for specific features
  #   }
  # ];

  # Optional: Enable nix-ssh-serve for easier setup of remote builders
  # services.nix-ssh-serve.enable = true;
}
