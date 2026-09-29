{ pkgs, lib, ... }:
# Polygon PoS read node (Bor v2 execution + Heimdall v2 consensus) for the
# polystack polychain firehose: local eth_getLogs/newHeads/txpool with no
# public-RPC throttling. Bor's WS (127.0.0.1:8546) is polychain's future
# rpc_ws once synced; HTTP RPC on 127.0.0.1:8545. Data on /mnt/bcachefs
# (53T volume, SSD read cache) — pbss path-scheme state + ~1.5-week tx/log
# index (history.transactions/logs = 500k @ 2s blocks ≈ 11.6 days).
#
# Bootstrap: `sudo systemctl start bor-snapshot-fetch` downloads the
# PublicNode PBSS+pebble snapshot (~6.5TB compressed) into the datadir, then
# bor catches up the gap itself (bor stays stopped until then).
let
  borGenesis = pkgs.fetchurl {
    url = "https://github.com/0xPolygon/bor/releases/download/v2.10.1/genesis-mainnet-v1.json";
    hash = "sha256-KyxnVX1wPsHq6BeFyVIeIUpGTRQWRpyq6VLeZ8yi+Po=";
  };
  heimdallGenesis = pkgs.fetchurl {
    url = "https://storage.googleapis.com/mainnet-heimdallv2-genesis/migrated_dump-genesis.json";
    hash = "sha256-hD54XjQKQI2VK3qg2SQ1yUZDU29CarfD7hiL/caLhpk=";
  };
  # Upstream mainnet sentry configs (seeds/bootnodes baked in).
  heimdallConf = pkgs.runCommand "heimdall-mainnet-conf" { nativeBuildInputs = [ pkgs.dpkg pkgs.zstd ]; } ''
    dpkg-deb -x ${pkgs.fetchurl {
      url = "https://github.com/0xPolygon/heimdall-v2/releases/download/v0.11.0/heimdall-mainnet-sentry-config_v0.11.0-all.deb";
      hash = "sha256-FVXt5CnD+24Pv/0svJ8YDVatU/mIpL9jpUuqyQJqeL4=";
    }} .
    mkdir -p $out
    cp -r var/lib/heimdall/config $out/
  '';
  borData = "/mnt/bcachefs/bor";
  heimdallHome = "/mnt/bcachefs/heimdall";
  borConf = pkgs.writeText "bor-config.toml" ''
    chain = "mainnet"
    datadir = "${borData}/data"
    "db.engine" = "pebble"
    "state.scheme" = "path"
    syncmode = "full"
    # pbss does not support archive

    [p2p]
        maxpeers = 200
        port = 30303
        [p2p.discovery]
            static-nodes = [ "enode://48e6326841ce106f6b4e229a1be7e98a1d12be57e328b08cb461f6744ae4e78f5ec2340996ce9b40928a1a90137aadea13e25ca34774b52a3600d13a52c5c7bb@34.185.209.56:30303","enode://8ab6905fe76aa9001adb77135250e918db888cac216870c0e95cf26650d83d31d8c2c93d54c3333e0a2196517c41651d174b743ec3e11f44e595f62b77fec7ba@34.185.162.14:30303","enode://02e0b33cf60fb1f88f853c7c04830156151f4acd1c36173cd3fe1f375801fb4f5be5b3a89c98527915d37ed217752933c3faf4c820df740c9dd681294caebcf6@34.179.171.228:30303","enode://079c387b65b09674825462ea63c528ca996af7b03d19b1b2ab6557347434838067db6dd7ae5e0c2e08d5ba164117f3d7faffbf3e890cb91cffbdf45a433ddfce@35.246.166.189:30303","enode://191d06720948ae0119343e5798098f5b1f95a308174c4119d226da91833bc0176009bcc8bf5012e490500562d4d5b5427c307b01f3485b2e8351ac5afd946864@34.142.28.190:30303","enode://30a4651b245e9a0cec674b9ecb5a06ca01553aa727e14a77d0f1ccdb9e48a975f3be631505f417aae438be545ac3b290cd3ed00bef96efd7fb0fb7f916397b3f@34.39.56.114:30303","enode://b950b98b92e118551d79c7280b97ddfcdf3dacb620367ebd45e8382f8e69390df192055386221025ffd3c03912da2aadf668ae6ea7b35f391d82ef87452b3f02@34.147.169.102:30303","enode://5f6232dc546bf615c7b5bc1c896323340892a1c41097a89a1d38385a5d48bb02f9023377e526911a9da6e4112415aa9f3803cbeeef8243a2bfc4a3d0219ae69e@35.230.142.203:30303" ]
            dns = [ "enrtree://AKUEZKN7PSKVNR65FZDHECMKOJQSGPARGTPPBI7WS2VUL4EGR6XPC@pos.polygon-peers.io" ]

    [heimdall]
        url = "http://localhost:1317"

    [txpool]
        nolocals = true
        pricelimit = 25000000000
        accountslots = 16
        globalslots = 131072
        accountqueue = 64
        globalqueue = 131072
        lifetime = "1h30m0s"

    [miner]
        gaslimit = 45000000
        gasprice = "25000000000"

    [jsonrpc]
        ipcpath = "${borData}/bor.ipc"
        [jsonrpc.http]
            enabled = true
            port = 8545
            host = "127.0.0.1"
            api = ["eth", "net", "web3", "txpool", "bor"]
            vhosts = ["*"]
            corsdomain = ["*"]
        [jsonrpc.ws]
            enabled = true
            port = 8546
            host = "127.0.0.1"
            api = ["eth", "net", "web3", "txpool"]
            origins = ["*"]

    [gpo]
        ignoreprice = "25000000000"

    [telemetry]
        metrics = true

    [cache]
        cache = 4096

    # keep ~1.5 weeks of tx/log index (2s blocks ≈ 43.2k/day); state history
    # stays at the pbss default (90k blocks ≈ 2 days)
    [history]
      transactions = 500000
      logs = 500000
  '';
in {
  users.groups.bor = { };
  users.users.bor = {
    isSystemUser = true;
    group = "bor";
    home = borData;
  };

  systemd.tmpfiles.rules = [
    "d ${heimdallHome} 0755 bor bor -"
    "d ${heimdallHome}/config 0755 bor bor -"
    "d ${heimdallHome}/data 0755 bor bor -"
    "d ${borData} 0755 bor bor -"
    "d ${borData}/data 0755 bor bor -"
  ];

  # One-shot bootstrap: PublicNode PBSS+pebble snapshot (base 0-75.8M +
  # part 75.8M-94.5M ≈ 6.5TB compressed). Download → extract → delete, one
  # file at a time (peak disk ≈ 12TB; the volume has 20T free). Manual:
  #   sudo systemctl start bor-snapshot-fetch
  #   journalctl -fu bor-snapshot-fetch
  systemd.services.bor-snapshot-fetch = {
    description = "Bor mainnet snapshot fetch+extract (PublicNode PBSS/pebble)";
    conflicts = [ "bor.service" ];
    after = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = borData;
    serviceConfig = {
      Type = "oneshot";
      User = "bor";
      Group = "bor";
      TimeoutStartSec = "infinity";
      RemainAfterExit = true;
    };
    path = with pkgs; [ curl lz4 gnutar coreutils ];
    script = ''
      set -euo pipefail
      cd ${borData}/data
      mkdir -p bor
      fetch() {
        name="$1"
        echo "== downloading $name"
        curl -fL -C - --retry 8 --retry-delay 30 -o "$name" \
          "https://snapshots.publicnode.com/$name"
        echo "== extracting $name"
        lz4 -dc "$name" | tar -xf - -C ${borData}/data/bor
        rm "$name"
        echo "== done $name"
      }
      fetch polygon-bor-base-0-75817088.tar.lz4
      fetch polygon-bor-part-75817089-94508047.tar.lz4
      echo "snapshot ready — start bor: sudo systemctl start bor"
    '';
  };

  systemd.services.heimdalld = {
    description = "Polygon Heimdall v2 (consensus layer)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    preStart = ''
      if [ ! -f ${heimdallHome}/config/node_key.json ]; then
        ${pkgs.heimdall-v2}/bin/heimdalld init butthead --home ${heimdallHome} || true
      fi
      cp -f ${heimdallGenesis} ${heimdallHome}/config/genesis.json
      # force the sentry reference configs (seeds/persistent_peers) — init
      # writes a default config.toml with EMPTY seeds if it runs first
      for f in config.toml app.toml client.toml; do
        cp -f ${heimdallConf}/config/$f ${heimdallHome}/config/$f
      done
    '';
    serviceConfig = {
      User = "bor";
      Group = "bor";
      ExecStart = "${pkgs.heimdall-v2}/bin/heimdalld start --home ${heimdallHome}";
      Restart = "on-failure";
      RestartSec = "5s";
      LimitNOFILE = 65536;
      TimeoutStartSec = "600s";
      TimeoutStopSec = "120s";
    };
  };

  systemd.services.bor = {
    description = "Polygon Bor v2 (execution layer)";
    after = [ "heimdalld.service" "network-online.target" "bor-snapshot-fetch.service" ];
    wants = [ "network-online.target" ];
    requires = [ "heimdalld.service" ];
    wantedBy = [ "multi-user.target" ];
    preStart = ''
      cp -f ${borConf} ${borData}/config.toml
      if [ ! -d ${borData}/data/bor/chaindata ]; then
        ${pkgs.bor}/bin/bor init --datadir ${borData}/data ${borGenesis} || true
      fi
    '';
    serviceConfig = {
      User = "bor";
      Group = "bor";
      ExecStart = "${pkgs.bor}/bin/bor server --config ${borData}/config.toml";
      Restart = "on-failure";
      RestartSec = "5s";
      LimitNOFILE = 65536;
      TimeoutStartSec = "900s";
      TimeoutStopSec = "300s";
    };
  };

  # Bor config's ipcpath points at the datadir.
  environment.etc."bor/ipc-note".text = "bor ipc lives at ${borData}/bor.ipc";

  # P2P: bor 30303, heimdall 26656 (inbound improves peering; outbound-only
  # works with reduced peer counts — router port-forwards are the user's call).
  networking.firewall.allowedTCPPorts = [ 30303 26656 ];
  networking.firewall.allowedUDPPorts = [ 30303 ];
}
