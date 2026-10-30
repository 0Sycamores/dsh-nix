{
  description = "DSH desktop (Linux/NixOS) Nix packaging — personal, unofficial";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # 桌面壳基线与 payload 源；必须与 nix/runtime/project 的生成版本一致。
    dsh-src = {
      url = "github:deepseek-ai/deepseek-harness/dsh-v0.2.2-alpha.2";
      flake = false;
    };
    # 仅用于 checks.hm-module：在 CI/本地渲染 HM 模块输出，不必等用户切换。
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      dsh-src,
      home-manager,
      ...
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);

      srcVersion = (nixpkgs.lib.importJSON (dsh-src + "/apps/desktop/package.json")).version;

      mkPayload =
        pkgs:
        pkgs.callPackage ./nix/payload.nix {
          inherit pkgs;
          src = dsh-src;
          srcRevision = dsh-src.rev or "0000000000000000000000000000000000000000";
        };
      mkRuntime =
        pkgs: payload:
        pkgs.callPackage ./nix/runtime.nix {
          inherit pkgs payload;
          version = srcVersion;
          upstreamSrc = dsh-src;
        };
      mkDesktop =
        pkgs:
        let
          payload = mkPayload pkgs;
        in
        pkgs.callPackage ./nix/desktop.nix {
          inherit payload;
          runtime = mkRuntime pkgs payload;
          # nixpkgs electron_44 的 libexec dist 在本机 GPU 进程会崩；用 spike 验证过的
          # electron_44-bin dist（同样的 44.9.3 官方产物，wrapper 由本包自带）。
          electron44bin = pkgs."electron_44-bin";
        };
    in
    {
      packages = forAllSystems (
        pkgs: system: {
          dsh-desktop = mkDesktop pkgs;
          dsh-desktop-payload = mkPayload pkgs;
          dsh-desktop-runtime = mkRuntime pkgs (mkPayload pkgs);
          default = self.packages.${system}.dsh-desktop;
        }
      );

      overlays.default = final: prev: {
        dsh-desktop = mkDesktop final;
      };

      homeModules = {
        default = ./nix/modules/desktop.nix;
        dsh-desktop = ./nix/modules/desktop.nix;
      };

      devShells = forAllSystems (
        pkgs: _: {
          default = pkgs.callPackage ./nix/dev-shell.nix { inherit dsh-src; };
        }
      );

      formatter = forAllSystems (pkgs: _: pkgs.nixfmt);

      checks = forAllSystems (
        pkgs: system: {
          dsh-desktop = self.packages.${system}.dsh-desktop;
          # 轻量门禁：不构建 1.3G 桌面端，只渲染 HM 输出/静态检查。
          hm-module = pkgs.callPackage ./nix/tests/hm-module.nix {
            inherit home-manager;
            dsh-nix = self;
          };
          scripts = pkgs.callPackage ./nix/tests/scripts.nix { src = self; };
          runtime-lockfile = pkgs.callPackage ./nix/tests/runtime-lockfile.nix { src = self; };
        }
      );
    };
}
