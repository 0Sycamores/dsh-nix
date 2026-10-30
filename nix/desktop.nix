{
  lib,
  stdenv,
  jq,
  electron44bin,
  gtk3,
  gtk4,
  gsettings-desktop-schemas,
  librsvg,
  dconf,
  payload,
  runtime,
}:

let
  # 等价 wrapGAppsHook3 的启动环境，但直接写进启动器：外层派生不做任何 fixup，
  # 保证 Electron dist 与 payload（逐文件摘要的运行时树）字节不被改动。
  gtk4Schemas = "${gtk4}/share/gsettings-schemas/gtk4-${gtk4.version}";
  gtk3Schemas = "${gtk3}/share/gsettings-schemas/gtk+3-${gtk3.version}";
  gsettingsSchemas = "${gsettings-desktop-schemas}/share/gsettings-schemas/gsettings-desktop-schemas-${gsettings-desktop-schemas.version}";
  gioModules = "${dconf}/lib/gio/modules";
  gdkPixbufCache = "${librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache";
in
stdenv.mkDerivation {
  pname = "dsh-desktop";
  inherit (payload) version;

  # 纯组装派生：无源码解包；payload 与 Electron dist 均不可被 fixup 修改。
  dontUnpack = true;
  dontFixup = true;
  dontPatchELF = true;
  dontStrip = true;
  dontPatchShebangs = true;

  nativeBuildInputs = [ jq ];

  buildInputs = [
    gtk3
    gtk4
    gsettings-desktop-schemas
    librsvg
    dconf
  ];

  installPhase = ''
    runHook preInstall

    # Electron dist 作为外壳；可执行文件名不能是 electron，否则 app.isPackaged=false。
    mkdir -p $out/lib/dsh-desktop $out/bin
    cp -a ${electron44bin}/libexec/electron/. $out/lib/dsh-desktop/
    chmod -R u+w $out/lib/dsh-desktop
    mv $out/lib/dsh-desktop/electron $out/lib/dsh-desktop/dsh-desktop
    rm -f $out/lib/dsh-desktop/resources/default_app.asar

    # plain resources/app 打包布局（不使用 asar）。
    mkdir -p $out/lib/dsh-desktop/resources/app
    cp -a ${payload}/desktop/lib $out/lib/dsh-desktop/resources/app/lib
    cp -a ${payload}/desktop/renderer $out/lib/dsh-desktop/resources/app/renderer
    cp -a ${runtime}/dsh $out/lib/dsh-desktop/resources/app/dsh
    cp -a ${payload}/shell-node-modules $out/lib/dsh-desktop/resources/app/node_modules
    cp -a ${runtime}/runtime $out/lib/dsh-desktop/resources/runtime
    cp ${payload}/desktop/resources/icon.png $out/lib/dsh-desktop/resources/icon.png
    # desktop-host CLI 的 supportDir 推导假设 asar 布局，用相对符号链接补齐。
    ln -s ../runtime $out/lib/dsh-desktop/resources/app/runtime

    ${jq}/bin/jq \
      '. + { productName: "DeepSeek Harness", dshDesktopAppId: "dev.dsh-nix.desktop", dshDesktopUpdateChannel: "nightly" }' \
      ${payload}/desktop/package.json > $out/lib/dsh-desktop/resources/app/package.json

    install -Dm644 ${payload}/desktop/resources/icon.png $out/share/icons/hicolor/512x512/apps/dsh-desktop.png

    # 本仓库许可与免责声明随包分发；上游/第三方许可见 NOTICE。
    install -Dm644 ${../LICENSE} $out/share/licenses/dsh-desktop/LICENSE
    install -Dm644 ${../NOTICE} $out/share/licenses/dsh-desktop/NOTICE

    install -m 644 ${./launcher.sh} $out/bin/dsh-desktop
    chmod u+w $out/bin/dsh-desktop
    substituteInPlace $out/bin/dsh-desktop \
      --replace-fail '@SHELL@' '${stdenv.shell}' \
      --replace-fail '@GIO_EXTRA_MODULES@' '${gioModules}' \
      --replace-fail '@GDK_PIXBUF_MODULE_FILE@' '${gdkPixbufCache}' \
      --replace-fail '@XDG_DATA_DIRS@' '${gtk4Schemas}:${gtk3Schemas}:${gsettingsSchemas}' \
      --replace-fail '@LD_LIBRARY_PATH@' '${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}' \
      --replace-fail '@PKG@' "$out/lib/dsh-desktop"
    chmod 755 $out/bin/dsh-desktop

    runHook postInstall
  '';
}
