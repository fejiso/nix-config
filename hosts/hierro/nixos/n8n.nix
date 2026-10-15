{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
# n8n workflow automation — the fleet's only directly-public hierro service:
# TLS terminated HERE (not via butthead's home ingress) because hierro is a
# Hetzner box with a real public IP and n8n webhooks must be reachable from
# the internet. Mesh vhosts are bound to wt0 only (see ingress-mesh
# listenAddr), so opening public 80/443 exposes just this one vhost.
let
  domains = import (inputs.ingress-secrets + "/ingress-domains.nix");
  domain = domains.meshDomain;

  # Declaratively managed community nodes. n8n reconciles EXACTLY this set on
  # every startup (N8N_COMMUNITY_PACKAGES_MANAGED_BY_ENV) — installs missing,
  # fixes versions, uninstalls anything not listed. The UI "Community nodes"
  # page is read-only as a consequence; to add/remove nodes, edit this list
  # and redeploy. Names verified against the npm registry.
  communityPackages = [
    # Documents / media
    { name = "n8n-nodes-pdf"; }
    { name = "n8n-nodes-pdfco"; }
    { name = "n8n-nodes-tesseractjs"; } # OCR, pure JS
    { name = "@mazix/n8n-nodes-converter-documents"; } # doc -> text/markdown
    { name = "n8n-nodes-youtube"; }
    { name = "n8n-nodes-transcript-lol"; }
    # AI / search
    { name = "n8n-nodes-mcp"; }
    { name = "n8n-nodes-deepseek"; }
    { name = "n8n-nodes-openai-advanced"; } # LiteLLM prompt caching
    { name = "n8n-nodes-qdrant"; }
    { name = "@langfuse/n8n-nodes-langfuse"; }
    { name = "n8n-nodes-perplexity"; }
    { name = "n8n-nodes-serpapi"; }
    { name = "@tavily/n8n-nodes-tavily"; }
    { name = "@brave/n8n-nodes-brave-search"; }
    { name = "n8n-nodes-elevenlabs"; }
    # Scraping / automation APIs
    { name = "n8n-nodes-apify"; }
    { name = "n8n-nodes-firecrawl"; }
    { name = "n8n-nodes-browserless"; }
    { name = "n8n-nodes-scrape-creators"; }
    { name = "@mookielianhd/n8n-nodes-instagram"; }
    # Messaging
    { name = "@telepilotco/n8n-nodes-telepilot"; } # Telegram (TDLib)
    { name = "n8n-nodes-evolution-api"; } # WhatsApp
    { name = "@devlikeapro/n8n-nodes-waha"; } # WhatsApp HTTP API
    { name = "@mbakgun/n8n-nodes-slack-socket-mode"; }
    # Power tools
    { name = "n8n-nodes-globals"; } # global constants
    { name = "n8n-nodes-run-node-with-credentials-x"; }
  ];
in
{
  services.n8n = {
    enable = true;
    environment = {
      WEBHOOK_URL = "https://n8n.${domain}/";
      N8N_HOST = "n8n.${domain}";
      N8N_PROTOCOL = "https";
      N8N_EDITOR_BASE_URL = "https://n8n.${domain}/";
      N8N_COMMUNITY_PACKAGES_ENABLED = "true";
      N8N_UNVERIFIED_PACKAGES_ENABLED = "true";
      N8N_COMMUNITY_PACKAGES_MANAGED_BY_ENV = "true";
      N8N_COMMUNITY_PACKAGES = builtins.toJSON communityPackages;
      # Pinning the key keeps stored credentials decryptable across
      # reinstalls/restores. Loaded via systemd credentials (DynamicUser-safe).
      N8N_ENCRYPTION_KEY_FILE = config.sops.secrets.n8n-encryption-key.path;
    };
  };

  # npm must be on PATH for community-package reconciliation at startup
  # (npm shells out to tar/gzip when unpacking — "spawn tar ENOENT" without).
  systemd.services.n8n.path = [ pkgs.nodejs pkgs.gnutar pkgs.gzip ];

  sops.secrets.n8n-encryption-key = {
    sopsFile = "${inputs.self}/secrets/n8n.yaml";
    key = "encryption_key";
  };

  # Public vhost, bound to hierro's public addresses only (mesh vhosts are
  # bound to wt0 — see ingress-mesh). Listens on 80 for ACME HTTP-01 +
  # redirect (forceSSL), 443 for the real thing.
  services.nginx.virtualHosts."n8n.${domain}" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      { addr = "65.108.100.35"; port = 80; }
      { addr = "65.108.100.35"; port = 443; ssl = true; }
      { addr = "[2a01:4f9:6b:2ba4::1]"; port = 80; }
      { addr = "[2a01:4f9:6b:2ba4::1]"; port = 443; ssl = true; }
    ];
    locations."/" = {
      proxyPass = "http://127.0.0.1:5678";
      proxyWebsockets = true;
    };
  };

  # Production Let's Encrypt (the staging endpoint is only in butthead's
  # ingress-public bring-up).
  security.acme = {
    acceptTerms = true;
    defaults.email = domains.acmeEmail;
    defaults.reloadServices = [ "nginx" ];
    defaults.group = "nginx";
  };

  # 80/443 public (n8n vhost only — mesh vhosts don't listen on public IPs).
  # 5678 mesh-only, for the Gatus health check and direct mesh access.
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 5678 ];
}
