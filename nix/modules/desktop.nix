# Home Manager 模块：DSH 桌面端（Linux/NixOS，个人自用）。
#
# 本模块只负责 Electron 外壳（包、launcher、desktop entry）。共享的
# DSH_HOME、环境文件与声明式设置由 programs.dsh 负责；两模块通过
# config.programs.dsh 交接，避免同一份 cordis.patch.yml 有两个写入者。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.dsh-desktop;
  shared = config.programs.dsh;

  environmentSource = lib.concatMapStringsSep "\n" (file: ''
    if [ -r ${lib.escapeShellArg file} ]; then
      . ${lib.escapeShellArg file}
    fi
  '') shared.environmentFiles;

  launcher = pkgs.writeShellScript "dsh-desktop-launch" ''
    set -a
    ${environmentSource}
    set +a
    export DSH_HOME=${lib.escapeShellArg shared.dshHome}
    exec ${cfg.package}/bin/dsh-desktop "$@"
  '';

  # 不依赖 xdg.enable（使用者的 HM 配置可能关闭 xdg 管理）；直接生成 desktop 文件。
  desktopItem = pkgs.makeDesktopItem {
    # 文件名（desktop entry id）与 Electron 的 Wayland app_id 一致，任务栏才能关联。
    name = "deepseek-harness";
    desktopName = "DeepSeek Harness";
    genericName = "AI Agent Workspace";
    comment = "DeepSeek Harness 桌面端（DSH，个人自用打包）";
    exec = "${launcher} %U";
    icon = "dsh-desktop";
    terminal = false;
    categories = [ "Development" ];
    startupWMClass = "deepseek-harness";
  };
in
{
  imports = [ ./dsh.nix ];

  options.programs.dsh-desktop = {
    enable = lib.mkEnableOption "DSH 桌面端";

    package = lib.mkPackageOption pkgs "dsh-desktop" { };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = shared.enable;
        message = "programs.dsh-desktop 需要 programs.dsh.enable = true（共享 DSH_HOME 与声明式设置）。";
      }
    ];

    home.packages = [ cfg.package ];

    home.file = {
      ".local/bin/dsh-desktop".source = launcher;

      # makeDesktopItem 的输出是目录（share/applications/...），home.file 需要指向文件本身。
      ".local/share/applications/deepseek-harness.desktop".source =
        "${desktopItem}/share/applications/deepseek-harness.desktop";
    };
  };
}
