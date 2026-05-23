{ ... }: {
  flake.modules.homeManager.beets =
{ config, pkgs, ... }:

{
  home.packages = [ pkgs.beets ];

  xdg.configFile."beets/config.yaml".text = ''
    plugins: fetchart embedart scrub replaygain lastgenre chroma web bpd rewrite mbsync duplicates missing
    directory: /mnt/Music
    library: /mnt/Music/musiclibrary.blb
    art_filename: albumart
    threaded: yes
    original_date: no
    per_disc_numbering: no


    match:
      strong_rec_thresh: 0.04
      ignored: album_id track_id
      max_rec:
        missing_tracks: strong
        unmatched_tracks: strong

    acoustid:
      apikey: ${config.sops.secrets.acoustid-apikey.path}

    import:
      none_rec_action: ask
      from_scratch: yes

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
      detail: yes

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

    missing:
      format: "$albumartist - $album - $title"
      count: false
      total: false

    web:
      host: 0.0.0.0
      port: 8337
  '';
}
;
}
