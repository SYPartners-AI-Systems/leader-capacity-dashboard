# Setup Guide for Leader Capacity Dashboard

## 🚀 Quick Start

### Resolving the "ModuleNotFoundError" for pandas

You're getting this error because the required Python packages aren't installed. Here are three ways to fix it:

### Option 1: Using the Notebook (Recommended)
1. **Run Cell 2** in the notebook
2. **Uncomment** the pip install line:
   ```python
   !pip install pandas numpy matplotlib seaborn openpyxl
   ```
3. **Run the cell** to install all packages
4. **Continue** with Cell 3 and beyond

### Option 2: Using requirements.txt
```bash
# In your terminal/command prompt:
pip install -r requirements.txt
```

### Option 3: Install individually
```bash
# Install each package separately:
pip install pandas
pip install numpy
pip install matplotlib
pip install seaborn
pip install openpyxl
```

## 📋 Package Versions

The notebook requires:
- **pandas** - For data manipulation
- **numpy** - For numerical operations
- **matplotlib** - For plotting (optional)
- **seaborn** - For enhanced visualizations (optional)
- **openpyxl** - For Excel file export

## 🔧 Environment Setup

### Using Virtual Environment (Recommended)
```bash
# Create virtual environment
python -m venv venv

# Activate it
# On Windows:
venv\Scripts\activate
# On Mac/Linux:
source venv/bin/activate

# Install packages
pip install -r requirements.txt
```

### Using Conda
```bash
# Create conda environment
conda create -n leader-dashboard python=3.9

# Activate it
conda activate leader-dashboard

# Install packages
conda install pandas numpy matplotlib seaborn openpyxl
```

## ✅ Verify Installation

After installation, run this in Python to verify:
```python
import pandas as pd
import numpy as np
print("✅ Packages installed successfully!")
print(f"Pandas version: {pd.__version__}")
print(f"Numpy version: {np.__version__}")
```

## 🆘 Troubleshooting

### If pip install fails:
1. **Update pip**: `python -m pip install --upgrade pip`
2. **Try with --user flag**: `pip install --user pandas numpy`
3. **Check Python version**: Ensure you're using Python 3.7+

### If using Jupyter in VS Code:
1. Make sure you've selected the correct Python interpreter
2. Click on the Python version in the top-right corner
3. Select the environment where you installed the packages

## 📚 Next Steps

Once packages are installed:
1. **Restart the kernel** in Jupyter
2. **Run cells sequentially** starting from Cell 1
3. **Check the output** of each cell for any errors
4. **Refer to NOTEBOOK_CELL_INDEX.md** for cell descriptions 