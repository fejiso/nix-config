{ ... }: {
  flake.modules.homeManager.keychain =
{ config, pkgs, ... }:

{
  programs.keychain = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    # Explicitly list keys if needed, or let it discover
    keys = [ "id_ed25519" "id_rsa" ];
  };
}
;
}
