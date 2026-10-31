# 终端/Web 共用的 dsh CLI：只引用 dsh-desktop-runtime 的输出，不复制运行时树，
# 因此闭包不含 Electron / GTK 桌面壳。运行时树带逐文件摘要，wrapper 只读它。
{
  lib,
  stdenv,
  runtime,
  version,
}:

stdenv.mkDerivation {
  pname = "dsh";
  inherit version;

  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
        runHook preInstall

        mkdir -p $out/bin
        cat > $out/bin/dsh <<EOF
    #!${stdenv.shell}
    exec ${runtime}/runtime/primary-runtime/dependencies/node/bin/node \\
      --expose-internals \\
      ${runtime}/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js "\$@"
    EOF
        chmod 755 $out/bin/dsh

        install -Dm644 ${../LICENSE} $out/share/licenses/dsh/LICENSE
        install -Dm644 ${../NOTICE} $out/share/licenses/dsh/NOTICE

        runHook postInstall
  '';

  meta = {
    description = "DeepSeek Harness CLI and web surface (shared desktop runtime, no Electron)";
    homepage = "https://github.com/0Sycamores/dsh-nix";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "dsh";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
