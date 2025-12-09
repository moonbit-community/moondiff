#!/usr/bin/env bash

# moondiff helper script
# use your favorite editor save this script to your git pre-commit hook (default is .git/hooks/pre-commit)
# e.g: code .git/hooks/pre-commit
# then set executable permission for pre-commit hook script
# e.g: chmod +x .git/hooks/pre-commit

moon fmt -- -add-uuid

# Get the list of all modified files in the staging area for this commit, then add them all
# --cached: Only view the staging area (staged)
# --name-only: Only output the file name
# -z: Use null character as a separator to correctly handle file names containing spaces
git diff --cached --name-only -z | xargs -0 git add