# Installing Python and pip on macOS

## 🍎 For macOS Users (Your System)

### Option 1: Install Python from python.org (Recommended)
1. **Visit** https://www.python.org/downloads/
2. **Download** the latest Python installer for macOS
3. **Run** the installer (it includes pip automatically)
4. **Verify** installation:
   ```bash
   python3 --version
   pip3 --version
   ```

### Option 2: Using Homebrew (If you have it)
```bash
# Install Homebrew first if you don't have it:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then install Python (includes pip):
brew install python3

# Verify:
python3 --version
pip3 --version
```

### Option 3: Check if Python is Already Installed
macOS comes with Python, but it might be an older version:
```bash
# Check what you have:
python3 --version
python --version

# Check for pip:
pip3 --version
pip --version
```

## 🔧 If Python is installed but pip is missing:

### Install pip using get-pip.py:
```bash
# Download the pip installer
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py

# Install pip
python3 get-pip.py

# Clean up
rm get-pip.py
```

### Or use ensurepip:
```bash
python3 -m ensurepip --upgrade
```

## 📦 After Installing pip:

### Install packages for the notebook:
```bash
# Use pip3 on macOS:
pip3 install pandas numpy matplotlib seaborn openpyxl jupyter

# Or if pip3 doesn't work, try:
python3 -m pip install pandas numpy matplotlib seaborn openpyxl jupyter
```

## 🚀 Running Jupyter Notebook:

### Once everything is installed:
```bash
# Navigate to your project directory
cd /Users/psweeney/leader-capacity-dashboard

# Start Jupyter
jupyter notebook

# Or use:
python3 -m notebook
```

## ⚡ Quick Install Script

Save this as `setup.sh` and run it:
```bash
#!/bin/bash

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Please install from python.org"
    exit 1
fi

# Check if pip is installed
if ! command -v pip3 &> /dev/null; then
    echo "Installing pip..."
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python3 get-pip.py
    rm get-pip.py
fi

# Install required packages
echo "Installing required packages..."
pip3 install pandas numpy matplotlib seaborn openpyxl jupyter

echo "✅ Setup complete! You can now run: jupyter notebook"
```

Make it executable and run:
```bash
chmod +x setup.sh
./setup.sh
```

## 🆘 Troubleshooting

### Permission Errors:
If you get permission errors, use `--user`:
```bash
pip3 install --user pandas numpy matplotlib seaborn openpyxl jupyter
```

### Path Issues:
Add Python to your PATH by adding this to `~/.zshrc`:
```bash
export PATH="/Library/Frameworks/Python.framework/Versions/3.x/bin:$PATH"
```

Then reload:
```bash
source ~/.zshrc
```

## 📱 Alternative: Use Google Colab

If local installation is problematic, you can use Google Colab:
1. Visit https://colab.research.google.com
2. Upload your notebook
3. Upload your CSV files
4. No installation needed!

## 🐍 Alternative: Anaconda

For a complete data science environment:
1. Download Anaconda from https://www.anaconda.com/products/individual
2. Run the installer
3. All packages are pre-installed!

After installation, use:
```bash
conda activate base
jupyter notebook
``` 