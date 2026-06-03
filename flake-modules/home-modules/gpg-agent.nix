{ ... }: {
  flake.modules.homeManager.gpg-agent =
{
  pkgs, ...
}: {
  services.gpg-agent = {
    enable = true;
    # SSH is handled by the NixOS ssh-agent (programs.ssh.startAgent), not
    # gpg-agent: gpg-agent's pinentry-curses needs a controlling TTY and breaks
    # under niri/Wayland (prompt spawns on an unreachable terminal).
    enableSshSupport = false;
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
