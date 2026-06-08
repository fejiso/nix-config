{ ... }: {
  # Native DLNA audio sink via pa-dlna (https://gitlab.com/xdegaye/pa-dlna).
  #
  # The Bose SoundTouch 30 is a full UPnP/DLNA MediaRenderer (AVTransport +
  # RenderingControl + ConnectionManager, sinks: L16/MP3/FLAC/WAV/AAC) — it just
  # doesn't advertise AirPlay (`_raop._tcp`), so PipeWire's raop-discover can't
  # use it. pa-dlna discovers DLNA renderers over SSDP and exposes each as a
  # PipeWire sink, encoding on the fly — so the speaker shows up as a normal
  # output device ("ST30 Living Room") that any app can play to. No bridge
  # scripts, no fixed IP (the speaker roams DHCP; SSDP/mDNS handle that).
  #
  # Gotcha handled below: SSDP M-SEARCH replies arrive *unicast* from the device
  # (src :1900), which the stateful firewall won't associate with the multicast
  # query and drops — so discovery silently finds nothing. We pin
  # `--msearch-port` to a known UDP port and open it (+1900 + the http port) in
  # the firewall (see desktop.nix).
  flake.modules.homeManager.bose-soundtouch =
  { lib, pkgs, config, ... }:

  with lib;

  let
    cfg = config.services.boseSoundtouch;
  in
  {
    options.services.boseSoundtouch = {
      enable = mkEnableOption "pa-dlna DLNA audio bridge (Bose SoundTouch et al. as PipeWire sinks)";

      httpPort = mkOption {
        type = types.port;
        default = 8092;
        description = ''
          TCP port for pa-dlna's HTTP server. Renderers fetch the encoded audio
          stream from this port, so it must be open toward their subnet.
        '';
      };

      msearchPort = mkOption {
        type = types.port;
        default = 1901;
        description = ''
          Fixed local UDP port for receiving SSDP M-SEARCH responses. Pinned (vs.
          pa-dlna's ephemeral default) so it can be opened in the firewall — the
          replies are unicast from the renderer and would otherwise be dropped.
        '';
      };

      logLevel = mkOption {
        type = types.enum [ "debug" "info" "warning" "error" ];
        default = "info";
        description = "pa-dlna log level (journald).";
      };
    };

    config = mkIf cfg.enable {
      # pa-dlna runs in the user's PipeWire session and creates a sink per
      # discovered renderer. Mirrors the unit shipped with pa-dlna (Type=notify
      # via python-systemd), with an ExecStartPre delay because pipewire-pulse is
      # Type=simple and libpulse may otherwise connect before it's ready.
      systemd.user.services.pa-dlna = {
        Unit = {
          Description = "pa-dlna — forward PipeWire streams to DLNA/UPnP renderers";
          Documentation = "https://pa-dlna.readthedocs.io/en/stable/";
          After = [ "pipewire-pulse.service" "wireplumber.service" ];
          Wants = [ "pipewire-pulse.service" ];
        };
        Service = {
          Type = "notify";
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
          ExecStart = concatStringsSep " " [
            "${pkgs.pa-dlna}/bin/pa-dlna"
            "--systemd"
            "--msearch-port ${toString cfg.msearchPort}"
            "--port ${toString cfg.httpPort}"
            "--loglevel ${cfg.logLevel}"
          ];
          Restart = "on-failure";
          RestartSec = 5;
          Slice = "session.slice";
          NoNewPrivileges = true;
          UMask = "0077";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
