# nix/ext/age.nix
{ lib, stdenv, fetchurl, postgresql, openssl, bison, flex }:

stdenv.mkDerivation rec {
  pname = "age";
  # Apache AGE 1.5.0 is compatible with PostgreSQL 15.
  # Source: https://age.apache.org/download/
  version = "1.5.0";

  src = fetchurl {
    url = "https://dlcdn.apache.org/age/PG15/1.5.0/apache-age-1.5.0-src.tar.gz";
    hash = "sha256-7iuLsE/XKgcLo48vzUpZBJcs67oJwoCL817RPAua8nA=";
  };

  nativeBuildInputs = [ bison flex ]; # Build tools for AGE
  buildInputs = [
    postgresql # Provides pg_config
    openssl
  ];

  # AGE uses PGXS. Setting PG_CONFIG should be enough for 'make'.
  makeFlags = [
    "PG_CONFIG=${postgresql}/bin/pg_config"
    # Add "PG_CPPFLAGS=-Wno-error" if the AGE build is too strict with warnings
    # and fails on your compiler version.
  ];

  # PGXS 'make install' with DESTDIR places files in system-like paths
  # prefixed by DESTDIR. We need to move them to the flat $out structure Nix expects.
  installPhase = ''
    runHook preInstall

    make install DESTDIR=$out PG_CONFIG=${postgresql}/bin/pg_config

    # Query pkglibdir and sharedir using pg_config
    PKGLIBDIR=$(${postgresql}/bin/pg_config --pkglibdir)
    SHAREDIR=$(${postgresql}/bin/pg_config --sharedir)

    # Create standard $out directories
    mkdir -p $out/lib
    mkdir -p $out/share/postgresql/extension

    # Try to find and move the .so file (age.so)
    found_so=false
    if [ -d "$out$PKGLIBDIR" ]; then
        echo "Looking for .so in $out$PKGLIBDIR"
        if mv $out$PKGLIBDIR/age*.so $out/lib/ 2>/dev/null; then
            found_so=true
            echo "Moved .so from $out$PKGLIBDIR"
        fi
    fi
    if [ "$found_so" = "false" ]; then
        # Fallback: search more broadly if not found in specific pkglibdir
        echo "AGE .so not found in specific pkglibdir, searching more broadly in $out"
        find "$out" -name "age*.so" -print -exec mv {} $out/lib/ \;
    fi

    # Try to find and move .control and .sql files
    found_control_sql=false
    if [ -d "$out$SHAREDIR/extension" ]; then
        echo "Looking for control/sql in $out$SHAREDIR/extension"
        if mv $out$SHAREDIR/extension/age*.* $out/share/postgresql/extension/ 2>/dev/null; then
            found_control_sql=true
            echo "Moved control/sql from $out$SHAREDIR/extension"
        fi
    fi
    if [ "$found_control_sql" = "false" ]; then
        echo "AGE control/sql files not found in specific sharedir, searching more broadly in $out"
        find "$out" -path "*/extension/age.control" -print -exec mv {} $out/share/postgresql/extension/ \;
        find "$out" -path "*/extension/age--*.sql" -print -exec mv {} $out/share/postgresql/extension/ \;
    fi

    # Clean up potentially empty directory structures left by DESTDIR install
    if [ -d "$out/usr" ]; then find "$out/usr" -depth -type d -empty -delete; fi
    if [ -d "$out/nix" ]; then find "$out/nix" -depth -type d -empty -delete; fi

    # Verify files are in the correct final $out locations
    echo "Final .so files in $out/lib:"
    ls -lR $out/lib | grep age
    echo "Final .control/.sql files in $out/share/postgresql/extension:"
    ls -lR $out/share/postgresql/extension | grep age

    runHook postInstall
  '';

  meta = with lib; {
    description = "Apache AGE graph database extension for PostgreSQL";
    homepage = "https://age.apache.org/";
    license = licenses.asl20; # Apache License 2.0
    platforms = postgresql.meta.platforms;
    maintainers = [ maintainers.advaluepartners ]; # Update with your actual GitHub handle if different
  };
}