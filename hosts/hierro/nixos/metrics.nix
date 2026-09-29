{ config, lib, pkgs, inputs, ... }:
{
  sops.secrets.grafana-secret-key = {
    sopsFile = "${inputs.self}/secrets/grafana.yaml";
    key = "secret_key";
    owner = "grafana";
    group = "grafana";
  };

  ##########################################################################
  # VictoriaMetrics — single-binary timeseries DB
  ##########################################################################
  services.victoriametrics = {
    enable = true;
    listenAddress = ":8428";
    retentionPeriod = "100y";
    extraOptions = [
      "-storageDataPath=/var/lib/victoriametrics"
      "-search.maxQueryDuration=60s"
    ];
  };

  ##########################################################################
  # VictoriaLogs — log database (nginx access logs shipped by vector from
  # the ingress hosts; see flake-modules/system-modules/ingress.nix)
  ##########################################################################
  services.victorialogs = {
    enable = true;
    listenAddress = "0.0.0.0:9428";
    extraOptions = [ "-retentionPeriod=30d" ];
  };

  ##########################################################################
  # vmagent — Prometheus-style scrape collector, pushes to VictoriaMetrics
  ##########################################################################
  services.vmagent = {
    enable = true;
    remoteWrite.url = "http://127.0.0.1:8428/api/v1/write";
    prometheusConfig = {
      global = {
        scrape_interval = "30s";
      };
      scrape_configs = [
        {
          job_name = "victoriametrics";
          static_configs = [{ targets = [ "127.0.0.1:8428" ]; }];
        }
        {
          job_name = "vmagent";
          static_configs = [{ targets = [ "127.0.0.1:8429" ]; }];
        }
        {
          job_name = "vmalert";
          static_configs = [{ targets = [ "127.0.0.1:8880" ]; }];
        }
        {
          job_name = "alertmanager";
          static_configs = [{ targets = [ "127.0.0.1:9093" ]; }];
        }
        {
          job_name = "grafana";
          static_configs = [{ targets = [ "127.0.0.1:3001" ]; }];
        }
        {
          job_name = "gatus";
          static_configs = [{ targets = [ "127.0.0.1:8080" ]; }];
        }
        {
          # nginx VTS per-vhost stats (module: flake-modules/system-modules/ingress.nix)
          job_name = "nginx-vts";
          metrics_path = "/status/format/prometheus";
          static_configs = [
            { targets = [ "127.0.0.1:9977" ]; labels.host = "hierro"; }
            { targets = [ "butthead.netbird.cloud:9977" ]; labels.host = "butthead"; }
          ];
        }
      ];
    };
  };

  ##########################################################################
  # vmalert — alerting rules engine
  ##########################################################################
  services.vmalert.instances."" = {
    enable = true;
    settings = {
      "datasource.url" = "http://127.0.0.1:8428/";
      "notifier.url" = [ "http://127.0.0.1:9093/" ];
      "remoteWrite.url" = "http://127.0.0.1:8428/";
      "remoteRead.url" = "http://127.0.0.1:8428/";
    };
    rules = {
      groups = [
        {
          name = "self";
          rules = [
            {
              alert = "VMAgentScrapeFailing";
              expr = "vmagent_remotewrite_send_duration_seconds_count == 0";
              for = "5m";
              labels.severity = "warning";
              annotations.summary = "vmagent isn't sending samples to VictoriaMetrics";
            }
            {
              alert = "VMStorageDiskUsageHigh";
              expr = ''vm_free_disk_space_bytes{path="/var/lib/victoriametrics"} / vm_data_size_bytes{path="/var/lib/victoriametrics"} < 0.2'';
              for = "10m";
              labels.severity = "warning";
              annotations.summary = "VictoriaMetrics has less than 20% free disk relative to data size";
            }
          ];
        }
      ];
    };
  };

  ##########################################################################
  # Alertmanager — alert routing
  ##########################################################################
  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9093;
    configuration = {
      route = {
        receiver = "default";
        group_by = [ "alertname" ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "12h";
      };
      receivers = [
        { name = "default"; }
      ];
    };
  };

  ##########################################################################
  # Grafana — dashboards with VictoriaMetrics provisioned as default DS
  ##########################################################################
  services.grafana = {
    enable = true;
    declarativePlugins = with pkgs.grafanaPlugins; [
      victoriametrics-logs-datasource
    ];
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3001;
        domain = "grafana.hierro.netbird.cloud";
        root_url = "http://grafana.hierro.netbird.cloud:3001/";
      };
      analytics.reporting_enabled = false;
      security.admin_user = "admin";
      security.secret_key = "$__file{${config.sops.secrets.grafana-secret-key.path}}";
    };
    provision = {
      enable = true;
      dashboards.settings.providers = [{
        name = "default";
        options.path = "/etc/grafana-dashboards";
      }];
      datasources.settings.datasources = [
        {
          name = "VictoriaMetrics";
          type = "prometheus";
          uid = "victoriametrics";
          url = "http://127.0.0.1:8428";
          isDefault = true;
          jsonData.timeInterval = "30s";
        }
        {
          name = "Alertmanager";
          type = "alertmanager";
          uid = "alertmanager";
          url = "http://127.0.0.1:9093";
          jsonData = {
            implementation = "prometheus";
            handleGrafanaManagedAlerts = false;
          };
        }
        {
          name = "VictoriaLogs";
          type = "victoriametrics-logs-datasource";
          uid = "victorialogs";
          url = "http://127.0.0.1:9428";
        }
      ];
    };
  };

  # Provisioned dashboards (nginx VTS traffic stats)
  environment.etc."grafana-dashboards".source = ./grafana-dashboards;

  networking.firewall.interfaces.wt0.allowedTCPPorts = [
    8428 # victoriametrics (vmui, query, push)
    8429 # vmagent
    8880 # vmalert
    9093 # alertmanager
    3001 # grafana
    9428 # victorialogs
  ];
}
