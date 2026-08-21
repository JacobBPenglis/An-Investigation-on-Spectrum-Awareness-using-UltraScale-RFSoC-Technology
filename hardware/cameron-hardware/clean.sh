#!/usr/bin/env bash
#!/usr/bin/env bash

# Always operate from the repository root
cd "$(dirname "$0")" || exit 1

echo "=========================================="
echo "Vivado Repository Clean"
echo "=========================================="
echo
echo "The following ignored files/directories will be removed:"
echo

# Preview what will be deleted
git clean -Xdfn

echo
read -r -p "Delete all ignored files above? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo "Clean cancelled."
    exit 0
fi

echo
echo "Cleaning ignored files..."
git clean -Xdf

if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Git clean failed."
    exit 1
fi

echo
echo "=========================================="
echo "Clean completed successfully."
echo "=========================================="