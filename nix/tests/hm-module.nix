{
  pkgs,
  home-manager,
  dsh-nix,
}:

let
  # dummy packages：让 HM 模块渲染出 wrapper/launcher/desktop entry，而不构建真实运行时。
  testDesktop = pkgs.writeShellScriptBin "dsh-desktop" "exit 0";
  testCli = pkgs.writeShellScriptBin "dsh" "exit 0";
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

        programs.dsh = {
          enable = true;
          package = testCli;
          dshHome = "${homeDirectory}/.dsh";
          environmentFiles = [ "/run/secrets/rendered/dsh_env" ];
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

        programs.dsh-desktop = {
          enable = true;
          package = testDesktop;
        };
      }
    ];
  };
in
pkgs.runCommand "dsh-hm-module-check" { } ''
  set -euo pipefail
  gen=${configuration.activationPackage}
  files="$gen/home-files"
  path="$gen/home-path"

  # 这次真实踩过的 bug：home.file.source 曾指向 makeDesktopItem 的输出目录。
  entry="$files/.local/share/applications/deepseek-harness.desktop"
  test -f "$entry"
  test ! -d "$entry"
  grep -q '^Icon=dsh-desktop$' "$entry"
  grep -q '^StartupWMClass=deepseek-harness$' "$entry"
  grep -q '^Exec=' "$entry"

  # 声明式 home patch 由 programs.dsh 生成，且包含 settings 行。
  patch="$files/.dsh/cordis.patch.yml"
  test -f "$patch"
  grep -q 'id: permission' "$patch"
  grep -q 'danger-full-access' "$patch"
  grep -q 'id: agent-default-model' "$patch"

  # 桌面 launcher 读取共享 DSH_HOME / environmentFiles，并指向桌面包。
  launcher="$files/.local/bin/dsh-desktop"
  test -x "$launcher"
  grep -q '${testDesktop}/bin/dsh-desktop' "$launcher"
  grep -q 'DSH_HOME=/home/dsh-test/.dsh' "$launcher"
  grep -q '/run/secrets/rendered/dsh_env' "$launcher"

  # 终端/Web CLI 由 programs.dsh 安装到 HM profile；wrapper 必须带共享环境。
  cli="$path/bin/dsh"
  test -x "$cli"
  cliTarget=$(readlink -f "$cli")
  grep -q '${testCli}/bin/dsh' "$cliTarget"
  grep -q 'DSH_HOME=/home/dsh-test/.dsh' "$cliTarget"
  grep -q '/run/secrets/rendered/dsh_env' "$cliTarget"

  touch $out
''
