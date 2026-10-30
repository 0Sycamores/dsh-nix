{
  pkgs,
  src,
}:

pkgs.runCommand "dsh-nix-scripts-check"
  {
    nativeBuildInputs = [
      pkgs.shellcheck
      pkgs.nixfmt
      pkgs.findutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail
    cd ${src}

    shellcheck scripts/*.sh nix/build-*.sh nix/install-*.sh nix/normalize-tarballs.sh

    for file in scripts/*.sh nix/build-*.sh nix/install-*.sh nix/normalize-tarballs.sh; do
      bash -n "$file"
    done

    nixfmt --check flake.nix $(find nix -name '*.nix' -type f)

    touch $out
  ''
