{ pkgs, lib }:

pkgs.stdenv.mkDerivation rec {
  pname = "airspy-adsb";
  version = "2.2-RC31"; # You will need to fill this in

  src = pkgs.fetchFromGitHub {
    owner = "fejiso";
    repo = "airspy_adsb";
    rev = "master"; # Tag for the desired version
    sha256 = "LRm8nOGnwa5f918PWCZH3RDsDDpxOEfbIsNvC1S6yv4="; # Correct hash for 2.2-RC31
    #sha256 = "";
  };

  buildInputs = with pkgs; [
    libusb1
    librtlsdr
    airspy
  ];

  makeFlags = [
    "PREFIX=$(out)"
  ];

  meta = with pkgs.lib; {
    description = "Airspy ADS-B decoder";
    homepage = "https://github.com/fejiso/airspy_adsb";
    license = licenses.gpl3Plus; # Assuming GPLv3+ based on common open-source projects
    platforms = platforms.linux;
  };
}
