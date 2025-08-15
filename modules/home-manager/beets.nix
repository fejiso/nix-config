{ config, pkgs, ... }:

{
  home.packages = [ pkgs.beets ];

  xdg.configFile."beets/config.yaml".text = ''
    directory: ~/lib
    library: ~/lib/musiclibrary.blb
    plugins: lyrics chroma bpd lastgenre rewrite replaygain echonest lastgenre mbsync duplicates missing scrub
    threaded: true
    musicbrainz:
      host: musicbrainz.tranquilbase.org
      rate: 10
    match:
      ignored: album_id track_id
    acoustid:
      apikey: "Fq1JpTIK"
    import:
      move: false
      delete: true
      incremental: true
    bpd:
      host: 127.0.0.1
      port: 6600
    lastgenre:
      canonical: ""
      source: track
    lyrics:
      auto: true
    replaygain:
      overwrite: true
      albumgain: true
      auto: true
      backend: gstreamer
    echonest:
      upload: false
    missing:
      format: "$albumartist - $album - $title"
      count: false
      total: false
  '';
}