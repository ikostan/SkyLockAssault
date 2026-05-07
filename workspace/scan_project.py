import os


def generate_tree(startpath, exclude_dirs=None):
    if exclude_dirs is None:
        exclude_dirs = {".git", ".godot", "__pycache__", "node_modules", ".github"}

    output = []
    for root, dirs, files in os.walk(startpath):
        # Filter out excluded directories
        dirs[:] = [d for d in dirs if d not in exclude_dirs]

        level = root.replace(startpath, "").count(os.sep)
        indent = " " * 4 * (level)
        output.append(f"{indent}{os.path.basename(root)}/")

        sub_indent = " " * 4 * (level + 1)
        for f in files:
            # You can add file extensions to exclude here if needed
            output.append(f"{sub_indent}{f}")

    return "\n".join(output)


if __name__ == "__main__":
    # Get the current directory where the script is run
    project_root = os.getcwd()
    tree_structure = generate_tree(project_root)

    # Save to a file for easy copying/uploading
    with open("project_structure.txt", "w", encoding="utf-8") as f:
        f.write(tree_structure)

    print("Scan complete! Results saved to project_structure.txt")
