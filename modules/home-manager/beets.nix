{ config, pkgs, ... }:

{
  home.packages = [ pkgs.beets ];

  xdg.configFile."beets/config.yaml".text = ''
    plugins: fetchart embedart scrub replaygain lastgenre chroma web discogs lyrics bpd rewrite mbsync duplicates missing
    directory: /mnt/user/Music
    library: /mnt/user/Music/musiclibrary.blb
    art_filename: albumart
    threaded: yes
    original_date: no
    per_disc_numbering: no

    match:
      max_rec:
        missing_tracks: medium
        unmatched_tracks: medium
      ignored: album_id track_id

    acoustid:
      apikey: ${config.sops.secrets.acoustid-apikey.path}

    paths:
      default: $albumartist/$album%aunique{}/$track - $title
      singleton: Non-Album/$artist - $title
      comp: Compilations/$album%aunique{}/$track - $title
      albumtype_soundtrack: Soundtracks/$album/$track $title

    import:
      write: yes
      copy: no
      move: yes
      delete: true
      resume: ask
      incremental: yes
      quiet_fallback: skip
      timid: no
      log: ~/.config/beets/beet.log

    bpd:
      host: 127.0.0.1
      port: 6600

    lastgenre:
      auto: yes
      source: album
      canonical: ""

    embedart:
      auto: yes

    fetchart:
      auto: yes

    replaygain:
      auto: no
      overwrite: true
      albumgain: true
      backend: gstreamer

    scrub:
      auto: yes

    lyrics:
      auto: true

    missing:
      format: "$albumartist - $album - $title"
      count: false
      total: false

    web:
      host: 0.0.0.0
      port: 8337
  '';
}
