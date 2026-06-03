{ ... }: {
  flake.modules.nixos.default =
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
      extraGroups = ["wheel" "networkmanager" "audio" "video" "docker" "pipewire" "cdrom" "dialout" "tty" "scanner" "lp"];
      shell = pkgs.fish;  # Changed default shell to fish
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFihyYRTqPTs7dzyirRCxGrkFuV5ymWkCJp2uPLgJ/7o username@daremote"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICQ5a7p+8LrnKTch/UUAJ3YpAYT6PS8fM+0FKtSspZ5U"
      ];
    };
    root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICQ5a7p+8LrnKTch/UUAJ3YpAYT6PS8fM+0FKtSspZ5U"
      ];
    };
  };

  # Enable shells system-wide
  programs.zsh.enable = true;
  programs.fish.enable = true;

  # Enable lingering for z-247 user
  systemd.services.user-linger-z-247 = {
    description = "Enable lingering for z-247 user";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger z-247";
    };
  };
}
;
}
