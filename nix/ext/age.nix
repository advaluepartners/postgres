{ lib, stdenv, fetchurl, postgresql, openssl, bison, flex, perl, readline, zlib, pkgs }:

# Apache AGE PostgreSQL Extension
# Dependencies based on Apache AGE official documentation:
# - gcc (provided by stdenv)
# - glibc (provided by stdenv)  
# - readline/libreadline-dev
# - zlib/zlib1g-dev
# - flex
# - bison
# - perl (required for keyword list generation)

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

  # FIXED: Added perl to nativeBuildInputs for keyword list generation
  nativeBuildInputs = [ bison flex perl ];
  # FIXED: Added readline and zlib per Apache AGE documentation requirements
  buildInputs = [ postgresql openssl readline zlib ];

  makeFlags = [
    "USE_PGXS=1" 
    "PG_CONFIG=${postgresql}/bin/pg_config"
  ];

  # Ensure all required tools are available in PATH during build
  preBuild = lib.optionalString ageSrcInfo.isSupported ''
    export PATH="${perl}/bin:$PATH"
    echo "=== Apache AGE Build Dependencies Check ==="
    echo "Perl path: $(which perl)"
    echo "Perl version: $(perl --version | head -1)"
    echo "Bison version: $(bison --version | head -1)"
    echo "Flex version: $(flex --version | head -1)"
    echo "GCC version: $(gcc --version | head -1)"
    echo "Readline library: ${readline}/lib"
    echo "Zlib library: ${zlib}/lib"
    echo "============================================"
  '';

  installPhase = if ageSrcInfo.isSupported then ''
    runHook preInstall
    make install USE_PGXS=1 PG_CONFIG=${postgresql}/bin/pg_config
    runHook postInstall
  '' else ''
    echo "Skipping install for unsupported AGE/PG combination."
    mkdir -p $out/lib $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Apache AGE graph database extension for PostgreSQL";
    homepage = "https://age.apache.org/";
    license = licenses.asl20;
    platforms = postgresql.meta.platforms;
    maintainers = [ maintainers.barneycook ];
    broken = !ageSrcInfo.isSupported;
  };
}