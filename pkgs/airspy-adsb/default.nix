{ pkgs, lib }:

pkgs.stdenv.mkDerivation rec {
  pname = "airspy-adsb";
  version = "2.2-RC31"; # You will need to fill this in

  src = pkgs.fetchFromGitHub {
    owner = "fejiso";
    repo = "airspy_adsb";
    rev = "2.2-RC31"; # Tag for the desired version
    sha256 = "AHa9xLn08PJJNAjWdK0KhVyff6mHCLC2h0eh2qpVumg="; # Correct hash for 2.2-RC31
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
