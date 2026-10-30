{
  pkgs,
  src,
}:

pkgs.runCommand "dsh-runtime-lockfile-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 ${./check-runtime-lockfile.py} ${src}/nix/runtime/project
    touch $out
  ''
