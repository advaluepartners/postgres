{ lib, stdenv, fetchurl, postgresql, bison, flex, perl, pkgs }:

let
  pgMajorStr = lib.versions.major postgresql.version;
  ageVersion = "1.5.0";

  ageSrcInfo =
    if pgMajorStr == "15" then {
      url = "https://dlcdn.apache.org/age/PG15/${ageVersion}/apache-age-${ageVersion}-src.tar.gz";
      hash = "sha256-7iuLsE/XKgcLo48vzUpZBJcs67oJwoCL817RPAua8nA=";
      isSupported = true;
    } else if pgMajorStr == "16" then {
      url = "https://dlcdn.apache.org/age/PG16/${ageVersion}/apache-age-${ageVersion}-src.tar.gz";
      hash = "sha256-031wczk98cyqr1536h49f3mdjq4pmbbmbidp00s3sqmjc6z7yy5i";
      isSupported = true;
    } else {
      isSupported = false;
      url = "";
      hash = "";
    };
in
stdenv.mkDerivation rec {
  pname = "age";
  version = ageVersion;

  src = if ageSrcInfo.isSupported then fetchurl {
    url = ageSrcInfo.url;
    sha256 = ageSrcInfo.hash;
  } else pkgs.runCommand "fake-age-src-${pname}-${version}" {} "mkdir -p $out";

  # Add all required build tools
  nativeBuildInputs = [ bison flex perl ] ++ lib.optionals stdenv.isDarwin [
    pkgs.xcbuild
  ];
  
  buildInputs = [ postgresql ] ++ lib.optionals stdenv.isDarwin [
    pkgs.darwin.apple_sdk.frameworks.CoreFoundation
  ];

  # Fix for cross-compilation
  makeFlags = [
    "USE_PGXS=1" 
    "PG_CONFIG=${postgresql}/bin/pg_config"
    "BISON=${bison}/bin/bison"
    "FLEX=${flex}/bin/flex"
    "PERL=${perl}/bin/perl"
  ] ++ lib.optionals (stdenv.buildPlatform != stdenv.hostPlatform) [
    "CC=${stdenv.cc.targetPrefix}cc"
    "CXX=${stdenv.cc.targetPrefix}c++"
  ];

  # Cross-compilation environment
  preConfigure = lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform) ''
    export PGXS=${postgresql}/lib/pgxs/src/makefiles/pgxs.mk
    export PG_CONFIG=${postgresql}/bin/pg_config
  '';

  # CRITICAL FIX: Follow AGE's exact build process
  postBuild = if ageSrcInfo.isSupported then ''
    echo "=== Creating AGE installation script following official build process ==="
    
    # Read the sql_files list (same as AGE Makefile does)
    SQL_FILES=$(cat sql/sql_files)
    
    # Create the main installation script by concatenating files in dependency order
    echo "-- Apache AGE ${version} Installation Script" > age--${version}.sql
    echo "-- Generated following official AGE build process" >> age--${version}.sql
    echo "" >> age--${version}.sql
    
    # Add each SQL file in the exact order specified by sql_files
    for sql_file in $SQL_FILES; do
      echo "-- Including $sql_file.sql" >> age--${version}.sql
      if [ -f "sql/$sql_file.sql" ]; then
        cat "sql/$sql_file.sql" >> age--${version}.sql
        echo "" >> age--${version}.sql
        echo "Added $sql_file.sql"
      else
        echo "ERROR: Missing required SQL file: sql/$sql_file.sql"
        exit 1
      fi
    done
    
    echo "=== AGE installation script created successfully ==="
    echo "Script size: $(wc -l age--${version}.sql)"
    echo "First few lines:"
    head -10 age--${version}.sql
  '' else "";

  installPhase = if ageSrcInfo.isSupported then ''
    runHook preInstall
    
    echo "=== Installing AGE extension files ==="
    mkdir -p $out/lib $out/share/postgresql/extension
    
    # Copy the shared library
    if [ -f "age${postgresql.dlSuffix}" ]; then
      cp age${postgresql.dlSuffix} $out/lib/
      echo "Copied age${postgresql.dlSuffix}"
    fi
    
    # Handle cross-compilation library naming
    ${lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform) ''
      if [ -f age.so ] && [ ! -f $out/lib/age.so ]; then
        cp age.so $out/lib/
        echo "Copied age.so (cross-compiled)"
      fi
    ''}
    
    # Copy the main installation script (CRITICAL - this is what was missing!)
    if [ -f "age--${version}.sql" ]; then
      cp age--${version}.sql $out/share/postgresql/extension/
      echo "Copied main installation script: age--${version}.sql"
    else
      echo "ERROR: Main installation script not found!"
      echo "Looking for age--${version}.sql in current directory:"
      ls -la age--*.sql || echo "No age--*.sql files found"
      exit 1
    fi
    
    # Copy control file
    if [ -f "age.control" ]; then
      cp age.control $out/share/postgresql/extension/
      echo "Copied age.control"
    else
      echo "ERROR: age.control not found!"
      exit 1
    fi
    
    # Copy individual component SQL files (these are still needed for debugging/reference)
    echo "Copying individual SQL component files..."
    SQL_FILES=$(cat sql/sql_files)
    for sql_file in $SQL_FILES; do
      if [ -f "sql/$sql_file.sql" ]; then
        cp "sql/$sql_file.sql" $out/share/postgresql/extension/
        echo "Copied $sql_file.sql"
      else
        echo "WARNING: Component file sql/$sql_file.sql not found"
      fi
    done
    
    # Final verification
    echo "=== AGE installation verification ==="
    echo "Library files:"
    ls -la $out/lib/age* || echo "No library files found"
    echo "Extension files:"
    ls -la $out/share/postgresql/extension/age*
    
    # Critical check: verify main installation script exists and has content
    if [ ! -f "$out/share/postgresql/extension/age--${version}.sql" ]; then
      echo "ERROR: Main installation script missing after install!"
      exit 1
    fi
    
    SCRIPT_SIZE=$(wc -l < "$out/share/postgresql/extension/age--${version}.sql")
    if [ "$SCRIPT_SIZE" -lt 100 ]; then
      echo "ERROR: Main installation script too small ($SCRIPT_SIZE lines) - build failed!"
      exit 1
    fi
    
    echo "SUCCESS: Main installation script has $SCRIPT_SIZE lines"
    echo "=== AGE installation completed successfully ==="
    
    runHook postInstall
  '' else ''
    echo "Skipping install for unsupported AGE/PG combination."
    mkdir -p $out/lib $out/share/postgresql/extension
    touch $out/lib/.empty
  '';

  meta = with lib; {
    description = "Apache AGE graph database extension for PostgreSQL";
    homepage = "https://age.apache.org/";
    license = licenses.asl20;
    platforms = postgresql.meta.platforms;
    broken = !ageSrcInfo.isSupported;
  };
}