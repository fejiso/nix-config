{ lib, stdenvNoCC, fetchurl, dpkg, zstd, autoPatchelfHook }:
# Polygon Heimdall v2 (consensus layer, CometBFT) — upstream release binary.
stdenvNoCC.mkDerivation rec {
  pname = "heimdall-v2";
  version = "0.11.0";

  src = fetchurl {
    url = "https://github.com/0xPolygon/heimdall-v2/releases/download/v${version}/heimdall-v${version}-amd64.deb";
    hash = "sha256-4Zoad45Bi/yIHQEYrehNjiY1z20oBYlfIHm+6f4jvoU=";
  };

  nativeBuildInputs = [ dpkg zstd autoPatchelfHook ];
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    dpkg-deb -x $src .
    install -m755 usr/bin/heimdalld $out/bin/heimdalld
    runHook postInstall
  '';

  meta = {
    description = "Polygon PoS consensus client (Heimdall v2, CometBFT)";
    homepage = "https://github.com/0xPolygon/heimdall-v2";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "heimdalld";
  };
}
