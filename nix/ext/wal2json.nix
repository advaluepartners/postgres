{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "wal2json";
  version = "2_6";

  src = fetchFromGitHub {
    owner = "eulerto";
    repo = "wal2json";
    rev = "wal2json_${builtins.replaceStrings ["."] ["_"] version}";
    hash = "sha256-+QoACPCKiFfuT2lJfSUmgfzC5MXf75KpSoc2PzPxKyM=";
  };

  buildInputs = [ postgresql ];

  makeFlags = [ "USE_PGXS=1" ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{lib,share/postgresql/extension}
    
    # Install shared library
    install -D *${postgresql.dlSuffix} $out/lib
    
    # Install SQL files
    install -D -t $out/share/postgresql/extension sql/*.sql
    
    # Create control file for wal2json extension
    cat > $out/share/postgresql/extension/wal2json.control << EOF
# wal2json extension
comment = 'JSON output plugin for changeset extraction'
default_version = '2.6'
module_pathname = '\$libdir/wal2json'
relocatable = false
EOF
    
    # Create main SQL file
    cat > $out/share/postgresql/extension/wal2json--2.6.sql << EOF
-- wal2json extension
-- This extension provides JSON output for logical decoding
-- The actual functionality is implemented in the wal2json shared library
EOF
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "PostgreSQL JSON output plugin for changeset extraction";
    homepage = "https://github.com/eulerto/wal2json";
    changelog = "https://github.com/eulerto/wal2json/releases/tag/wal2json_${version}";
    platforms = postgresql.meta.platforms;
    license = licenses.bsd3;
  };
}
