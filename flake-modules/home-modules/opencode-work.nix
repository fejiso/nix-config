{ ... }: {
  flake.modules.homeManager.opencode-work =
# opencode configured for the internal corporate Bedrock gateway.
# Auth uses the Midway SSO cookie at ~/.midway/cookie (managed by mwinit).
# No sops secrets — no personal API credentials deployed here.
#
# TODOs before first deploy:
#   - Set model to the Bedrock model ID served by the internal gateway
#   - Set endpoint to the internal gateway URL
#   - Verify cookieFile is the correct provider option name (opencode provider docs)
{ config, lib, ... }: {
  programs.opencode.settings = {
    model = "TODO: bedrock-model-id";
    provider."internal-bedrock".options = {
      endpoint = "TODO: https://internal-corp-gateway/v1";
      cookieFile = "${config.home.homeDirectory}/.midway/cookie";
    };
  };
};
}
