{ lib, stdenv, fetchurl, pkg-config, postgresql, msgpack-c, callPackage, mecab, makeWrapper, xxHash }:
let
  supabase-groonga = callPackage ../supabase-groonga.nix { };
in
# Modern approach using stdenv.mkDerivation with standard PostgreSQL extension patterns
stdenv.mkDerivation rec {
  pname = "pgroonga";
  version = "3.2.5";
  
  src = fetchurl {
    url = "https://packages.groonga.org/source/${pname}/${pname}-${version}.tar.gz";
    sha256 = "sha256-GM9EOQty72hdE4Ecq8jpDudhZLiH3pP9ODLxs8DXcSY=";
  };

  nativeBuildInputs = [ pkg-config makeWrapper ];
  
  buildInputs = [ 
    postgresql 
    msgpack-c 
    supabase-groonga 
    mecab 
  ] ++ lib.optionals stdenv.isDarwin [ xxHash ];

  propagatedBuildInputs = [ supabase-groonga ];

  makeFlags = [
    "HAVE_MSGPACK=1"
    "MSGPACK_PACKAGE_NAME=msgpack-c"
    "HAVE_MECAB=1"
    "HAVE_XXHASH=1"  # Added for consistency
  ];

  # Standard PostgreSQL extension build - no custom buildPhase
  # This automatically calls 'make all' which builds all 7 components

  preConfigure = ''
    export GROONGA_LIBS="-L${supabase-groonga}/lib -lgroonga"
    export GROONGA_CFLAGS="-I${supabase-groonga}/include"
    export MECAB_CONFIG="${mecab}/bin/mecab-config"
    
    ${lib.optionalString stdenv.isDarwin ''
      export CPPFLAGS="-I${supabase-groonga}/include/groonga -I${xxHash}/include -DPGRN_VERSION=\"${version}\""
      export CFLAGS="-I${supabase-groonga}/include/groonga -I${xxHash}/include -DPGRN_VERSION=\"${version}\""
      export PG_CPPFLAGS="-Wno-error=incompatible-function-pointer-types -Wno-error=format"
    ''}
  '';

  # Standard installPhase using PostgreSQL conventions
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/lib $out/share/postgresql/extension
    
    # Install all .so files built by make all
    install -D *.so -t $out/lib/
    
    # Install control files
    install -D *.control -t $out/share/postgresql/extension
    
    # Install SQL files
    install -D data/*.sql -t $out/share/postgresql/extension
    
    runHook postInstall
  '';

  env.NIX_CFLAGS_COMPILE = lib.optionalString stdenv.isDarwin (builtins.concatStringsSep " " [
    "-Wno-error=incompatible-function-pointer-types"
    "-Wno-error=format"
    "-Wno-format"
    "-I${supabase-groonga}/include/groonga"
    "-I${xxHash}/include"
    "-DPGRN_VERSION=\"${version}\""
  ]);

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