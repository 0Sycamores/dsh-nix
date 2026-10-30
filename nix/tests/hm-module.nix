{
  pkgs,
  home-manager,
  dsh-nix,
}:

let
  # dummy package：让 HM 模块渲染出 launcher/desktop entry，而不构建真实桌面端。
  testPackage = pkgs.writeShellScriptBin "dsh-desktop" "exit 0";
  homeDirectory = "/home/dsh-test";
  configuration = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      dsh-nix.homeModules.default
      {
        home.username = "dsh-test";
        home.homeDirectory = homeDirectory;
        home.stateVersion = "26.05";
        nixpkgs.overlays = [ dsh-nix.overlays.default ];

        programs.dsh-desktop = {
          enable = true;
          package = testPackage;
          dshHome = "${homeDirectory}/.dsh";
          environmentFiles = [ "/run/secrets/rendered/dsh_env" ];
          cli.enable = true;
          settings = {
            agent-default-model = {
              provider = "sycamore";
              model = "deepseek-v4.1-flash";
              reasoningEffort = "max";
            };
            permission = {
              defaultPreset = "danger-full-access";
              presets = {
                read-only = {
                  sandbox = "read-only";
                  approval = "ask";
                };
                workspace-write = {
                  sandbox = "workspace-write";
                  approval = "ask";
                };
                danger-full-access = {
                  sandbox = "danger-full-access";
                  approval = "never";
                };
              };
            };
          };
        };
      }
    ];
  };
in
pkgs.runCommand "dsh-hm-module-check" { } ''
  set -euo pipefail
  gen=${configuration.activationPackage}
  files="$gen/home-files"

  # 这次真实踩过的 bug：home.file.source 曾指向 makeDesktopItem 的输出目录。
  entry="$files/.local/share/applications/deepseek-harness.desktop"
  test -f "$entry"
  test ! -d "$entry"
  grep -q '^Icon=dsh-desktop$' "$entry"
  grep -q '^StartupWMClass=deepseek-harness$' "$entry"
  grep -q '^Exec=' "$entry"

  # 声明式 home patch 必须落在正确位置并包含 id。
  patch="$files/.dsh/cordis.patch.yml"
  test -f "$patch"
  grep -q 'id: permission' "$patch"
  grep -q 'danger-full-access' "$patch"
  grep -q 'id: agent-default-model' "$patch"

  # launcher / CLI wrapper 存在且指向预期文件。
  launcher="$files/.local/bin/dsh-desktop"
  test -x "$launcher"
  grep -q '${testPackage}/bin/dsh-desktop' "$launcher"
  grep -q 'DSH_HOME=/home/dsh-test/.dsh' "$launcher"
  cli="$files/.local/bin/dsh"
  test -x "$cli"
  grep -q 'cli.js' "$cli"

  touch $out
''
