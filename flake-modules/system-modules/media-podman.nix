{ ... }: {
  flake.modules.nixos.media-podman =
# Shared media-podman user and media-services group
# Used by tdarr, emby, sonarr, radarr, and other media services
{ lib, ... }:

{
  users.users.media-podman = {
    isSystemUser = true;
    group = "media-services";
    uid = 13106;
    home = "/var/lib/media-podman";
    createHome = true;
    subUidRanges = [{ startUid = 300000; count = 165536; }];
    subGidRanges = [{ startGid = 300000; count = 165536; }];
  };

  users.groups.media-services.gid = 13100;
}
;
}
