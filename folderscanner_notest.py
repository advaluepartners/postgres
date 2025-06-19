#!/usr/bin/env python3
"""
FolderScanner - Production-ready utility to scan and document file structures.

This tool scans directories and files, respecting depth limitations and exclusion patterns,
to create comprehensive documentation of the code structure in text or markdown format.
"""
import os
import sys
import argparse
import fnmatch
import logging
import textwrap
from typing import List, Tuple, Set, Dict, Optional, Any
from dataclasses import dataclass, field

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

@dataclass
class ScanConfig:
    """Configuration for directory scanning."""
    paths: List[str]
    exclude_paths: Set[str] = field(default_factory=set)  # Specific paths to exclude (from CLI)
    exclude_patterns: Set[str] = field(default_factory=set)  # Patterns to exclude (from CLI)
    exclude_dirs: Set[str] = field(default_factory=set)  # Directory names to exclude
    exclude_files: Set[str] = field(default_factory=set)  # File patterns to exclude
    depth_specs: Dict[str, int] = field(default_factory=dict)  # Path -> depth limit mapping
    output_format: str = "txt"  # Output format: "txt" or "md"
    output_file: str = "scan_output.txt"  # Output file path

def parse_paths_with_depth(raw_paths: List[str]) -> Tuple[List[str], Dict[str, int]]:
    """
    Extract depth specifications from paths and return cleaned paths and depth specs.
    
    Format: "/path/to/dir/root+N" where N is the depth level to scan.
    
    Args:
        raw_paths: List of paths, potentially containing depth specifications
        
    Returns:
        tuple: (cleaned_paths, depth_specs)
    """
    cleaned_paths = []
    depth_specs = {}
    
    for path in raw_paths:
        if "root+" in path:
            # Extract the base path and depth
            parts = path.split("root+")
            if len(parts) == 2 and parts[1].isdigit():
                base_path = parts[0].rstrip("/")
                depth = int(parts[1])
                cleaned_paths.append(base_path)
                depth_specs[os.path.abspath(base_path)] = depth
            else:
                # Invalid format, treat as normal path
                cleaned_paths.append(path)
        else:
            cleaned_paths.append(path)
            
    return cleaned_paths, depth_specs

def normalize_paths(paths: List[str]) -> List[str]:
    """
    Convert paths to absolute and normalize them.
    
    Args:
        paths: List of paths to normalize
        
    Returns:
        List of normalized absolute paths
    """
    return [os.path.abspath(p) for p in paths]

def count_words(content: str) -> int:
    """
    Count the number of words in the content, excluding error messages.

    Args:
        content: File content or error message.

    Returns:
        int: Number of words if content is valid, else 0.
    """
    if isinstance(content, str) and not content.startswith("Error reading file:"):
        return len(content.split())
    return 0

def is_excluded(path: str, is_dir: bool, config: ScanConfig) -> bool:
    """
    Determine if a path should be excluded based on config settings.

    Args:
        path: The relative path to check.
        is_dir: True if the path is a directory, False if a file.
        config: ScanConfig object with exclusion rules.

    Returns:
        bool: True if the path should be excluded, False otherwise.
    """
    rel_path = os.path.normpath(path)
    
    # Check explicit exclusion paths
    if any(rel_path.startswith(excl) for excl in config.exclude_paths):
        return True
    
    # Check exclusion patterns
    if any(pattern in rel_path for pattern in config.exclude_patterns):
        return True
    
    # Check directory components
    components = rel_path.split(os.sep)
    
    if is_dir:
        # Check if any directory component is in the exclude list
        if any(comp in config.exclude_dirs for comp in components):
            return True
    else:
        # It's a file - check against filename patterns
        file_name = os.path.basename(rel_path)
        
        # Check exact match exclusions
        if file_name in config.exclude_files:
            return True
        
        # Check wildcards in exclude_files
        for pattern in config.exclude_files:
            if '*' in pattern and fnmatch.fnmatch(file_name, pattern):
                return True
        
        # Check for test files
        if ".test." in file_name or ".spec." in file_name:
            return True
    
    return False

def get_file_contents(file_path: str) -> str:
    """
    Read the contents of a file, handling exceptions gracefully.

    Args:
        file_path: Absolute path to the file.

    Returns:
        str: File contents or an error message if reading fails.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception as e:
        error_msg = f"Error reading file: {e}"
        logger.error(error_msg)
        return error_msg

def walk_directories(config: ScanConfig) -> List[Tuple[str, str, str]]:
    """
    Walk through directories and collect file contents, respecting depth limits and exclusions.

    Args:
        config: ScanConfig object with paths and exclusion rules.

    Returns:
        List of tuples: (root_path, relative file path, file contents).
        For single files: (full_file_path, filename, content)
        For directory files: (directory_path, relative_path_from_dir, content)
    """
    file_data = []
    
    # Process each path in the config
    for path in config.paths:
        path = os.path.abspath(path)
        
        # Handle single files
        if os.path.isfile(path):
            logger.info(f"Processing single file: {path}")
            file_name = os.path.basename(path)
            
            # Check if the file should be excluded
            if not is_excluded(file_name, False, config):
                content = get_file_contents(path)
                # FIXED: Store full file path as root_path for single files
                file_data.append((path, file_name, content))
            continue
            
        # Handle directories
        logger.info(f"Scanning directory: {path}")
        
        # Check if we have a depth limit for this path
        depth_limit = config.depth_specs.get(path)
        if depth_limit is not None:
            logger.info(f"Depth limit set to {depth_limit} for {path}")
            
            # Special handling for depth=0 to get files directly in the root directory
            if depth_limit == 0:
                try:
                    # List all entries in the directory
                    entries = os.listdir(path)
                    logger.info(f"Found {len(entries)} entries in root directory {path}")
                    
                    # Process only files (not subdirectories)
                    for entry in entries:
                        entry_path = os.path.join(path, entry)
                        if os.path.isfile(entry_path):
                            rel_path = os.path.basename(entry_path)
                            if not is_excluded(rel_path, False, config):
                                logger.info(f"Reading root file: {rel_path}")
                                content = get_file_contents(entry_path)
                                file_data.append((path, rel_path, content))
                except Exception as e:
                    logger.error(f"Error reading root directory {path}: {e}")
                
                # Skip normal directory walk when depth=0
                continue
            
        # Normal directory walk for depth > 0 or no depth limit
        for subdir, dirs, files in os.walk(path):
            # Calculate the current depth relative to the starting path
            rel_subdir = os.path.relpath(subdir, path) if subdir != path else "."
            current_depth = 0 if rel_subdir == "." else rel_subdir.count(os.sep) + 1
            
            logger.debug(f"Processing directory at depth {current_depth}: {subdir}")
            
            # Check depth limit
            if depth_limit is not None and current_depth > depth_limit:
                logger.debug(f"Skipping {subdir} - exceeds depth limit of {depth_limit}")
                dirs[:] = []  # Skip subdirectories
                continue
                
            # Check if the directory should be excluded
            if is_excluded(rel_subdir, True, config):
                logger.debug(f"Excluding directory: {rel_subdir}")
                dirs[:] = []  # Skip subdirectories
                continue
                
            # Filter out excluded directories from the list to walk
            dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_subdir, d), True, config)]
            
            # Process files in the current directory
            for file in files:
                file_path = os.path.join(subdir, file)
                rel_path = os.path.relpath(file_path, path)
                
                if not is_excluded(rel_path, False, config):
                    logger.debug(f"Reading: {rel_path}")
                    content = get_file_contents(file_path)
                    file_data.append((path, rel_path, content))
    
    logger.info(f"Total files collected: {len(file_data)}")
    return file_data

def get_directory_structure(root_path: str, config: ScanConfig) -> str:
    """
    Generate a string representation of the directory structure, excluding specified items.

    Args:
        root_path: Root directory to scan.
        config: ScanConfig object with exclusion rules.

    Returns:
        str: Formatted directory structure.
    """
    if os.path.isfile(root_path):
        return os.path.basename(root_path)
        
    structure = []
    root_name = os.path.basename(root_path)
    
    for root, dirs, files in os.walk(root_path):
        rel_path = os.path.relpath(root, root_path) if root != root_path else "."
        
        # Check depth limit
        depth_limit = config.depth_specs.get(root_path)
        current_depth = 0 if rel_path == "." else rel_path.count(os.sep) + 1
        
        if depth_limit is not None and current_depth > depth_limit:
            dirs[:] = []  # Skip subdirectories
            continue
            
        # Skip excluded directories
        if rel_path != "." and is_excluded(rel_path, True, config):
            dirs[:] = []  # Skip subdirectories
            continue
            
        # Filter dirs list in place
        dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_path, d), True, config)]
        
        # Format the current directory line
        level = rel_path.count(os.sep) if rel_path != "." else 0
        indent = ' ' * 4 * level
        
        if rel_path == ".":
            structure.append(f"{indent}{root_name}/")
        else:
            structure.append(f"{indent}{os.path.basename(root)}/")
        
        # Format the files
        sub_indent = ' ' * 4 * (level + 1)
        for file in sorted(files):
            file_rel_path = os.path.join(rel_path, file)
            if not is_excluded(file_rel_path, False, config):
                structure.append(f"{sub_indent}{file}")
    
    return "\n".join(structure)

def write_txt_output(f: Any, file_data: List[Tuple[str, str, str]], config: ScanConfig) -> None:
    """Write output in text format."""
    # Get list of unique root paths for the header
    root_paths = sorted(set(root_path for root_path, _, _ in file_data))
    root_paths_str = "\n- ".join([""] + root_paths)
    
    f.write(
        f"The below represents the folders and files from the root paths:{root_paths_str}\n\n"
        "Each file is separated by '''--- followed by the file path and ending with ---.\n"
        "File content begins immediately after its path and extends until the next '''---\n\n"
    )
    
    # Group by root path for better organization
    paths_seen = set()
    for root_path, rel_path, content in file_data:
        if root_path not in paths_seen:
            paths_seen.add(root_path)
            
            if os.path.isfile(root_path):
                # It's a single file
                f.write(f"\n*File: {os.path.basename(root_path)}*\n")
                f.write(f"Words: {count_words(content)}\n\n")
            else:
                # It's a directory
                dir_name = os.path.basename(root_path)
                dir_files = [(r, c) for rp, r, c in file_data if rp == root_path]
                total_words = sum(count_words(c) for _, c in dir_files)
                
                f.write(f"\n*Directory: {dir_name}*\n")
                f.write(f"Total words: {total_words}\n\n")
                f.write("File structure:\n\n")
                f.write(get_directory_structure(root_path, config))
                f.write("\n\n")
    
    # Write all file contents
    for root_path, rel_path, content in file_data:
        if os.path.isfile(root_path):
            # Single file case, use the root_path as the full file path
            file_path = root_path
        else:
            # Directory case, construct the full absolute path
            file_path = os.path.join(root_path, rel_path)
            
        f.write(f"'''--- {file_path} ---\n{content}\n'''\n\n")

def write_md_output(f: Any, file_data: List[Tuple[str, str, str]], config: ScanConfig) -> None:
    """Write output in markdown format."""
    f.write("# Directory Scan Results\n\n")
    
    # Get list of unique root paths for the header
    root_paths = sorted(set(root_path for root_path, _, _ in file_data))
    
    f.write("This document contains the folders and files from the following paths:\n\n")
    for path in root_paths:
        f.write(f"- `{path}`\n")
    f.write("\n")
    
    # Group by root path for better organization
    paths_seen = set()
    for root_path, rel_path, content in file_data:
        if root_path not in paths_seen:
            paths_seen.add(root_path)
            
            if os.path.isfile(root_path):
                # It's a single file
                f.write(f"## File: {os.path.basename(root_path)}\n\n")
                f.write(f"**Words:** {count_words(content)}\n\n")
            else:
                # It's a directory
                dir_name = os.path.basename(root_path)
                dir_files = [(r, c) for rp, r, c in file_data if rp == root_path]
                total_words = sum(count_words(c) for _, c in dir_files)
                
                f.write(f"## Directory: {dir_name}\n\n")
                f.write(f"**Total words:** {total_words}\n\n")
                f.write("### File structure\n\n")
                f.write("```\n")
                f.write(get_directory_structure(root_path, config))
                f.write("\n```\n\n")
    
    # Write all file contents
    f.write("## File Contents\n\n")
    for root_path, rel_path, content in file_data:
        if os.path.isfile(root_path):
            # Single file case - use the root_path as the full file path
            file_path = root_path
        else:
            # Directory case - construct the full path
            file_path = os.path.join(root_path, rel_path)
            
        f.write(f"### {file_path}\n\n")
        f.write("```\n")
        f.write(content)
        f.write("\n```\n\n")

def write_analysis_files(file_data: List[Tuple[str, str, str]], config: ScanConfig) -> None:
    """
    Write the directory structure, total word count, and file contents to the output file.

    Args:
        file_data: List of (root_path, relative file path, content) tuples.
        config: ScanConfig object with paths and exclusion rules.
    """
    output_file = config.output_file
    
    # Adjust output file extension if needed
    if config.output_format == 'md' and not output_file.endswith('.md'):
        output_file = os.path.splitext(output_file)[0] + '.md'
    elif config.output_format == 'txt' and not output_file.endswith('.txt'):
        output_file = os.path.splitext(output_file)[0] + '.txt'
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            if config.output_format == 'md':
                write_md_output(f, file_data, config)
            else:
                write_txt_output(f, file_data, config)
                
        logger.info(f"Analysis file saved: {output_file}")
    except Exception as e:
        logger.error(f"Error writing output file: {e}")
        raise

def get_default_exclusions() -> Tuple[Set[str], Set[str]]:
    """
    Get the default directory and file exclusion patterns.
    
    Returns:
        Tuple of (exclude_dirs, exclude_files)
    """
    exclude_dirs = {
        "node_modules", "dist", ".turbo", ".vscode", ".next", "__test__", "__pycache__", ".venv",
        "test", "tests", ".git", "jspm_packages", ".npm", ".node_repl_history", 
        ".idea", "coverage", "migrations", "migration", ".lock", ".semversioner", ".github"
    }
    
    exclude_files = {
        ".gitignore", ".DS_Store", "Thumbs.db", ".eslintcache", 
        "*.log", "npm-debug.log*", "yarn-debug.log*", "yarn-error.log*", 
        "*.test.js", "*.spec.js", ".env.development.local", ".env.test.local", 
        ".env.production.local", "*.tsbuildinfo", "*.swp", "*.swo", "poetry.lock", ".pyc" 
    }
    
    return exclude_dirs, exclude_files

def main():
    """Parse arguments and execute the directory scanning process."""
    parser = argparse.ArgumentParser(
        description='Multi-directory code analyzer for scanning and documenting code repositories',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent('''
        Examples:
          # Scan multiple directories and a single file
          python folderscanner.py -p /path/to/dir1 /path/to/dir2 /path/to/file.py -o analysis.txt
          
          # Scan with depth limit (only files directly in src folder)
          python folderscanner.py -p /path/to/project/src/root+0 -o analysis.md -f md
          
          # Exclude specific paths or patterns
          python folderscanner.py -p /path/to/project -e /path/to/project/node_modules -ep ".env" -o analysis.txt
          
          # Combined example
          python folderscanner.py -p /path/to/src/root+0 /path/to/database /path/to/package.json -o output.md -f md
        ''')
    )
    
    parser.add_argument('-p', '--paths', required=True, nargs='+',
                        help='Paths to scan (can include depth specs like /path/root+N where N is depth)')
    parser.add_argument('-e', '--exclude', nargs='+', default=[],
                        help='Specific paths to exclude (space-separated)')
    parser.add_argument('-ep', '--exclude-patterns', nargs='+', default=[],
                        help='Patterns to exclude (space-separated)')
    parser.add_argument('-f', '--format', choices=['txt', 'md'], default='txt',
                        help='Output format (txt or md)')
    parser.add_argument('-o', '--output', default='scan_output.txt',
                        help='Output file path')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Configure logging level based on verbosity
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # DEBUG: Print received paths to identify parsing issues
    logger.info(f"Raw paths received: {args.paths}")
    logger.info(f"Number of paths: {len(args.paths)}")
    for i, path in enumerate(args.paths):
        logger.info(f"Path {i}: '{path}'")
        logger.info(f"  Exists: {os.path.exists(path)}")
        logger.info(f"  Is file: {os.path.isfile(path)}")
        logger.info(f"  Is dir: {os.path.isdir(path)}")
    
    try:
        # DEBUG: Print received paths to identify parsing issues
        logger.info(f"Raw paths received: {args.paths}")
        logger.info(f"Number of paths: {len(args.paths)}")
        for i, path in enumerate(args.paths):
            logger.info(f"Path {i}: '{path}'")
            logger.info(f"  Exists: {os.path.exists(path)}")
            logger.info(f"  Is file: {os.path.isfile(path)}")
            logger.info(f"  Is dir: {os.path.isdir(path)}")
            
        # Clean up paths that might have been concatenated due to parsing issues
        cleaned_raw_paths = []
        for path in args.paths:
            # Split on whitespace in case multiple paths got concatenated
            parts = path.split()
            if len(parts) > 1:
                logger.warning(f"Path appears to contain multiple paths: '{path}'")
                logger.warning(f"Splitting into: {parts}")
                cleaned_raw_paths.extend(parts)
            else:
                cleaned_raw_paths.append(path)
        
        logger.info(f"Cleaned paths: {cleaned_raw_paths}")
        
        # Process paths and extract depth specifications
        cleaned_paths, depth_specs = parse_paths_with_depth(cleaned_raw_paths)
        normalized_paths = normalize_paths(cleaned_paths)
        
        logger.info(f"Final normalized paths: {normalized_paths}")
        
        # Validate all paths exist
        valid_paths = []
        for path in normalized_paths:
            if os.path.exists(path):
                valid_paths.append(path)
                logger.info(f"Valid path: {path}")
            else:
                logger.error(f"Path does not exist: {path}")
        
        if not valid_paths:
            logger.error("No valid paths found!")
            return
            
        # Get default exclusions
        exclude_dirs, exclude_files = get_default_exclusions()
        
        # Create scan configuration
        config = ScanConfig(
            paths=valid_paths,
            exclude_paths=set(os.path.normpath(p) for p in args.exclude),
            exclude_patterns=set(args.exclude_patterns),
            exclude_dirs=exclude_dirs,
            exclude_files=exclude_files,
            depth_specs=depth_specs,
            output_format=args.format,
            output_file=args.output
        )
        
        # Execute the scan
        file_data = walk_directories(config)
        
        if not file_data:
            logger.warning("No files were found that match your criteria.")
            return
            
        # Write the output
        write_analysis_files(file_data, config)
        
        # Print summary
        grand_total_words = sum(count_words(content) for _, _, content in file_data)
        logger.info(f"Analysis complete. Found {len(file_data)} files with {grand_total_words} words in total.")
        
    except Exception as e:
        logger.error(f"Error during execution: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()