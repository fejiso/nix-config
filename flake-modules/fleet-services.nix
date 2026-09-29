{ ... }: {
  # Fleet-wide service registry — single source of truth consumed by:
  #   - flake-modules/system-modules/ingress.nix (nginx vhosts on butthead + hierro)
  #   - flake-modules/system-modules/gatus.nix   (health checks + alerting)
  #
  # Onboarding a new service = one entry here; proxying (if `public`) and
  # monitoring appear on the next rebuild. `public` services get a
  # <sub>.<domain> vhost; non-default subdomain labels and both domains are
  # secret (secrets/ingress.yaml -> /var/lib/fleet-secrets/ingress-domains.nix,
  # see scripts/render-ingress-domains.sh). Ports/groups mirror homepage.nix.
  #
  # `public` flags were seeded 2026-09-28 from the nginx-proxy-manager proxy
  # host list, with each destination probed for liveness; dead NPM entries
  # (archivebox, calibre, fileflows, immich, localai, madsb, meshtastic,
  # motion, omv, pintoradio, prometheus, qdirstat, readarr, romm, router2,
  # search, serge*, syncthing, task, unmanic, webz, grafana/prometheus on
  # butthead) were NOT onboarded.
  fleet.services = {
    # ── butthead ────────────────────────────────────────────────────────────
    emby          = { host = "butthead"; port = 8096;  group = "Media";       description = "Media server"; public = true; };
    sonarr        = { host = "butthead"; port = 8989;  group = "Media";       description = "TV"; public = true; };
    radarr        = { host = "butthead"; port = 7878;  group = "Media";       description = "Movies"; public = true; };
    lidarr        = { host = "butthead"; port = 8686;  group = "Media";       description = "Music"; public = true; };
    prowlarr      = { host = "butthead"; port = 9696;  group = "Media";       description = "Indexers"; public = true; };
    # Quadlet defined but container was DOWN when probed 2026-09-28 — gatus
    # will (correctly) alert; restart or drop the container.
    lazylibrarian = { host = "butthead"; port = 5299;  group = "Media";       description = "Books"; public = true; };
    sabnzbd       = { host = "butthead"; port = 8080;  group = "Media";       description = "Usenet"; public = true; };
    deluge        = { host = "butthead"; port = 8112;  group = "Media";       description = "Torrents"; public = true; };
    qbittorrent   = { host = "butthead"; port = 8084;  group = "Media";       description = "Torrents (via NordVPN)"; };
    tdarr         = { host = "butthead"; port = 8265;  group = "Media";       description = "Transcoding"; public = true; };

    # Quadlet defined but container was DOWN when probed 2026-09-28 (NPM
    # pointed at :8000, now restic — stale). Restart or drop the container.
    paperless  = { host = "butthead"; port = 8010; group = "Documents"; description = "Documents"; public = true; };
    vaultwarden = { host = "butthead"; port = 4743; group = "Documents"; description = "Passwords"; public = true; };

    open-webui = { host = "butthead"; port = 3003;  group = "AI"; description = "Ollama chat UI"; };
    ollama     = { host = "butthead"; port = 11434; group = "AI"; description = "Local models API"; healthPath = "/api/version"; };
    comfyui    = { host = "butthead"; port = 8188;  group = "AI"; description = "Image generation"; public = true; };

    kopia          = { host = "butthead"; port = 51515; group = "Infra"; description = "Backup server"; scheme = "https"; };
    homepage       = { host = "butthead"; port = 3002;  group = "Infra"; description = "Dashboard"; };
    restic-rest    = { host = "butthead"; port = 8000;  group = "Infra"; description = "Restic REST server"; };
    home-assistant = { host = "butthead"; port = 8123;  group = "Infra"; description = "HAOS VM"; public = true; };
    soundcork      = { host = "butthead"; port = 8005;  group = "Infra"; description = "Bose SoundTouch"; };
    syncthing-unraid = { host = "butthead"; port = 8384; group = "Infra"; description = "Syncthing"; public = true; };

    # ── hierro ──────────────────────────────────────────────────────────────
    forgejo     = { host = "hierro"; port = 3000; group = "Infra";      description = "Git (SSH :2222)"; public = true; };
    silverbullet = { host = "hierro"; port = 3004; group = "Documents"; description = "Notes"; };
    openclaw    = { host = "hierro"; port = 3080; group = "AI";         description = "AI assistant gateway"; };
    llama-rpc   = { host = "hierro"; port = 8079; group = "AI";         description = "Distributed inference API"; };

    grafana         = { host = "hierro"; port = 3001; group = "Monitoring"; description = "Dashboards"; };
    victoriametrics = { host = "hierro"; port = 8428; group = "Monitoring"; description = "Metrics DB"; healthPath = "/health"; };
    vmalert         = { host = "hierro"; port = 8880; group = "Monitoring"; description = "Alert rules"; };
    alertmanager    = { host = "hierro"; port = 9093; group = "Monitoring"; description = "Alerts"; };
    gatus           = { host = "hierro"; port = 8080; group = "Monitoring"; description = "Uptime"; };

    nats  = { host = "hierro"; port = 8222; group = "Infra"; description = "Messaging monitor"; };
    atuin = { host = "hierro"; port = 8888; group = "Infra"; description = "Shell history sync"; };

    # ── snuffles ────────────────────────────────────────────────────────────
    # Public label is the legacy "adsb.pinto" (subdomains map, ingress.yaml).
    tar1090  = { host = "snuffles"; port = 8080; group = "Radio"; description = "Live ADS-B map"; healthPath = "/tar1090/"; public = true; };
    piaware  = { host = "snuffles"; port = 8081; group = "Radio"; description = "FlightAware feeder"; };
    fr24feed = { host = "snuffles"; port = 8082; group = "Radio"; description = "Flightradar24 feeder"; };

    # ── LAN appliances (not nix-config hosts; raw upstream) ────────────────
    # NPM fronted these with an HTTP-basic-auth access list ("admin") — the
    # nginx ingress does NOT replicate that, they rely on their own auth.
    router  = { host = "lan"; port = 80; upstream = "10.2.3.1:80"; group = "Infra"; description = "Router"; public = true; };
    router3 = { host = "lan"; port = 80; upstream = "10.2.3.3:80"; group = "Infra"; description = "Router 3"; public = true; };
  };
}
