{ lib, stdenvNoCC, fetchurl, dpkg, zstd, autoPatchelfHook }:
# Polygon Bor (execution layer, geth fork) — upstream release binary.
# The deb ships only /usr/bin/bor; the mainnet config comes from the module.
stdenvNoCC.mkDerivation rec {
  pname = "bor";
  version = "2.10.3";

  src = fetchurl {
    url = "https://github.com/0xPolygon/bor/releases/download/v${version}/bor-v${version}-amd64.deb";
    # upstream .checksum asset (GitHub release v2.10.3)
    hash = "sha256-3C6V6BfzhqheXjPS6H0Ym9XnIyqLkc4g27538XC0XR4=";
  };

  nativeBuildInputs = [ dpkg zstd autoPatchelfHook ];
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    dpkg-deb -x $src .
    install -m755 usr/bin/bor $out/bin/bor
    runHook postInstall
  '';

  meta = {
    description = "Polygon PoS execution client (Bor, geth fork)";
    homepage = "https://github.com/0xPolygon/bor";
    license = lib.licenses.lgpl3;
    platforms = [ "x86_64-linux" ];
    mainProgram = "bor";
  };
}
