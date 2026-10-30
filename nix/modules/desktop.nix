# Home Manager 模块：DSH 桌面端（Linux/NixOS，个人自用）。
#
# 声明式设置写入 home 层 patch：$DSH_HOME/cordis.patch.yml，由 app-boot 在
# bundles → profile 用户层之后叠加，对所有 profile 生效（机器级偏好，优先级高于
# profile 层、低于命令行 --patch）。不生成可变的 settings.yaml 副本。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.dsh-desktop;
  yaml = pkgs.formats.yaml { };

  # 旧 settings.yaml 键 → 新 patch 行 id 的重映射（上游 LEGACY_SECTION_ENTRIES；
  # shell 段在本仓库目标平台 Linux 上映射到 bash-sandbox）。
  legacySettingsIds = {
    "ui-developer-tools" = "ui-settings";
    "ui-onboarding" = "ui-settings-general";
    "shell" = "bash-sandbox";
  };

  settingsRows = lib.mapAttrsToList (
    id: value: {
      id = legacySettingsIds.${id} or id;
      config = value;
    }
  ) cfg.settings;
  patchRows = settingsRows ++ cfg.patches;

  environmentSource = lib.concatMapStringsSep "\n" (file: ''
    if [ -r ${lib.escapeShellArg file} ]; then
      . ${lib.escapeShellArg file}
    fi
  '') cfg.environmentFiles;

  launcher = pkgs.writeShellScript "dsh-desktop-launch" ''
    set -a
    ${environmentSource}
    set +a
    export DSH_HOME=${lib.escapeShellArg cfg.dshHome}
    exec ${cfg.package}/bin/dsh-desktop "$@"
  '';

  # 终端 dsh：复用桌面 payload 的官方 Node 与 desktop-host CLI（完整 dsh CLI）。
  cli = pkgs.writeShellScript "dsh" ''
    set -a
    ${environmentSource}
    set +a
    export DSH_HOME=${lib.escapeShellArg cfg.dshHome}
    exec ${cfg.package}/lib/dsh-desktop/resources/runtime/primary-runtime/dependencies/node/bin/node \
      --expose-internals \
      ${cfg.package}/lib/dsh-desktop/resources/app/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js \
      "$@"
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

  homeRelative = lib.removePrefix "${config.home.homeDirectory}/" cfg.dshHome;
in
{
  options.programs.dsh-desktop = {
    enable = lib.mkEnableOption "DSH 桌面端";

    package = lib.mkPackageOption pkgs "dsh-desktop" { };

    dshHome = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.dsh";
      description = "DSH 数据目录（DSH_HOME）绝对路径；与终端 dsh 共享。";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "启动前按顺序 source 的环境文件（如 sops 渲染的 dsh_env）；后文件优先。";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf yaml.type;
      default = { };
      description = ''
        声明式设置：键为 patch 行 id，值为该行的 config。写入
        $DSH_HOME/cordis.patch.yml；旧 settings.yaml 键名（如 ui-onboarding）会重映射。

        注意：上游 patch 语义是**整行替换**该 id 的 config，不是深合并。每行必须写全
        需要的键（例如 permission 行要连同 presets 一起写），否则该行原有键会被清掉。
      '';
    };

    patches = lib.mkOption {
      type = lib.types.listOf yaml.type;
      default = [ ];
      description = "追加到 home 层、按顺序应用的原始 patch 行（settings 之后，语义同上：整行替换）。";
    };

    cli.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        安装终端 dsh（复用桌面 payload 的官方 Node 与 CLI）。
        与旧 pkgs/dsh 的 dsh 在 PATH 上冲突，过渡期保持关闭。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          lib.hasPrefix "${config.home.homeDirectory}/" cfg.dshHome
          && cfg.dshHome != config.home.homeDirectory
          && !(lib.elem ".." (lib.splitString "/" cfg.dshHome))
          && !(lib.hasSuffix "/" cfg.dshHome);
        message = "programs.dsh-desktop.dshHome 必须是家目录内、不等于家目录、不含 .. 且无尾斜杠的绝对路径。";
      }
      {
        assertion =
          let
            ids = map (row: row.id or null) patchRows;
          in
          lib.length ids == lib.length (lib.unique ids);
        message = "programs.dsh-desktop.settings/patches 中存在重复的 patch 行 id。";
      }
    ];

    home.packages = [ cfg.package ];

    home.file =
      {
        ".local/bin/dsh-desktop".source = launcher;
      }
      // lib.optionalAttrs (patchRows != [ ]) {
        # force：home 层是声明式真源；应用/恢复流程不会改它，激活时覆盖手写内容。
        "${homeRelative}/cordis.patch.yml" = {
          source = yaml.generate "dsh-home-patch.yml" patchRows;
          force = true;
        };
      }
      // lib.optionalAttrs cfg.cli.enable {
        ".local/bin/dsh".source = cli;
      }
      // {
        # makeDesktopItem 的输出是目录（share/applications/...），home.file 需要指向文件本身。
        ".local/share/applications/deepseek-harness.desktop".source = "${desktopItem}/share/applications/deepseek-harness.desktop";
      };

  };
}
