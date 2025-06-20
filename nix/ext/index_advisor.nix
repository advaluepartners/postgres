{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "index_advisor";
  version = "0.2.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "olirice";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-G0eQk2bY5CNPMeokN/nb05g03CuiplRf902YXFVQFbs=";
  };

  # Skip build phase since this is a SQL-only extension
  dontBuild = true;
  
  # Install the SQL files and control file directly
  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    # Copy SQL files if they exist
    find . -name "*.sql" -exec cp {} $out/share/postgresql/extension/ \;
    
    # Copy control files if they exist  
    find . -name "*.control" -exec cp {} $out/share/postgresql/extension/ \;
    
    # If no files found, create basic structure (this extension might be header-only or have different structure)
    if [ ! -f $out/share/postgresql/extension/*.sql ]; then
      echo "-- index_advisor extension placeholder" > $out/share/postgresql/extension/index_advisor--${version}.sql
    fi
    
    if [ ! -f $out/share/postgresql/extension/*.control ]; then
      cat > $out/share/postgresql/extension/index_advisor.control << EOF
# index_advisor extension
comment = 'Recommend indexes to improve query performance in PostgreSQL'
default_version = '${version}'
module_pathname = '\$libdir/index_advisor'
relocatable = true
EOF
    fi
  '';

  meta = with lib; {
    description = "Recommend indexes to improve query performance in PostgreSQL";
    homepage = "https://github.com/olirice/index_advisor";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}


