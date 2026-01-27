{ config, pkgs, ... }:

{
  programs.keychain = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    # Only use gpg agent since we are using gpg-agent with ssh support
    agents = [ "gpg" ];
    # Explicitly list keys if needed, or let it discover
    keys = [ "id_ed25519" "id_rsa" ];
  };
}
