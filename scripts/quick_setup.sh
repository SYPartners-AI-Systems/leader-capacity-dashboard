#!/bin/bash

echo "🔍 Checking your Python installation..."

# Check if Python 3 is installed
if command -v python3 &> /dev/null; then
    echo "✅ Python 3 is installed: $(python3 --version)"
else
    echo "❌ Python 3 is not installed"
    echo "Please visit https://www.python.org/downloads/ to install Python"
    echo "Download and run the macOS installer"
    exit 1
fi

# Check if pip is installed
if command -v pip3 &> /dev/null; then
    echo "✅ pip3 is already installed: $(pip3 --version)"
else
    echo "⚠️  pip3 is not found. Installing pip..."
    
    # Try to install pip using ensurepip first
    echo "Attempting to install pip..."
    python3 -m ensurepip --upgrade
    
    # If that didn't work, try get-pip
    if ! command -v pip3 &> /dev/null; then
        echo "Downloading pip installer..."
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python3 get-pip.py --user
        rm get-pip.py
    fi
fi

# Install required packages
echo ""
echo "📦 Installing required packages for the dashboard..."
python3 -m pip install --user pandas numpy matplotlib seaborn openpyxl jupyter

echo ""
echo "✅ Setup complete!"
echo ""
echo "To run the notebook:"
echo "1. cd /Users/psweeney/leader-capacity-dashboard"
echo "2. python3 -m notebook"
echo ""
echo "Then open the notebook file in your browser" 