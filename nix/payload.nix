{
  pkgs,
  lib,
  stdenv,
  fetchPnpmDeps,
  pnpm_11,
  nodejs_24,
  gcc,
  gnumake,
  python3,
  git,
  jq,
  cacert,
  sqlite,
  zstd,
  gnutar,
  gzip,
  coreutils,
  src,
  srcRevision,
  monorepoDepsHash ? "sha256-i+T4XEJsKK8LhWgTXLV9X88IpEfWwXcOMUFc2MvzCZw=",
}:

let
  version = (lib.importJSON (src + "/apps/desktop/package.json")).version;
  monorepoDeps = fetchPnpmDeps {
    pname = "dsh-monorepo-deps";
    inherit version src;
    pnpm = pnpm_11;
    fetcherVersion = 5;
    hash = monorepoDepsHash;
  };
in
stdenv.mkDerivation {
  pname = "dsh-desktop-payload";
  inherit version src;

  patches = [
    ../patches/0001-desktop-build-paths-linux.patch
    ../patches/0002-prepare-dsh-runtime-node.patch
    ../patches/0003-linux-desktop-adaptations.patch
  ];

  nativeBuildInputs = [
    nodejs_24
    pnpm_11
    gcc
    gnumake
    python3
    git
    jq
    cacert
    sqlite
    zstd
    coreutils
  ];

  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    export MONOREPO_DEPS="${monorepoDeps}"
    export SRC_REVISION="${srcRevision}"
    export OUT_SHELL="$TMPDIR/shell-deps"
    cp ${./normalize-tarballs.sh} ./.dsh-nix-normalize-tarballs.sh
    bash ${./build-payload.sh}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    bash ${./install-payload.sh}
    runHook postInstall
  '';

  passthru = { inherit monorepoDeps; };
}
