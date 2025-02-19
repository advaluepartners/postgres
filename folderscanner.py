#!/usr/bin/env python3

import os
import argparse
from typing import List, Tuple, Set
from dataclasses import dataclass

@dataclass
class ScanConfig:
    paths: List[str]
    exclude_paths: Set[str]
    exclude_patterns: Set[str]

def is_excluded(path: str, config: ScanConfig) -> bool:
    rel_path = os.path.normpath(path)
    return any(
        rel_path.startswith(excl) for excl in config.exclude_paths
    ) or any(
        pattern in rel_path for pattern in config.exclude_patterns
    )

def get_file_contents(file_path: str) -> str:
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            return file.read()
    except Exception as e:
        return f"Error reading file: {e}"

def walk_directories(config: ScanConfig) -> List[Tuple[str, str]]:
    file_data = []
    
    for root_path in config.paths:
        abs_path = os.path.abspath(root_path)
        print(f"Scanning: {abs_path}")
        
        for subdir, dirs, files in os.walk(abs_path):
            rel_subdir = os.path.relpath(subdir, abs_path)
            
            if is_excluded(rel_subdir, config):
                dirs[:] = []
                continue
                
            dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_subdir, d), config)]
            
            for file in files:
                file_path = os.path.join(subdir, file)
                rel_path = os.path.relpath(file_path, abs_path)
                
                if not is_excluded(rel_path, config):
                    print(f"Reading: {rel_path}")
                    content = get_file_contents(file_path)
                    
                    # Extract the path starting from /capital-a/
                    capital_a_index = file_path.find("/postgres/")
                    if capital_a_index != -1:
                        repo_relative_path = file_path[capital_a_index:]
                        file_data.append((repo_relative_path, content))
                    else:
                        print(f"Warning: Path {file_path} does not contain '/postgres/'. Skipping.")
    
    return file_data

def get_directory_structure(root_path: str, config: ScanConfig) -> str:
    structure = ""
    for root, dirs, files in os.walk(root_path):
        rel_path = os.path.relpath(root, root_path)
        
        if is_excluded(rel_path, config):
            dirs[:] = []
            continue
            
        dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_path, d), config)]
        
        level = rel_path.count(os.sep)
        indent = ' ' * 4 * level
        structure += f"{indent}{os.path.basename(root)}/\n"
        
        sub_indent = ' ' * 4 * (level + 1)
        for file in files:
            if not is_excluded(os.path.join(rel_path, file), config):
                structure += f"{sub_indent}{file}\n"
    return structure

def write_analysis_files(file_data: List[Tuple[str, str]], config: ScanConfig, output_file: str):
    with open(output_file, 'w', encoding='utf-8') as f:
        header_text = (
             "Here is the txt file that represents the folders and files in my github hub repo to build an ec2 and build and run a postrgesSQL db. The set id done by using github actions with nix, ansible and docker "
            "Each file in this repo separated by the sequence '''--- , followed "
            "by the file path, ending with ---. Each file's content begins immediately after "
            "its file path and extends until the next sequence of '''---\n\n"
        )
        
        f.write(header_text)
        
        # Write folder structure for each root path
        for root_path in config.paths:
            abs_path = os.path.abspath(root_path)
            capital_a_index = abs_path.find("/postgres")
            if capital_a_index != -1:
                repo_relative_path = abs_path[capital_a_index:]
                f.write(f"*Folder: {repo_relative_path}*\n")
                f.write(get_directory_structure(abs_path, config))
                f.write("\n")
            else:
                print(f"Warning: Path {abs_path} does not contain '/postgres/'. Skipping folder structure.")
        
        # Write file contents
        f.write("\nFile contents:\n\n")
        for file_path, content in file_data:
            f.write(f"'''--- {file_path} ---\n{content}\n'''\n")
        
        print(f"Analysis file saved: {output_file}")

def main():
    parser = argparse.ArgumentParser(description='Multi-directory code analyzer')
    parser.add_argument('-p', '--paths', required=True, nargs='+', 
                      help='Paths to scan (space-separated)')
    parser.add_argument('-e', '--exclude', nargs='+', default=[],
                      help='Paths to exclude (space-separated)')
    parser.add_argument('-ep', '--exclude-patterns', nargs='+', default=['node_modules'],
                      help='Patterns to exclude (default: node_modules)')
    parser.add_argument('-o', '--output', default='combined_analysis.txt',
                      help='Output file path')
    
    args = parser.parse_args()
    
    config = ScanConfig(
        paths=args.paths,
        exclude_paths=set(os.path.normpath(p) for p in args.exclude),
        exclude_patterns=set(args.exclude_patterns)
    )
    
    file_data = walk_directories(config)
    write_analysis_files(file_data, config, args.output)
    print(f"Analysis complete. Found {len(file_data)} files")

if __name__ == "__main__":
    main()


# #!/usr/bin/env python3

# # READ ME 
# # # Scan multiple directories
# # python script.py -p ./project1 ./project2 ./project3

# # # Exclude specific paths and patterns
# # python script.py -p ./project1 ./project2 \
# #     -e components/layouts/BrainLayout test/fixtures \
# #     -ep node_modules .git cache \
# #     -o custom_output.txt

# #!/usr/bin/env python3

# import os
# import argparse
# from typing import List, Tuple, Set
# from dataclasses import dataclass

# @dataclass
# class ScanConfig:
#     paths: List[str]
#     exclude_paths: Set[str]
#     exclude_patterns: Set[str]

# def is_excluded(path: str, config: ScanConfig) -> bool:
#     rel_path = os.path.normpath(path)
#     return any(
#         rel_path.startswith(excl) for excl in config.exclude_paths
#     ) or any(
#         pattern in rel_path for pattern in config.exclude_patterns
#     )

# def get_file_contents(file_path: str) -> str:
#     try:
#         with open(file_path, 'r', encoding='utf-8') as file:
#             return file.read()
#     except Exception as e:
#         return f"Error reading file: {e}"

# def walk_directories(config: ScanConfig) -> List[Tuple[str, str]]:
#     file_data = []
    
#     for root_path in config.paths:
#         abs_path = os.path.abspath(root_path)
#         print(f"Scanning: {abs_path}")
        
#         for subdir, dirs, files in os.walk(abs_path):
#             rel_subdir = os.path.relpath(subdir, abs_path)
            
#             if is_excluded(rel_subdir, config):
#                 dirs[:] = []
#                 continue
                
#             dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_subdir, d), config)]
            
#             for file in files:
#                 file_path = os.path.join(subdir, file)
#                 rel_path = os.path.relpath(file_path, abs_path)
                
#                 if not is_excluded(rel_path, config):
#                     print(f"Reading: {rel_path}")
#                     content = get_file_contents(file_path)
#                     file_data.append((os.path.join(os.path.basename(root_path), rel_path), content))
    
#     return file_data

# def get_directory_structure(root_path: str, config: ScanConfig) -> str:
#     structure = ""
#     for root, dirs, files in os.walk(root_path):
#         rel_path = os.path.relpath(root, root_path)
        
#         if is_excluded(rel_path, config):
#             dirs[:] = []
#             continue
            
#         dirs[:] = [d for d in dirs if not is_excluded(os.path.join(rel_path, d), config)]
        
#         level = rel_path.count(os.sep)
#         indent = ' ' * 4 * level
#         structure += f"{indent}{os.path.basename(root)}/\n"
        
#         sub_indent = ' ' * 4 * (level + 1)
#         for file in files:
#             if not is_excluded(os.path.join(rel_path, file), config):
#                 structure += f"{sub_indent}{file}\n"
#     return structure

# def write_analysis_files(file_data: List[Tuple[str, str]], config: ScanConfig, output_file: str):
#     with open(output_file, 'w', encoding='utf-8') as f:
#         header_text = (
#             "Here is the txt file that represents the folders and files in my github hub repo to build an ec2 and build and run a postrgesSQL db. The set id done by using github actions with nix, ansible and docker "
#             "Each file in this repo separated by the sequence '''--- , followed "
#             "by the file path, ending with ---. Each file's content begins immediately after "
#             "its file path and extends until the next sequence of '''---\n\n"
#         )
        
#         f.write(header_text)
        
#         for root_path in config.paths:
#             repo_name = os.path.basename(root_path)
#             f.write(f"\n*Folder {repo_name}*\n")
#             f.write("\nFile structure:\n\n")
#             f.write(get_directory_structure(root_path, config))
            
#             path_data = [(p, c) for p, c in file_data 
#                         if p.startswith(os.path.basename(root_path))]
            
#             for file_path, content in path_data:
#                 f.write(f"'''--- {file_path} ---\n{content}\n'''")
        
#         print(f"Analysis file saved: {output_file}")

# def main():
#     parser = argparse.ArgumentParser(description='Multi-directory code analyzer')
#     parser.add_argument('-p', '--paths', required=True, nargs='+', 
#                       help='Paths to scan (space-separated)')
#     parser.add_argument('-e', '--exclude', nargs='+', default=[],
#                       help='Paths to exclude (space-separated)')
#     parser.add_argument('-ep', '--exclude-patterns', nargs='+', default=['node_modules'],
#                       help='Patterns to exclude (default: node_modules)')
#     parser.add_argument('-o', '--output', default='combined_analysis.txt',
#                       help='Output file path')
    
#     args = parser.parse_args()
    
#     config = ScanConfig(
#         paths=args.paths,
#         exclude_paths=set(os.path.normpath(p) for p in args.exclude),
#         exclude_patterns=set(args.exclude_patterns)
#     )
    
#     file_data = walk_directories(config)
#     write_analysis_files(file_data, config, args.output)
#     print(f"Analysis complete. Found {len(file_data)} files")

# if __name__ == "__main__":
#     main()