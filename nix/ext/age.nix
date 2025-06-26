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

  installPhase = if ageSrcInfo.isSupported then ''
    runHook preInstall
    
    mkdir -p $out/lib $out/share/postgresql/extension
    
    # Copy the shared library
    cp age${postgresql.dlSuffix} $out/lib/
    
    # Copy SQL and control files
    cp sql/age*.sql $out/share/postgresql/extension/ || true
    cp age.control $out/share/postgresql/extension/ || true
    
    # Handle cross-compilation library naming
    ${lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform) ''
      if [ -f age.so ] && [ ! -f $out/lib/age.so ]; then
        cp age.so $out/lib/
      fi
    ''}
    
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