{ ... }: {
  flake.modules.homeManager.gpg-agent =
{
  pkgs, ...
}: {
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry-curses;
    defaultCacheTtl = 86400;  # 24 hours
    maxCacheTtl = 86400;      # 24 hours
    extraConfig = ''
      allow-loopback-pinentry
      allow-preset-passphrase
    '';
  };
}
;
}
