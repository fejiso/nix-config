{ ... }: {
  # Declarative ~/.ssh/config (replaces the hand-maintained file — move it
  # aside first: `mv ~/.ssh/config ~/.ssh/config.pre-nix`).
  flake.modules.homeManager.ssh = { ... }: {
    programs.ssh = {
      enable = true;

      # Load keys into the agent on first use (one unlock per login session;
      # sops uses the agent too, so nuci diff/deploy stops double-prompting).
      compression = true;
      serverAliveInterval = 10;

      matchBlocks = {
        "*" = {
          addKeysToAgent = "yes";
          controlMaster = "auto";
          controlPath = "/tmp/ssh_mux_%h_%p_%r";
          controlPersist = "30m";
          forwardX11Trusted = true;
          extraOptions = {
            TCPKeepAlive = "yes";
            ConnectTimeout = "200";
          };
        };

        "github.com" = {
          hostname = "github.com";
          user = "git";
        };

        # Legacy embedded devices with old dropbear/openssh servers.
        "192.168.*.* 10.234.234.* 10.123.123.*" = {
          extraOptions = {
            PubkeyAcceptedAlgorithms = "+ssh-rsa";
            HostkeyAlgorithms = "+ssh-rsa";
          };
        };
      };
    };
  };
}
