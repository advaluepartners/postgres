{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg-safeupdate";
  version = "1.4";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner  = "eradman";
    repo   = pname;
    rev    = version;
    hash = "sha256-1cyvVEC9MQGMr7Tg6EUbsVBrMc8ahdFS3+CmDkmAq4Y=";
  };

  makeFlags = [ "USE_PGXS=1" ];

  buildPhase = ''
    runHook preBuild
    make $makeFlags
    runHook postBuild
  '';

  postBuild = ''
    # Create control file since the source doesn't include one
    cat > safeupdate.control << EOF
# safeupdate extension
comment = 'Require criteria for UPDATE and DELETE'
default_version = '${version}'
module_pathname = '\$libdir/safeupdate'
relocatable = true
EOF
    
    # Create SQL file
    cat > safeupdate--${version}.sql << EOF
-- safeupdate extension
-- Prevents UPDATE and DELETE commands without WHERE clause
-- No additional SQL setup required - functionality is in shared library
EOF
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{lib,share/postgresql/extension}
    
    # Install shared library
    install -D safeupdate${postgresql.dlSuffix} -t $out/lib
    
    # Install control and SQL files (now they exist because we created them in postBuild)
    install -D safeupdate.control -t $out/share/postgresql/extension
    install -D safeupdate--${version}.sql -t $out/share/postgresql/extension
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "A simple extension to PostgreSQL that requires criteria for UPDATE and DELETE";
    homepage    = "https://github.com/eradman/pg-safeupdate";
    changelog   = "https://github.com/eradman/pg-safeupdate/raw/${src.rev}/NEWS";
    platforms   = postgresql.meta.platforms;
    license     = licenses.postgresql;
    broken      = versionOlder postgresql.version "14";
  };
}
