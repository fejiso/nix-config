{ inputs, outputs, lib, config, pkgs, hostname, ... }: {
  home = {
    username = "ubuntu";
    homeDirectory = "/home/ubuntu";
  };

  # Using bare `default` HM class — no Wayland modules to disable.

  home.packages = with pkgs; [
    # add amp1-specific tooling here as needed
  ];
}
