{
  pkgs,
  dsh-src,
}:

pkgs.mkShell {
  packages = with pkgs; [
    nodejs_24
    pnpm_11
    gcc
    gnumake
    python3
    git
    jq
    patchelf
    sqlite
    zstd
    cacert
    gnutar
    gzip
    electron_44-bin
    # 质量门使用（scripts/check.sh / checks）：固定版本，避免宿主工具漂移。
    shellcheck
    nixfmt
    file
    desktop-file-utils
    curl
  ];

  DSH_SRC = "${dsh-src}";
  ELECTRON_DIST = "${pkgs."electron_44-bin"}/libexec/electron";

  shellHook = ''
    echo "dsh-nix dev shell: node $(node --version), pnpm $(pnpm --version)"
    echo "DSH_SRC=$DSH_SRC（只读；spike 复制到 work/ 再改）"
  '';
}
