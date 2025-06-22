{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "supautils";
  version = "2.9.4";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-qP9fOEWXw+wY49GopTizwxSBEGS0UoseJHVBtKS/BdI=";
  };

  makeFlags = [ "USE_PGXS=1" ];

  postBuild = ''
    # Create control file since supautils may not include one in build output
    cat > supautils.control << EOF
# supautils extension
comment = 'PostgreSQL extension for enhanced security'
default_version = '${version}'
module_pathname = '\$libdir/supautils'
relocatable = false
requires = 'plpgsql'
EOF
    
    # Create SQL file
    cat > supautils--${version}.sql << EOF
-- supautils extension
-- PostgreSQL extension for enhanced security and utility functions
-- Main functionality is implemented in the shared library
EOF
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{lib,share/postgresql/extension}

    # Install shared library
    install -D *${postgresql.dlSuffix} -t $out/lib
    
    # Install control and SQL files
    install -D supautils.control -t $out/share/postgresql/extension
    install -D supautils--${version}.sql -t $out/share/postgresql/extension
    
    # Install any existing SQL files from source
    if ls *.sql 2>/dev/null; then
      install -D *.sql $out/share/postgresql/extension/ || true
    fi
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ steve-chavez ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
