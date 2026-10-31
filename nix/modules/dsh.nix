# Home Manager 模块：DSH 的共享配置与终端/Web CLI。
#
# 与 programs.dsh-desktop 的分工：
#   - 本模块只负责「所有 surface 共用」的东西：$DSH_HOME、环境文件、声明式
#     home 层 patch、以及带这些环境的 dsh 命令。
#   - 桌面模块只负责 Electron 外壳；它读取本模块的 dshHome/environmentFiles。
#
# 声明式设置写入 $DSH_HOME/cordis.patch.yml，由 app-boot 在 bundles → profile
# 用户层之后叠加，对所有 profile 生效（机器级偏好，优先级高于 profile 层、
# 低于命令行 --patch）。不生成可变的 settings.yaml 副本。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.dsh;
  yaml = pkgs.formats.yaml { };

  # 旧 settings.yaml 键 → 新 patch 行 id 的重映射（上游 LEGACY_SECTION_ENTRIES；
  # shell 段在本仓库目标平台 Linux 上映射到 bash-sandbox）。
  legacySettingsIds = {
    "ui-developer-tools" = "ui-settings";
    "ui-onboarding" = "ui-settings-general";
    "shell" = "bash-sandbox";
  };

  settingsRows = lib.mapAttrsToList (id: value: {
    id = legacySettingsIds.${id} or id;
    config = value;
  }) cfg.settings;
  patchRows = settingsRows ++ cfg.patches;

  # welcomeNoticeVersion 由 UI 自己持久化；声明在 home 层会覆盖 UI 的写入，
  # 且上游一改 WELCOME_NOTICE_VERSION 就会卡在“暂时无法保存确认状态”。
  welcomePinned =
    cfg.settings ? "ui-onboarding"
    || (
      let
        section = cfg.settings."ui-settings-general" or null;
      in
      lib.isAttrs section && section ? welcomeNoticeVersion
    )
    || lib.any (
      row:
      lib.isAttrs row
      && (
        (row.id or null) == "ui-onboarding"
        || (
          (row.id or null) == "ui-settings-general"
          && lib.isAttrs (row.config or null)
          && (row.config ? welcomeNoticeVersion)
        )
      )
    ) cfg.patches;

  environmentSource = lib.concatMapStringsSep "\n" (file: ''
    if [ -r ${lib.escapeShellArg file} ]; then
      . ${lib.escapeShellArg file}
    fi
  '') cfg.environmentFiles;

  cli = pkgs.writeShellScriptBin "dsh" ''
    set -a
    ${environmentSource}
    set +a
    export DSH_HOME=${lib.escapeShellArg cfg.dshHome}
    exec ${cfg.package}/bin/dsh "$@"
  '';

  homeRelative = lib.removePrefix "${config.home.homeDirectory}/" cfg.dshHome;
in
{
  options.programs.dsh = {
    enable = lib.mkEnableOption "DSH 共享配置与终端/Web CLI";

    package = lib.mkPackageOption pkgs "dsh" { };

    dshHome = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.dsh";
      description = "DSH 数据目录（DSH_HOME）绝对路径；桌面端、终端与 Web 共用。";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "dsh 启动前按顺序 source 的环境文件（如 sops 渲染的 dsh_env）；后文件优先。";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf yaml.type;
      default = { };
      description = ''
        声明式设置：键为 patch 行 id，值为该行的 config。写入
        $DSH_HOME/cordis.patch.yml；旧 settings.yaml 键名（如 ui-onboarding）会重映射。

        注意：上游 patch 语义是**整行替换**该 id 的 config，不是深合并。每行必须写全
        需要的键（例如 permission 行要连同 presets 一起写），否则该行原有键会被清掉。

        不要声明 `ui-onboarding` 或 `ui-settings-general.welcomeNoticeVersion`：预览版
        说明的确认状态由 UI 自己持久化，home 层声明会覆盖 UI 写入并导致 Continue 失败。
      '';
    };

    patches = lib.mkOption {
      type = lib.types.listOf yaml.type;
      default = [ ];
      description = "追加到 home 层、按顺序应用的原始 patch 行（settings 之后，语义同上：整行替换）。";
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
        message = "programs.dsh.dshHome 必须是家目录内、不等于家目录、不含 .. 且无尾斜杠的绝对路径。";
      }
      {
        assertion = !welcomePinned;
        message = "programs.dsh.settings/patches 不要声明 ui-onboarding 或 ui-settings-general.welcomeNoticeVersion：该确认状态必须由 UI 持久化，home 层声明会覆盖写入并导致“暂时无法保存确认状态”。";
      }
      {
        assertion =
          let
            ids = map (row: row.id or null) patchRows;
          in
          lib.length ids == lib.length (lib.unique ids);
        message = "programs.dsh.settings/patches 中存在重复的 patch 行 id。";
      }
    ];

    home.packages = [ cli ];

    home.file = lib.optionalAttrs (patchRows != [ ]) {
      # force：home 层是声明式真源；应用/恢复流程不会改它，激活时覆盖手写内容。
      "${homeRelative}/cordis.patch.yml" = {
        source = yaml.generate "dsh-home-patch.yml" patchRows;
        force = true;
      };
    };
  };
}
