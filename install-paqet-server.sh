#!/bin/bash

# Script to install the PAQET server

# Define variables
PACKAGE_NAME="paqet-package.tar.gz"
EXTRACT_DIR="paqet-example-files"

# Download or copy the tar.gz package to the current directory if not already present
if [ ! -f "$PACKAGE_NAME" ]; then
    echo "Package $PACKAGE_NAME not found! Please place it in the current directory."
    exit 1
fi

# Create a directory for extracted files
mkdir -p "$EXTRACT_DIR"

# Extract the tar.gz package
echo "Extracting $PACKAGE_NAME..."
tar -xzf "$PACKAGE_NAME" -C "$EXTRACT_DIR"

# Use example YAML files
if [ -d "$EXTRACT_DIR" ]; then
    echo "Using example YAML files from $EXTRACT_DIR..."
    # Add your commands to use the YAML files here
else
    echo "Extraction failed. Directory $EXTRACT_DIR not found."
    exit 1
fi

echo "PAQET server installation completed."