# User configuration
{
  config,
  pkgs,
  ...
}: {
  users.defaultUserShell = pkgs.fish;
  users.users = {
    z-247 = {
      isNormalUser = true;
      description = "z-247";
      extraGroups = ["wheel" "networkmanager" "audio" "video" "docker"];
      shell = pkgs.fish;  # Changed default shell to fish
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICQ5a7p+8LrnKTch/UUAJ3YpAYT6PS8fM+0FKtSspZ5U"
      ];
    };
  };

  # Enable shells system-wide
  programs.zsh.enable = true;
  programs.fish.enable = true;
}
