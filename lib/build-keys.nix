{ lib, ... }:
{
  # Shared SSH pubkey for the role account `nix-ssh` on every builder.
  # Private half lives in secrets/nix-builder.yaml as a sops secret deployed to
  # /run/secrets/nix-builder-key. Safe to share because nix-ssh's forced command
  # is locked to `nix-daemon --stdio --option builders ""` (see
  # flake-modules/system/distributed-build.nix) — inbound builds only, no
  # re-delegation.
  nixBuilderPublicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIET73bXt5BAGlLTmYQh4JZGq6I3cfAUoihP/nk+KqQZo nix-builder@fleet";

  keys = {
    butthead = {
      hostPublicKey = "AAAAC3NzaC1lZDI1NTE5AAAAIDa46hBmT7aRcNtTSKRmzTG8VBBrf9dU+GsUMgMzS7ld";
      nixPublicKey = "butthead.netbird.cloud:kK2K7QvMCdOaWkH2WeVHZegdwffpq+WnSxrFQ83kQAc=";
    };
    hierro = {
      hostPublicKey = "AAAAC3NzaC1lZDI1NTE5AAAAIBgTN8rJvs9tZlSA0t3lNQX4MY15aJWUjxASTz32NdHt";
      nixPublicKey = "hierro.netbird.cloud:avFnbUhkKpj22+Xso2AWrjEZNu7m8VeeNLBvuDiv1xk=";
    };
    blacktop = {
      hostPublicKey = "AAAAC3NzaC1lZDI1NTE5AAAAINQePaMUwEu3oPfVMg/Yk9BiX6QbDmxRBC3Icnd1GkGQ";
      nixPublicKey = "blacktop.netbird.cloud:B5ESfgNFS512fO1c6AlX3kW7L0gp77vC6FdU/KhrEEI=";
    };
    elitedex = {
      hostPublicKey = "AAAAC3NzaC1lZDI1NTE5AAAAIIjL5IsHvPwtZhjj3VYpcKMoA68f7MlHvayhakVwdG+E";
      nixPublicKey = "";
    };
    lenovix = {
      hostPublicKey = "AAAAC3NzaC1lZDI1NTE5AAAAIKjSXKkOBTwOny1O6ssb4yFOuntAKh07qiDjhJnVRXV2";
      nixPublicKey = "";
    };
    # Aarch64 builder (Ubuntu 22.04, single-user Nix). Login user is `ubuntu`
    # because there's no nix-daemon / no /etc/nix/nix.conf to configure a
    # role account against.
    amp1 = {
      hostPublicKey = "AAAAC3NzaC1lZDI1NTE5AAAAIAM47unCeN2EA3ORIgufS2hGSDQ2DPNE5AOeo7Gki91X";
      nixPublicKey = "";
    };
  };
}
