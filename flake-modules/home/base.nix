{ ... }: {
  flake.modules.homeManager.default = { inputs, outputs, lib, config, pkgs, hostname, ... }: {
    home = {
      enableNixpkgsReleaseCheck = false;
    };

    home.packages = with pkgs; [
      htop btop tree pstree wget curl unzip zip jq ripgrep fd bat eza zoxide broot fzf nmap
      zellij fish weechat
      git git-annex gh direnv colmena
      vim nano
      f3
      mtr pfetch hyfetch fastfetch iperf3 rclone
      git-filter-repo git-crypt
      nil nix nix-index nixd rmlint age sops
    ];

    programs.home-manager.enable = true;

    services.syncthing = {
      enable = true;
    };

    xdg.enable = true;

    home.stateVersion = "25.05";

    home.sessionVariables = {
      GNUPGHOME = "${config.home.homeDirectory}/.gnupg";
      OPENCODE_ENABLE_EXA = "1";
    };

    sops = {
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      defaultSopsFile = "${inputs.self}/secrets/secrets.yaml";
      validateSopsFiles = false;

      secrets = {
        git-credentials = {
          sopsFile = "${inputs.self}/secrets/git-credentials-age.yaml";
          key = "git_credentials";
          path = "${config.home.homeDirectory}/.git-credentials";
          mode = "0600";
        };
        acoustid-apikey = {
          sopsFile = "${inputs.self}/secrets/beets.yaml";
          key = "acoustid_apikey";
        };
        lastfm-password = {
          sopsFile = "${inputs.self}/secrets/music.yaml";
          key = "lastfm_password_hash";
        };
        listenbrainz-token = {
          sopsFile = "${inputs.self}/secrets/music.yaml";
          key = "listenbrainz_token";
        };
        atuin-key = {
          sopsFile = "${inputs.self}/secrets/atuin.yaml";
          key = "atuin_key";
          path = "${config.home.homeDirectory}/.local/share/atuin/key";
          mode = "0600";
        };
      };
    };
  };
}
