#!/usr/bin/env python3  v2

import os
import argparse
from typing import List, Set
from dataclasses import dataclass

@dataclass
class ScanConfig:
    paths: List[str]
    exclude_paths: Set[str]
    exclude_patterns: Set[str]

def is_excluded(path: str, config: ScanConfig) -> bool:
    """Check if a path should be excluded based on config rules."""
    rel_path = os.path.normpath(path)
    return any(
        rel_path.startswith(excl) for excl in config.exclude_paths
    ) or any(
        pattern in rel_path for pattern in config.exclude_patterns
    )

def count_total_words(config: ScanConfig) -> int:
    """Count the total number of words (tokens) in all files across the specified paths."""
    total_words = 0
    for path in config.paths:
        abs_path = os.path.abspath(path)
        if os.path.isfile(abs_path):
            rel_path = os.path.basename(abs_path)
            if not is_excluded(rel_path, config):
                try:
                    with open(abs_path, 'r', encoding='utf-8') as file:
                        content = file.read()
                        total_words += len(content.split())
                except Exception as e:
                    print(f"Error reading file {abs_path}: {e}")
        elif os.path.isdir(abs_path):
            for subdir, dirs, files in os.walk(abs_path):
                rel_subdir = os.path.relpath(subdir, abs_path)
                if is_excluded(rel_subdir, config):
                    dirs[:] = []
                    continue
                dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_subdir, d), config)]
                for file in files:
                    rel_path = os.path.join(rel_subdir, file)
                    if not is_excluded(rel_path, config):
                        file_path = os.path.join(subdir, file)
                        try:
                            with open(file_path, 'r', encoding='utf-8') as file:
                                content = file.read()
                                total_words += len(content.split())
                        except Exception as e:
                            print(f"Error reading file {file_path}: {e}")
        else:
            print(f"Warning: Path {abs_path} is not a file or directory. Skipping.")
    return total_words

def get_limited_directory_structure(root_path: str, config: ScanConfig, max_level: int) -> str:
    """
    Generate a string representing the directory structure up to a specified depth.

    Args:
        root_path: The root directory to scan.
        config: ScanConfig object with exclusion rules.
        max_level: The maximum depth level to include in the structure (root is level 1).

    Returns:
        str: A string representation of the directory structure up to the specified depth.
    """
    structure = ""
    for root, dirs, files in os.walk(root_path):
        rel_path = os.path.relpath(root, root_path)
        level = 1 if rel_path == '.' else len(rel_path.split(os.sep)) + 1
        if is_excluded(rel_path, config):
            dirs[:] = []
            continue
        if level == max_level:
            dirs[:] = []  # Prevent traversal beyond max_level, but include this level
        dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_path, d), config)]
        indent = ' ' * 4 * (level - 1)
        structure += f"{indent}{os.path.basename(root)}/\n"
        sub_indent = ' ' * 4 * level
        for file in files:
            if not is_excluded(os.path.join(rel_path, file), config):
                structure += f"{sub_indent}{file}\n"
    return structure

def parse_depth(depth_str: str) -> int:
    """
    Parse the depth string in the format 'root+N' and return the maximum level.

    Args:
        depth_str: The depth string, e.g., 'root+2'.

    Returns:
        int: The maximum level to include (root level is 1, so max_level = 1 + N).

    Raises:
        ValueError: If the depth string is not in the correct format or N is invalid.
    """
    if not depth_str.startswith("root+"):
        raise ValueError("Depth must be in the format 'root+N' where N is an integer.")
    try:
        N = int(depth_str[5:])
        if N < 0:
            raise ValueError("N must be a non-negative integer.")
        return 1 + N
    except ValueError as e:
        raise ValueError(f"Invalid depth format: {e}")

def main():
    parser = argparse.ArgumentParser(description='File scanner for repository analysis')
    parser.add_argument('-p', '--paths', required=True, nargs='+',
                        help='Paths to scan (directories or files, space-separated)')
    parser.add_argument('-e', '--exclude', nargs='+', default=[],
                        help='Relative paths to exclude (space-separated)')
    parser.add_argument('-ep', '--exclude-patterns', nargs='+', default=['node_modules', '.git'],
                        help='Patterns to exclude (default: node_modules, .git)')
    parser.add_argument('-d', '--depth', default='root+4',
                        help='Depth of the directory tree to scan, e.g., "root+2" (default: root+4)')
    parser.add_argument('-o', '--output', default=None, 
                        help='Output file to write the results (if not specified, prints to console)')
    args = parser.parse_args()

    config = ScanConfig(
        paths=args.paths,
        exclude_paths=set(os.path.normpath(p) for p in args.exclude),
        exclude_patterns=set(args.exclude_patterns)
    )

    # Parse the depth from the command-line argument
    try:
        max_level = parse_depth(args.depth)
    except ValueError as e:
        print(f"Error: {e}")
        return

    # Calculate total word count across all paths
    total_words = count_total_words(config)
    output_content = f"Total tokens in the repo: {total_words}\n"

    # Generate directory structure for each directory path up to the specified depth
    for path in config.paths:
        abs_path = os.path.abspath(path)
        if os.path.isdir(abs_path):
            structure = get_limited_directory_structure(abs_path, config, max_level=max_level)
            output_content += f"\nStructure tree for {abs_path} (up to depth {args.depth}):\n{structure}"

    # Write output to file or print to console
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output_content)
        print(f"Results written to {args.output}")
    else:
        print(output_content)

if __name__ == "__main__":
    main()


# #!/usr/bin/env python3

# import os
# import argparse
# from typing import List, Set
# from dataclasses import dataclass

# @dataclass
# class ScanConfig:
#     paths: List[str]
#     exclude_paths: Set[str]
#     exclude_patterns: Set[str]

# def is_excluded(path: str, config: ScanConfig) -> bool:
#     """Check if a path should be excluded based on config rules."""
#     rel_path = os.path.normpath(path)
#     return any(
#         rel_path.startswith(excl) for excl in config.exclude_paths
#     ) or any(
#         pattern in rel_path for pattern in config.exclude_patterns
#     )

# def count_total_words(config: ScanConfig) -> int:
#     """Count the total number of words (tokens) in all files across the specified paths."""
#     total_words = 0
#     for path in config.paths:
#         abs_path = os.path.abspath(path)
#         if os.path.isfile(abs_path):
#             rel_path = os.path.basename(abs_path)
#             if not is_excluded(rel_path, config):
#                 try:
#                     with open(abs_path, 'r', encoding='utf-8') as file:
#                         content = file.read()
#                         total_words += len(content.split())
#                 except Exception as e:
#                     print(f"Error reading file {abs_path}: {e}")
#         elif os.path.isdir(abs_path):
#             for subdir, dirs, files in os.walk(abs_path):
#                 rel_subdir = os.path.relpath(subdir, abs_path)
#                 if is_excluded(rel_subdir, config):
#                     dirs[:] = []
#                     continue
#                 dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_subdir, d), config)]
#                 for file in files:
#                     rel_path = os.path.join(rel_subdir, file)
#                     if not is_excluded(rel_path, config):
#                         file_path = os.path.join(subdir, file)
#                         try:
#                             with open(file_path, 'r', encoding='utf-8') as file:
#                                 content = file.read()
#                                 total_words += len(content.split())
#                         except Exception as e:
#                             print(f"Error reading file {file_path}: {e}")
#         else:
#             print(f"Warning: Path {abs_path} is not a file or directory. Skipping.")
#     return total_words

# def get_limited_directory_structure(root_path: str, config: ScanConfig, max_level: int = 5) -> str:
#     """Generate a string representing the directory structure up to a specified depth."""
#     structure = ""
#     for root, dirs, files in os.walk(root_path):
#         rel_path = os.path.relpath(root, root_path)
#         level = 1 if rel_path == '.' else len(rel_path.split(os.sep)) + 1
#         if is_excluded(rel_path, config):
#             dirs[:] = []
#             continue
#         if level == max_level:
#             dirs[:] = []  # Prevent traversal beyond max_level
#         dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_path, d), config)]
#         indent = ' ' * 4 * (level - 1)
#         structure += f"{indent}{os.path.basename(root)}/\n"
#         sub_indent = ' ' * 4 * level
#         for file in files:
#             if not is_excluded(os.path.join(rel_path, file), config):
#                 structure += f"{sub_indent}{file}\n"
#     return structure

# def main():
#     parser = argparse.ArgumentParser(description='File scanner for repository analysis')
#     parser.add_argument('-p', '--paths', required=True, nargs='+',
#                         help='Paths to scan (directories or files, space-separated)')
#     parser.add_argument('-e', '--exclude', nargs='+', default=[],
#                         help='Relative paths to exclude (space-separated)')
#     parser.add_argument('-ep', '--exclude-patterns', nargs='+', default=['node_modules'],
#                         help='Patterns to exclude (default: node_modules)')
#     parser.add_argument('-o', '--output', default=None, help='Output file to write the results')
#     args = parser.parse_args()

#     config = ScanConfig(
#         paths=args.paths,
#         exclude_paths=set(os.path.normpath(p) for p in args.exclude),
#         exclude_patterns=set(args.exclude_patterns)
#     )

#     total_words = count_total_words(config)
#     output_content = f"Total tokens in the repo: {total_words}\n"
#     for path in config.paths:
#         abs_path = os.path.abspath(path)
#         if os.path.isdir(abs_path):
#             structure = get_limited_directory_structure(abs_path, config, max_level=5)
#             output_content += f"\nStructure tree for {abs_path}:\n{structure}"

#     if args.output:
#         with open(args.output, 'w') as f:
#             f.write(output_content)
#     else:
#         print(output_content)

# if __name__ == "__main__":
#     main()