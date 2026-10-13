{ pkgs, ... }: {
  services.microsocks = {
    enable = true;
    ip = "0.0.0.0";
    port = 1080;
  };
}
