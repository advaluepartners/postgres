{ lib, stdenv, fetchurl, postgresql, openssl, bison, flex, pkgs }: # Added pkgs

let
  pgMajorStr = lib.versions.major postgresql.version; # e.g., "15" or "17"
  ageVersion = "1.5.0"; # This is the AGE version, defined here

  ageSrcInfo =
    if pgMajorStr == "15" then {
      url = "https://dlcdn.apache.org/age/PG15/${ageVersion}/apache-age-${ageVersion}-src.tar.gz";
      hash = "sha256-7iuLsE/XKgcLo48vzUpZBJcs67oJwoCL817RPAua8nA="; 
      isSupported = true;
    } else if pgMajorStr == "16" then {
      url = "https://dlcdn.apache.org/age/PG16/${ageVersion}/apache-age-${ageVersion}-src.tar.gz";
      hash = "sha256-031wczk98cyqr1536h49f3mdjq4pmbbmbidp00s3sqmjc6z7yy5i"; # Use the hash you got
      isSupported = true;
    } else { # This covers PG17 and any other unsupported versions
      isSupported = false;
      url = ""; 
      hash = ""; 
    };
in
stdenv.mkDerivation rec {
  pname = "age";
  version = ageVersion; # Explicitly set version to ageVersion

  # Conditionally fetch source or use a dummy if unsupported
  src = if ageSrcInfo.isSupported then fetchurl {
    url = ageSrcInfo.url;
    sha256 = ageSrcInfo.hash;
  } else pkgs.runCommand "fake-age-src-${pname}-${version}" {} "mkdir -p $out"; # Dummy src

  nativeBuildInputs = [ bison flex ];
  buildInputs = [ postgresql openssl ];

  makeFlags = [
    "PG_CONFIG=${postgresql}/bin/pg_config"
    # Corrected PG_CPPFLAGS from previous attempt, assuming ${src} points to unpacked root
    "PG_CPPFLAGS=-I${src}/include -I${src}/include/catalog -I${src}/src/include -I${src}/src/include/catalog -Wno-error -Wno-deprecated-non-prototype -Wno-cast-function-type-strict"
  ];

  preBuild = ''
    # This phase will not run if src is the dummy derivation
    if [ ! -f "${src}/include/catalog/ag_catalog.h" ]; then
      echo "Skipping preBuild checks for dummy source or ag_catalog.h not found where expected."
      echo "Attempted path: ${src}/include/catalog/ag_catalog.h"
      # If it's a real source and the file is missing, it's an error.
      # If it's the dummy source, this 'if' body won't execute meaningfully.
      if [ -d "${src}/include" ]; then # Check if it's a real source directory
          echo "ERROR: ag_catalog.h not found in a real source directory!"
          ls -R ${src} # List contents for debugging
          exit 1
      fi
    else
      echo "Found ag_catalog.h in ${src}/include/catalog"
    fi
    if ! command -v flex >/dev/null 2>&1; then
      echo "ERROR: flex is not found in the build environment. Path: $PATH"
      exit 1
    fi
    echo "Flex version: $(flex --version)"
  '';

  installPhase = if ageSrcInfo.isSupported then ''
    runHook preInstall

    make install DESTDIR=$out PG_CONFIG=${postgresql}/bin/pg_config

    PKGLIBDIR=$(${postgresql}/bin/pg_config --pkglibdir)
    SHAREDIR=$(${postgresql}/bin/pg_config --sharedir)

    mkdir -p $out/lib
    mkdir -p $out/share/postgresql/extension

    found_so=false
    if [ -d "$out$PKGLIBDIR" ]; then
        echo "Looking for .so in $out$PKGLIBDIR"
        if mv $out$PKGLIBDIR/age*.so $out/lib/ 2>/dev/null; then
            found_so=true
            echo "Moved .so from $out$PKGLIBDIR"
        fi
    fi
    if [ "$found_so" = "false" ] && [ -d "$out/usr/local/pgsql/lib" ]; then # Common fallback for non-DESTDIR compliant makefiles
        echo "AGE .so not found in specific pkglibdir, trying $out/usr/local/pgsql/lib"
        if mv $out/usr/local/pgsql/lib/age*.so $out/lib/ 2>/dev/null; then
            found_so=true
            echo "Moved .so from $out/usr/local/pgsql/lib"
        fi
    fi
    if [ "$found_so" = "false" ]; then
        echo "AGE .so not found in pkglibdir, searching more broadly in $out"
        find "$out" -name "age*.so" -print -exec mv {} $out/lib/ \; || echo "Still no .so found"
    fi

    found_control_sql=false
    if [ -d "$out$SHAREDIR/extension" ]; then
        echo "Looking for control/sql in $out$SHAREDIR/extension"
        if mv $out$SHAREDIR/extension/age*.* $out/share/postgresql/extension/ 2>/dev/null; then
            found_control_sql=true
            echo "Moved control/sql from $out$SHAREDIR/extension"
        fi
    fi
    if [ "$found_control_sql" = "false" ] && [ -d "$out/usr/local/pgsql/share/extension" ]; then # Common fallback
         echo "AGE control/sql not found in specific sharedir, trying $out/usr/local/pgsql/share/extension"
        if mv $out/usr/local/pgsql/share/extension/age*.* $out/share/postgresql/extension/ 2>/dev/null; then
            found_control_sql=true
            echo "Moved control/sql from $out/usr/local/pgsql/share/extension"
        fi
    fi
    if [ "$found_control_sql" = "false" ]; then
        echo "AGE control/sql files not found in sharedir, searching more broadly in $out"
        find "$out" -path "*/extension/age.control" -print -exec mv {} $out/share/postgresql/extension/ \; || echo "age.control not found"
        find "$out" -path "*/extension/age--*.sql" -print -exec mv {} $out/share/postgresql/extension/ \; || echo "age SQL files not found"
    fi

    if [ -d "$out/usr" ]; then find "$out/usr" -depth -type d -empty -delete; fi
    if [ -d "$out/nix" ]; then find "$out/nix" -depth -type d -empty -delete; fi

    echo "Final .so files in $out/lib:"
    ls -lR $out/lib | grep age || echo "No age .so files in $out/lib"
    echo "Final .control/.sql files in $out/share/postgresql/extension:"
    ls -lR $out/share/postgresql/extension | grep age || echo "No age control/sql files in $out/share/postgresql/extension"

    runHook postInstall
  '' else ''
    echo "Skipping install for unsupported AGE/PG combination for ${pname}-${version}."
    mkdir -p $out/lib $out/share/postgresql/extension # Create empty dirs so the derivation is valid
  '';

  meta = with lib; {
    description = "Apache AGE graph database extension for PostgreSQL";
    homepage = "https://age.apache.org/";
    license = licenses.asl20;
    platforms = postgresql.meta.platforms;
    maintainers = [ maintainers.barneycook ];
    broken = !ageSrcInfo.isSupported; # Mark as broken if not supported for this PG major version
  };
}