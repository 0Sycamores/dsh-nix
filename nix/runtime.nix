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
  coreutils,
  payload,
  version,
  # 读取 lock.json 等只读输入用的上游源码（flake input 路径），不参与构建输入。
  upstreamSrc,
  runtimeDepsHash ? "sha256-nnA7+RY9w0pB2WB9ocUrgkXOMFPO4llF32wknwt1eOU=",
}:

let
  # payload 产出的「已构建源码树」：含 workspace 的 lib 产物，避免运行期重复构建。
  # 不要在这里 importJSON 该路径：那会触发 IFD；version 由 flake 传入。
  src = "${payload}/src";

  # Payload 输入全部来自上游 lock.json：node / python / wheels 用 fetchurl 预取，
  # 构建阶段填进上游的 sha256 命名缓存目录，因此 prepare 脚本无需联网。
  runtimeLock = lib.importJSON (upstreamSrc + "/scripts/primary-runtime/lock.json");
  target = "linux-x64";
  targetLock = runtimeLock.targets.${target};
  sri = hex: builtins.convertHash { hash = "sha256:${hex}"; toHashFormat = "sri"; };
  nodeArchive = "node-v${runtimeLock.nodeVersion}-${targetLock.nodeArchive}";
  pythonArchive = "cpython-${runtimeLock.pythonVersion}+${runtimeLock.pythonRelease}-${targetLock.pythonTarget}-install_only_stripped.tar.gz";
  assetRecords =
    [
      {
        url = "https://nodejs.org/dist/v${runtimeLock.nodeVersion}/${nodeArchive}";
        sha256 = targetLock.nodeSha256;
      }
      {
        url = "https://github.com/astral-sh/python-build-standalone/releases/download/${runtimeLock.pythonRelease}/${builtins.replaceStrings [ "+" ] [ "%2B" ] pythonArchive}";
        sha256 = targetLock.pythonSha256;
      }
    ]
    ++ map (wheel: { inherit (wheel) url sha256; }) (runtimeLock.wheels ++ targetLock.wheels);
  fetched = map (asset: {
    inherit (asset) sha256;
    file = pkgs.fetchurl {
      url = asset.url;
      hash = sri asset.sha256;
    };
  }) assetRecords;
  runtimeAssets = pkgs.runCommand "dsh-desktop-runtime-assets" { } ''
    mkdir -p $out
    ${lib.concatMapStringsSep "\n" (asset: "ln -s ${asset.file} $out/${asset.sha256}") fetched}
  '';

  # fetch 阶段需要一个包含 lockfile、元数据与本地包 tarball 的完整项目目录。
  runtimeProjectSrc = pkgs.runCommand "dsh-desktop-runtime-project-src" { } ''
    mkdir -p $out
    cp -a ${./runtime/project}/. $out/
    chmod -R u+w $out
    mkdir -p $out/desktop-packages
    cp -a ${payload}/package-set/desktop-packages/. $out/desktop-packages/
    chmod -R u+w $out
  '';

  runtimeDeps = fetchPnpmDeps {
    pname = "dsh-desktop-runtime-deps";
    inherit version;
    src = runtimeProjectSrc;
    pnpm = pnpm_11;
    fetcherVersion = 5;
    hash = runtimeDepsHash;
  };
in
stdenv.mkDerivation {
  pname = "dsh-desktop-runtime";
  inherit version src;

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

  # dsh 运行时树带逐文件摘要（desktop-runtime.json），任何 fixup 改动都会破坏校验。
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    export MONOREPO_DEPS="${payload.monorepoDeps}"
    export RUNTIME_DEPS="${runtimeDeps}"
    export RUNTIME_ASSETS="${runtimeAssets}"
    export PAYLOAD="${payload}"
    export RUNTIME_LOCKFILE="${./runtime/project/pnpm-lock.yaml}"
    cp ${./prepare-runtime.ts} ./.dsh-nix-prepare-runtime.ts
    bash ${./build-runtime.sh}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    bash ${./install-runtime.sh}
    runHook postInstall
  '';
}
