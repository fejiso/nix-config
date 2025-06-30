# User configuration
{
  config,
  pkgs,
  ...
}: {
  users.users = {
    z-247 = {
      isNormalUser = true;
      description = "z-247";
      extraGroups = ["wheel" "networkmanager" "audio" "video" "docker"];
      shell = pkgs.fish;  # Changed default shell to fish
      openssh.authorizedKeys.keys = [
        # Add your SSH public keys here
      ];
    };
  };

  # Enable shells system-wide
  programs.zsh.enable = true;
  programs.fish.enable = true;
}
