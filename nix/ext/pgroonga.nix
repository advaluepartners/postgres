# File: nix/ext/pgroonga.nix
{ lib, stdenv, fetchurl, pkg-config, postgresql, msgpack-c, callPackage, mecab, makeWrapper, xxHash,
  # No supabase-groonga, autoconf, automake in the function signature here
  # They will be handled internally or via nativeBuildInputs
}:

let
  # supabase-groonga is defined locally, as in your original pgroonga.nix
  # callPackage here will use the pkgs from the outer scope.
  supabase-groonga = callPackage ../../supabase-groonga.nix {
    # Pass arguments needed by supabase-groonga.nix if any are not auto-detected
    # For example, if mecab-naist-jdic is needed by supabase-groonga.nix and
    # it's not automatically picked up by its own callPackage.
    # Looking at your supabase-groonga.nix, it calls:
    #   let mecab-naist-jdic = callPackage ./ext/mecab-naist-jdic { };
    # This path is relative to supabase-groonga.nix. If supabase-groonga.nix is in ./nix/
    # then ./ext/mecab-naist-jdic is ./nix/ext/mecab-naist-jdic.
    # This seems correct as is.
  };
in
stdenv.mkDerivation rec {
  pname = "pgroonga";
  version = "3.2.5";
  src = fetchurl {
    url = "https://packages.groonga.org/source/${pname}/${pname}-${version}.tar.gz";
    sha256 = "sha256-GM9EOQty72hdE4Ecq8jpDudhZLiH3pP9ODLxs8DXcSY=";
  };

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    stdenv.cc.bintools # for ar, ranlib, etc. if needed by configure/make
    # Add autoconf/automake if ./configure script needs to be (re)generated.
    # If pgroonga release tarballs always include a working 'configure', these might not be strictly necessary.
    # However, for robustness (e.g. if patches touch configure.ac), pkgs.autoreconfHook is better.
    # For now, let's assume 'configure' is present in the tarball. If not, add:
    # pkgs.autoconf pkgs.automake
    # Or, more simply: pkgs.autoreconfHook (and remove explicit autoconf/automake)
  ];
  
  buildInputs = [ postgresql msgpack-c supabase-groonga mecab ] ++ lib.optionals stdenv.isDarwin [
    xxHash
  ];

  propagatedBuildInputs = [ supabase-groonga ]; # supabase-groonga is available to this derivation

  # Flags for the ./configure script
  configureFlags = [
    "--with-pgsql-config=${postgresql}/bin/pg_config"
    # PGroonga's configure.ac uses --with-mecab-config=PATH_TO_MECAB_CONFIG
    # or relies on MECAB_CONFIG environment variable.
    # We set MECAB_CONFIG in preConfigure, so --enable-mecab should suffice.
    "--enable-mecab" # This flag enables mecab support
    "--with-groonga=${supabase-groonga}" # Points to the root of supabase-groonga derivation
  ];

  # Flags for the 'make' command (top-level Makefile)
  makeFlags = [
    "PG_CONFIG=${postgresql}/bin/pg_config" # Essential for PGXS parts invoked by top-level Makefile
    "HAVE_MSGPACK=1"
    "MSGPACK_PACKAGE_NAME=msgpack-c"
    "HAVE_MECAB=1" # If ./configure doesn't set this sufficiently for the Makefile
  ];

  # Environment variables for ./configure and make
  NIX_CFLAGS_COMPILE = lib.strings.concatStringsSep " " (
    [
      "-I${supabase-groonga}/include/groonga"
      "-I${supabase-groonga}/include" # General include for supabase-groonga
      "-DPGRN_VERSION=\"${version}\""
    ] ++ lib.optionals stdenv.isDarwin [
      "-Wno-error=incompatible-function-pointer-types"
      "-Wno-error=format" # -Wno-format is covered by this
      "-I${xxHash}/include"
    ]
  );
  
  # preConfigure runs before the configurePhase.
  preConfigure = ''
    export GROONGA_LIBS="-L${supabase-groonga}/lib -lgroonga"
    export GROONGA_CFLAGS="-I${supabase-groonga}/include -I${supabase-groonga}/include/groonga"
    export MECAB_CONFIG="${mecab}/bin/mecab-config" # Used by ./configure
    
    # Ensure CPPFLAGS also get NIX_CFLAGS_COMPILE for ./configure
    export CPPFLAGS="$NIX_CFLAGS_COMPILE ''${CPPFLAGS:-}"
    # CFLAGS is usually set by stdenv based on NIX_CFLAGS_COMPILE. Explicitly setting can ensure it for configure.
    export CFLAGS="$NIX_CFLAGS_COMPILE ''${CFLAGS:-}"

    # PG_CPPFLAGS for PGXS builds on Darwin (often handled by NIX_CFLAGS_COMPILE now)
    ${lib.optionalString stdenv.isDarwin ''
      export PG_CPPFLAGS="-Wno-error=incompatible-function-pointer-types -Wno-error=format"
    ''}

    # If 'configure' script is not in the tarball (unlikely for releases), run autogen.sh
    # if [ ! -f configure -a -f autogen.sh ]; then
    #   ./autogen.sh
    # fi
  '';
  
  # configurePhase: Default stdenv behavior will run ./configure with $configureFlags
  # if a ./configure script exists.
  # buildPhase: Default stdenv behavior will run 'make' with $makeFlags.
  # This should use the top-level Makefile from PGroonga.

  installPhase = ''
    runHook preInstall

    # Use the top-level Makefile's install target.
    make install DESTDIR=$out

    # Verification steps (highly recommended)
    if [ ! -f "$out/lib/pgroonga${postgresql.dlSuffix}" ]; then
      echo "ERROR: $out/lib/pgroonga${postgresql.dlSuffix} not found after 'make install'!"
      # Try to find it in the build directory and copy manually if make install failed placement
      if [ -f "pgroonga${postgresql.dlSuffix}" ]; then
          mkdir -p $out/lib
          install -D pgroonga${postgresql.dlSuffix} $out/lib/
      else
          ls -lA . # List current directory for debugging
          exit 1
      fi
    fi
    
    if [ ! -f "$out/lib/pgroonga_database${postgresql.dlSuffix}" ]; then
      echo "ERROR: $out/lib/pgroonga_database${postgresql.dlSuffix} not found after 'make install'!"
      if [ -f "pgroonga_database${postgresql.dlSuffix}" ]; then
          mkdir -p $out/lib
          install -D pgroonga_database${postgresql.dlSuffix} $out/lib/
      else
          ls -lA . # List current directory for debugging
          exit 1
      fi
    fi

    # Verify control and SQL files (example for pgroonga, repeat for pgroonga_database)
    if [ ! -f "$out/share/postgresql/extension/pgroonga.control" ]; then
        echo "ERROR: $out/share/postgresql/extension/pgroonga.control not found!"
        if [ -f pgroonga.control ]; then # Check if it's in build dir
            mkdir -p $out/share/postgresql/extension
            install -D pgroonga.control $out/share/postgresql/extension/
            install -D sql/pgroonga--${version}.sql $out/share/postgresql/extension/ # Assuming 'sql' subdir
            install -D uninstall_pgroonga.sql $out/share/postgresql/extension/
        else
            exit 1
        fi
    fi
     if [ ! -f "$out/share/postgresql/extension/pgroonga_database.control" ]; then
        echo "ERROR: $out/share/postgresql/extension/pgroonga_database.control not found!"
        if [ -f pgroonga_database.control ]; then
            mkdir -p $out/share/postgresql/extension
            install -D pgroonga_database.control $out/share/postgresql/extension/
            install -D sql/pgroonga_database--${version}.sql $out/share/postgresql/extension/
            install -D uninstall_pgroonga_database.sql $out/share/postgresql/extension/
        else
            exit 1
        fi
    fi
    
    # Remove $out/bin if it exists and is empty (some 'make install' might create it)
    if [ -d "$out/bin" ] && [ -z "$(ls -A $out/bin)" ]; then
      rmdir "$out/bin"
    fi
    
    echo "Debug: supabase-groonga plugins directory contents:"
    if [ -d "${supabase-groonga}/lib/groonga/plugins/tokenizers/" ]; then
      ls -l ${supabase-groonga}/lib/groonga/plugins/tokenizers/
    else
      echo "Groonga plugins directory not found at ${supabase-groonga}/lib/groonga/plugins/tokenizers/"
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "A PostgreSQL extension to use Groonga as the index";
    longDescription = ''
      PGroonga is a PostgreSQL extension to use Groonga as the index.
      PostgreSQL supports full text search against languages that use only alphabet and digit.
      It means that PostgreSQL doesn't support full text search against Japanese, Chinese and so on.
      You can use super fast full text search feature against all languages by installing PGroonga into your PostgreSQL.
    '';
    homepage = "https://pgroonga.github.io/";
    changelog = "https://github.com/pgroonga/pgroonga/releases/tag/${version}";
    license = licenses.postgresql;
    platforms = postgresql.meta.platforms;
  };
}