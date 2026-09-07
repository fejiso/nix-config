# Homepage (gethomepage.dev) dashboard for the fleet, served from butthead.
# All links use netbird mesh addresses (<host>.netbird.cloud), no external URLs.
{ ... }: {
  services.homepage-dashboard = {
    enable = true;
    # 3002 was already open in butthead's firewall (unused leftover).
    listenPort = 3002;
    allowedHosts = "butthead.netbird.cloud:3002,localhost:3002,127.0.0.1:3002";

    settings = {
      title = "fleet";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
    };

    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        datetime = {
          format = {
            dateStyle = "short";
            timeStyle = "short";
          };
        };
      }
    ];

    services = [
      {
        "Media" = [
          { "Emby" = { href = "http://butthead.netbird.cloud:8096"; description = "Media server"; }; }
          { "Sonarr" = { href = "http://butthead.netbird.cloud:8989"; description = "TV"; }; }
          { "Radarr" = { href = "http://butthead.netbird.cloud:7878"; description = "Movies"; }; }
          { "Lidarr" = { href = "http://butthead.netbird.cloud:8686"; description = "Music"; }; }
          { "Prowlarr" = { href = "http://butthead.netbird.cloud:9696"; description = "Indexers"; }; }
          { "LazyLibrarian" = { href = "http://butthead.netbird.cloud:5299"; description = "Books"; }; }
          { "SABnzbd" = { href = "http://butthead.netbird.cloud:8080"; description = "Usenet"; }; }
          { "Deluge" = { href = "http://butthead.netbird.cloud:8112"; description = "Torrents"; }; }
          { "qBittorrent" = { href = "http://butthead.netbird.cloud:8084"; description = "Torrents (via NordVPN)"; }; }
          { "Tdarr" = { href = "http://butthead.netbird.cloud:8265"; description = "Transcoding"; }; }
        ];
      }
      {
        "Documents & notes" = [
          { "Paperless-ngx" = { href = "http://butthead.netbird.cloud:8010"; description = "Documents"; }; }
          { "Vaultwarden" = { href = "http://butthead.netbird.cloud:4743"; description = "Passwords"; }; }
          { "Silverbullet" = { href = "http://hierro.netbird.cloud:3004"; description = "Notes"; }; }
        ];
      }
      {
        "AI" = [
          { "Open WebUI" = { href = "http://butthead.netbird.cloud:3003"; description = "Ollama chat UI"; }; }
          { "Ollama" = { href = "http://butthead.netbird.cloud:11434"; description = "Local models API"; }; }
          { "ComfyUI" = { href = "http://butthead.netbird.cloud:8188"; description = "Image generation"; }; }
          { "OpenClaw" = { href = "http://hierro.netbird.cloud:3080"; description = "AI assistant gateway"; }; }
          { "llama.cpp" = { href = "http://hierro.netbird.cloud:8079"; description = "Distributed inference API"; }; }
        ];
      }
      {
        "Monitoring" = [
          { "Grafana" = { href = "http://hierro.netbird.cloud:3001"; description = "Dashboards"; }; }
          { "Uptime Kuma" = { href = "http://butthead.netbird.cloud:3344"; description = "Uptime"; }; }
          { "VictoriaMetrics" = { href = "http://hierro.netbird.cloud:8428/vmui"; description = "Metrics DB"; }; }
          { "vmalert" = { href = "http://hierro.netbird.cloud:8880"; description = "Alert rules"; }; }
          { "Alertmanager" = { href = "http://hierro.netbird.cloud:9093"; description = "Alerts"; }; }
        ];
      }
      {
        "Infrastructure" = [
          { "Forgejo" = { href = "http://hierro.netbird.cloud:3000"; description = "Git (SSH :2222)"; }; }
          { "Kopia" = { href = "https://butthead.netbird.cloud:51515"; description = "Backup server (HTTPS)"; }; }
          { "Nginx Proxy Manager" = { href = "http://butthead.netbird.cloud:8102"; description = "Public ingress"; }; }
          { "NATS" = { href = "http://hierro.netbird.cloud:8222"; description = "Messaging monitor"; }; }
          { "Home Assistant" = { href = "http://butthead.netbird.cloud:8123"; description = "HAOS VM"; }; }
          { "SoundCork" = { href = "http://butthead.netbird.cloud:8005"; description = "Bose SoundTouch"; }; }
        ];
      }
      {
        "Radio" = [
          { "tar1090 (adsbfi)" = { href = "http://snuffles.netbird.cloud:8080"; description = "Live ADS-B map"; }; }
          { "piaware" = { href = "http://snuffles.netbird.cloud:8081"; description = "FlightAware feeder"; }; }
          { "fr24feed" = { href = "http://snuffles.netbird.cloud:8082"; description = "Flightradar24 feeder"; }; }
        ];
      }
    ];
  };

  # Home Assistant's QEMU hostfwd binds 8123 on the host; open it so the
  # dashboard link works over LAN/mesh like butthead's other services.
  networking.firewall.allowedTCPPorts = [ 8123 ];
}
