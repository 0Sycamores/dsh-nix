{
  pkgs,
  home-manager,
  dsh-nix,
}:

let
  # 只求值 activationPackage.drvPath；断言在求值阶段触发，tryEval 能捕获。
  testCli = pkgs.writeShellScriptBin "dsh" "exit 0";
  baseModules = [
    dsh-nix.homeModules.dsh
    {
      home.username = "dsh-test";
      home.homeDirectory = "/home/dsh-test";
      home.stateVersion = "26.05";
      programs.dsh = {
        enable = true;
        package = testCli;
      };
    }
  ];

  valid = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = baseModules;
  };

  invalid = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = baseModules ++ [
      {
        programs.dsh.settings.ui-onboarding.welcomeNoticeVersion = "must-not-be-declared";
      }
    ];
  };

  validResult = builtins.tryEval valid.activationPackage.drvPath;
  invalidResult = builtins.tryEval invalid.activationPackage.drvPath;
in
if !validResult.success then
  throw "positive control failed: the base programs.dsh configuration does not evaluate"
else if invalidResult.success then
  throw "programs.dsh accepted a forbidden welcomeNoticeVersion declaration; the assertion regressed"
else
  pkgs.runCommand "dsh-welcome-pin-negative-check" { } ''
    touch $out
  ''
