{ lib, stdenvNoCC, fetchurl, dpkg, zstd, autoPatchelfHook }:
# Polygon Bor (execution layer, geth fork) — upstream release binary.
# The deb ships only /usr/bin/bor; the mainnet config comes from the module.
stdenvNoCC.mkDerivation rec {
  pname = "bor";
  version = "2.10.1";

  src = fetchurl {
    url = "https://github.com/0xPolygon/bor/releases/download/v${version}/bor-v${version}-amd64.deb";
    hash = "sha256-AclS6ToDbwE+voEOsfp61CZcGlFylmjIRvv2tgxACeI=";
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
