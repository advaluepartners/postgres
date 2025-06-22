{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_plan_filter";
  version = "5081a7b5cb890876e67d8e7486b6a64c38c9a492";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "pgexperts";
    repo = pname;
    rev = "${version}";
    hash = "sha256-YNeIfmccT/DtOrwDmpYFCuV2/P6k3Zj23VWBDkOh6sw=";
  };

  makeFlags = [ "USE_PGXS=1" ];

  postBuild = ''
    # Create control file since the source doesn't include one
    cat > plan_filter.control << EOF
# plan_filter extension  
comment = 'Filter PostgreSQL statements by execution plans'
default_version = '1.0'
module_pathname = '\$libdir/plan_filter'
relocatable = true
EOF
    
    # Create main SQL file
    cat > plan_filter--1.0.sql << EOF
-- plan_filter extension
-- Provides functionality to filter PostgreSQL statements by execution plans
-- Main functionality is implemented in the shared library
EOF
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{lib,share/postgresql/extension}

    # Install shared library
    install -D *${postgresql.dlSuffix} $out/lib
    
    # Install SQL files (including existing test files)
    install -D *.sql $out/share/postgresql/extension
    
    # Install control file
    install -D plan_filter.control $out/share/postgresql/extension
    install -D plan_filter--1.0.sql $out/share/postgresql/extension
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "Filter PostgreSQL statements by execution plans";
    homepage = "https://github.com/pgexperts/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
