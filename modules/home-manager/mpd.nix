{ config, pkgs, lib, ... }:

with lib;

{
  options.services.mpd-stack = {
    enable = mkEnableOption "MPD music stack with ncmpcpp, mpd-sima, and scrobblers";

    musicDirectory = mkOption {
      type = types.str;
      default = "/mnt/user/Music";
      description = "Path to music directory";
    };

    lastfmUsername = mkOption {
      type = types.str;
      default = "";
      description = "Last.fm username for scrobbling";
    };
  };

  config = mkIf config.services.mpd-stack.enable {
    # MPD - Music Player Daemon
    services.mpd = {
      enable = true;
      musicDirectory = config.services.mpd-stack.musicDirectory;
      extraConfig = ''
        audio_output {
          type "pipewire"
          name "PipeWire Sound Server"
        }

        # HTTP streaming output (optional, for remote access)
        audio_output {
          type "httpd"
          name "HTTP Stream"
          encoder "vorbis"
          port "8000"
          bind_to_address "127.0.0.1"
          bitrate "128"
          format "44100:16:1"
          always_on "no"
          tags "yes"
        }

        auto_update "yes"
        auto_update_depth "3"
        follow_outside_symlinks "yes"
        follow_inside_symlinks "yes"
      '';
    };

    # ncmpcpp - Terminal MPD client
    programs.ncmpcpp = {
      enable = true;
      settings = {
        mpd_host = "127.0.0.1";
        mpd_port = 6600;
        mpd_crossfade_time = 3;

        # Visualizer
        visualizer_data_source = "/tmp/mpd.fifo";
        visualizer_output_name = "Visualizer";
        visualizer_in_stereo = "yes";
        visualizer_type = "spectrum";
        visualizer_look = "●▮";

        # UI
        user_interface = "alternative";
        playlist_display_mode = "columns";
        browser_display_mode = "columns";
        search_engine_display_mode = "columns";
        playlist_editor_display_mode = "columns";

        # Progress bar
        progressbar_look = "─░─";

        # Colors
        colors_enabled = "yes";
        main_window_color = "white";
        header_window_color = "cyan";
        volume_color = "green";
        statusbar_color = "white";
        progressbar_color = "cyan";
        progressbar_elapsed_color = "white";

        # Format
        song_list_format = "{$4%a - }{%t}|{$8%f$9}$R{$3(%l)$9}";
        song_status_format = "$b{{$8\"%t\"}} $3by {$4%a}{ $3in $7%b}";
        song_library_format = "{%n - }{%t}|{%f}";

        # Other
        media_library_primary_tag = "album_artist";
        media_library_albums_split_by_date = "no";
        startup_screen = "playlist";
        display_bitrate = "yes";
        ignore_leading_the = "yes";
        external_editor = "nvim";
        use_console_editor = "yes";
      };
      bindings = [
        { key = "j"; command = "scroll_down"; }
        { key = "k"; command = "scroll_up"; }
        { key = "J"; command = [ "select_item" "scroll_down" ]; }
        { key = "K"; command = [ "select_item" "scroll_up" ]; }
        { key = "h"; command = "previous_column"; }
        { key = "l"; command = "next_column"; }
        { key = "g"; command = "move_home"; }
        { key = "G"; command = "move_end"; }
        { key = "n"; command = "next_found_item"; }
        { key = "N"; command = "previous_found_item"; }
      ];
    };

    # mpd-sima and mpdscribble
    home.packages = with pkgs; [ mpd-sima mpdscribble ];

    xdg.configFile."mpd-sima/mpd_sima.cfg".text = ''
      [sima]
      # anthropic's claude recommendation: use lastfm for similarity data
      internal = Crop, Lastfm, Random
      history_duration = 8
      queue_length = 2

      [crop]
      # Keep playlist at reasonable size
      consume = 10
      priority = 10

      [lastfm]
      # Uses last.fm similar artists API (no auth required for similarity lookups)
      queue_mode = track
      single_album = false
      track_to_add = 1
      album_to_add = 0
      depth = 3
      priority = 20

      [random]
      # Fallback when no similar tracks found
      priority = 30
      track_to_add = 1
    '';

    # Systemd service for mpd-sima
    systemd.user.services.mpd-sima = {
      Unit = {
        Description = "MPD-sima autoqueue daemon";
        After = [ "mpd.service" ];
        Requires = [ "mpd.service" ];
      };
      Service = {
        ExecStart = "${pkgs.mpd-sima}/bin/mpd-sima";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # mpdscribble config - secrets are injected at runtime via systemd
    xdg.configFile."mpdscribble/mpdscribble.conf.template".text = ''
      host = 127.0.0.1
      port = 6600
      log = /tmp/mpdscribble.log
      verbose = 1

      [last.fm]
      url = https://post.audioscrobbler.com/
      username = ${config.services.mpd-stack.lastfmUsername}
      password = @LASTFM_PASSWORD@

      [listenbrainz]
      url = https://api.listenbrainz.org/1/submit-listens
      username = token
      password = @LISTENBRAINZ_TOKEN@
    '';

    # Systemd service for mpdscribble with secret injection
    systemd.user.services.mpdscribble = {
      Unit = {
        Description = "MPD scrobbler for Last.fm and ListenBrainz";
        After = [ "mpd.service" ];
        Requires = [ "mpd.service" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = pkgs.writeShellScript "mpdscribble-config" ''
          ${pkgs.coreutils}/bin/mkdir -p ${config.xdg.configHome}/mpdscribble
          LASTFM_PW=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.lastfm-password.path} 2>/dev/null || echo "")
          LB_TOKEN=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.listenbrainz-token.path} 2>/dev/null || echo "")
          ${pkgs.gnused}/bin/sed \
            -e "s|@LASTFM_PASSWORD@|$LASTFM_PW|g" \
            -e "s|@LISTENBRAINZ_TOKEN@|$LB_TOKEN|g" \
            ${config.xdg.configHome}/mpdscribble/mpdscribble.conf.template \
            > ${config.xdg.configHome}/mpdscribble/mpdscribble.conf
        '';
        ExecStart = "${pkgs.mpdscribble}/bin/mpdscribble --no-daemon --conf ${config.xdg.configHome}/mpdscribble/mpdscribble.conf";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # Note: SOPS secrets (lastfm-password, listenbrainz-token) are defined in
    # hosts/common/home/default.nix where inputs.self is available
  };
}
