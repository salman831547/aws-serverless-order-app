#!/bin/bash

# 1. Define the environment name
ENV_NAME="my_env"

echo "--- Checking Prerequisites ---"

# 2. Check and install python3-venv if missing
if ! dpkg -s python3-venv >/dev/null 2>&1; then
    echo "Installing python3-venv..."
    sudo apt update
    sudo apt install -y python3-venv
else
    echo "python3-venv is already installed."
fi

# 3. Create the Virtual Environment if it doesn't exist
if [ ! -d "$ENV_NAME" ]; then
    echo "Creating virtual environment '$ENV_NAME'..."
    python3 -m venv "$ENV_NAME"
else
    echo "Virtual environment '$ENV_NAME' already exists."
fi

# 4. Activate the Environment
echo "Activating environment..."
source "${ENV_NAME}/bin/activate"

# 5. Confirmation
if [ -n "$VIRTUAL_ENV" ]; then
    echo "SUCCESS: Virtual environment '$ENV_NAME' is active."
    echo "Python location: $(which python)"
else
    echo "ERROR: Failed to activate environment."
fi