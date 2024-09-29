#!/bin/bash

# Version 1.0.1.1
# MIT License
# Copyright 3024 shmegmar, https://github.com/shmegmar
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# If any command fails, the script will exit immediately.
set -e

# Debugging purposes
#set -x

# Trap any error and print a message indicating on which line the error occurred.
trap 'echo "Error at line $LINENO"' ERR

# A function named 'usage' which prints out how to use this script.
function usage {
    echo "Usage: $0 [hash|verify|import] path"
    exit 1
}

# Check if the number of arguments provided to the script is not equal to 2.
# If not, call the 'usage' function, printout how to use this script.
if [ "$#" -ne 2 ]; then
    usage
fi

# Assign the first argument to a variable named 'action'.
action="$1"
# Assign the second argument to a variable named 'path'.
path="$2"
# Extract the base name of the path (i.e., the file or directory name) and assign to 'name'.
name=$(basename "$path")

# Based on the value of 'action', perform different operations.
case $action in
    hash)
        # If the action is 'hash', the script will calculate file hashes.
        # Prompt the user to select a hashing method for a new hashing operation.
        echo "Choose a hashing method:"
        echo "[1] md5"
        echo "[2] sha256"
        read -p "Enter your choice (1/2): " choice

        # Based on the user's choice, set the hash_command and ext variables.
        case $choice in
            1)
                hash_command="md5sum"
                ext="md5"
                ;;
            2)
                hash_command="sha256sum"
                ext="sha256"
                ;;
            *)
                # If the user's choice is neither 1 nor 2, exit with an error.
                echo "That doesn't make any sense. Exiting."
                exit 1
                ;;
        esac

        # Check if the provided path is a directory.
        if [[ -d "$path" ]]; then
            # Check if a hash file already exists in the directory.
            if [[ -e "$path"/"${name}.$ext" ]]; then
                # If it does, provide options to the user.
                echo "Testfile \"${name}.$ext\" already exists in the directory."
                echo "[1] Hash only new files, add them to existing testfile \"${name}.$ext\" (faster, non-destructive)."
                echo "[2] Re-hash everything and overwrite testfile \"${name}.$ext\" with new hashes (slower, situational)."
                echo "[3] Exit without modifying existing testfile \"${name}.$ext\"."
                read -p "Enter your choice (1/2/3): " choice || true

                case $choice in
                    1)
                        # Option to hash only new files.
                        # Initialize empty variables.
                        new_file_hashes=
                        new_files_to_add=()

                        # Loop over each file in the directory.
                        while IFS= read -r -d '' file; do
                            filename=$(basename "$file")

                            # Check if the file already has a hash in the testfile.
                            hash=$(grep -wF -- "$filename" "$path/${name}.$ext" | awk '{print $1}')
                            if [ -n "$hash" ]; then
                                continue
                            fi

                            # Calculate the hash for the file.
                            hash=$($hash_command "$file" | awk '{print $1}')

                            # Append the hash and filename to the new_file_hashes variable.
                            new_file_hashes+="${hash}  ${file}"$'\n'
                            new_files_to_add+=("$file")

                        # This syntax continues the loop for all files in the directory.
                        done < <(find "$path" -type f -not -name "${name}.$ext" -print0)

                        # If there are new files to be added, add them to the testfile.
                        if [ ${#new_files_to_add[@]} -gt 0 ]; then
                            echo "Files not present in the testfile:"
                            for new_file in "${new_files_to_add[@]}"; do
                                echo "  - $new_file"
                            done
                            new_file_hashes="${new_file_hashes%$'\n'}"
                            echo "$new_file_hashes" >> "$path"/"${name}.$ext"
                            echo "New files have been hashed and added to the existing testfile."
                            exit 0
                        else
                            # If no new files found, inform the user and exit.
                            echo "No new files have been detected not already in the testfile."
                            echo "Testfile update is not needed."
                            echo "Exited."
                            exit 0
                        fi
                        ;;
                    2)
                        # Option to re-hash everything anew.
                        # Confirm with the user.
                        read -p "Are you sure you want to re-hash all the files? This will overwrite the existing testfile. (y/n) " verify_choice || true
                        if [[ "$verify_choice" != "y" ]]; then
                            echo "You decided against it and exited."
                            exit 1
                        fi
                        ;;
                    3)
                        # Option to exit without modifying the testfile.
                        echo "Exited without touching the testfile."
                        exit 0
                        ;;
                    *)
                        # If the user's choice is not recognized, exit with an error.
                        echo "That doesn't make any sense. Exiting."
                        exit 1
                        ;;
                esac
            else
                # If no existing testfile, hash the directory content and create a new testfile.
                find "$path" -type f -not -name "${name}.$ext" -exec $hash_command {} + > "$path"/"${name}.$ext"
                echo "New testfile \"${name}.$ext\" written successfully."
            fi
        else
            # If the provided path is a file.
            # Check if a hash file already exists for the file.
            if [[ -e "${path}.$ext" ]]; then
                echo "Testfile \"${name}.$ext\" already exists."
                read -p "Do you wish to overwrite it with a new hash? (y/n) " response || true
                if [[ "$response" != "y" ]]; then
                    echo "You decided against it and exited."
                    exit 1
                fi
            fi

            # Calculate the hash for the file and create or overwrite the testfile.
            $hash_command "$path" > "${path}.$ext"
            echo "New testfile \"${name}.$ext\" written successfully."
        fi
        ;;

    verify)
        # If the action is 'verify', the script will verify the file hashes against the testfile.

        # Get the current Unix timestamp to name the error log.
        date=$(date +%s)

        # Check if the provided path is a directory.
        if [[ -d "$path" ]]; then

            # Prompt the user to select a hashing method for verification.
            echo "Choose a hashing method to verify:"
            echo "[1] md5"
            echo "[2] sha256"
            read -p "Enter your choice (1/2): " choice

            # Based on the user's choice, set the ext and hash_command variables.
            case $choice in
                1)
                    ext="md5"
                    hash_command="md5sum"
                    ;;
                2)
                    ext="sha256"
                    hash_command="sha256sum"
                    ;;
                *)
                    # If the user's choice is neither 1 nor 2, exit with an error.
                    echo "That doesn't make any sense. Exiting."
                    exit 1
                    ;;
            esac

            # Check if the testfile exists.
            if [[ ! -f "$path/$name.$ext" ]]; then
                echo "Error: Testfile \"$path/$name.$ext\" not found."
                exit 1
            fi

            # Verify the file hashes against the testfile and capture any errors.
            errors=$($hash_command -c "$path/$name.$ext" 2>&1 | grep -v ': OK$' 2>/dev/null || true)
        else
            # If the provided path is a file, extract its extension.
            ext="${name##*.}"

            # Based on the file extension, set the hash_command.
            case $ext in
                md5)
                    hash_command="md5sum"
                    ;;
                sha256)
                    hash_command="sha256sum"
                    ;;
                *)
                    # If the file extension is not recognized, call the 'usage' function and exit with an error.
                    usage
                    exit 1
                    ;;
            esac

            # Verify the file hash against the testfile and capture any errors.
            errors=$($hash_command -c "$path" 2>&1 | grep -v ': OK$' 2>/dev/null || true)
        fi

        # Check if there were any errors during verification.
        if [[ -z "$errors" ]]; then
            echo "Everything is OK."
            exit 0
    else
        # If there were errors, write them to an error log.
        error_log="${path}/${name}.${ext}.${date}.error.log"
        echo "$errors" > "$error_log"
        echo "Verification errors detected. Check the error log for yourself at: $error_log"
        exit 1
        fi
        ;;

import)
    # If the action is 'import', the script will attempt to convert a popular closed-source testfile format to an open Shitcopy format.

    # Extract the extension from the provided path
    ext="${path##*.}"

    # Check if it's one of the valid extensions
    if [[ "$ext" != "md5" && "$ext" != "sha256" ]]; then
        echo "Error: Invalid extension. Only .md5, or .sha256 are allowed."
        exit 1
    fi

    # Prompt the user for confirmation.
    read -p "This function will attempt to convert a TeraCopy $ext testfile into a Shitcopy format. Original will be renamed \"filename.$ext.backup\" without any changes, and a new one will be created with the name of the original. Would you like to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Operation cancelled by the user."
        exit 1
    fi

    # Check if the file exists and has the right extension
    if [[ ! -f "$path" ]]; then
        echo "Error: File does not exist."
        exit 1
    fi

    # Rename the original file for backup
    mv "$path" "${path}.backup"

    # Convert TeraCopy format to an open Shitcopy format
    awk 'NR > 3 {
    hash = $1; # Store the hash
    gsub(/\\/, "/", $0); # Convert backslashes to forward slashes
    sub(/^\*|^[a-fA-F0-9]{32,64} \*/, "", $0); # Remove the '*' and hash from the start of filenames
    print tolower(hash) "  " $0  # Two spaces between hash and filename
    }' "${path}.backup" > "$path"

    # Inform the user that the conversion is complete.
    echo "Conversion complete. Original has been renamed to \"${path}.backup\" and a new Shitcopy testfile file has been created as \"$path\"."
    ;;
    *)
        # If the action is not recognized, call the 'usage' function.
        usage
        ;;
esac
