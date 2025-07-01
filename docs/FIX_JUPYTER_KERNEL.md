# 🔧 Fix: Jupyter Not Using Virtual Environment

## The Problem
Your Jupyter notebook is not using the virtual environment where pandas is installed.

## Quick Fix - 3 Steps:

### Step 1: Close Current Jupyter
Close any Jupyter tabs in your browser and stop any running notebooks.

### Step 2: Start Jupyter from Virtual Environment
In your terminal, run these commands:

```bash
cd /Users/psweeney/leader-capacity-dashboard
source venv/bin/activate
jupyter notebook
```

You should see `(venv)` at the beginning of your terminal prompt.

### Step 3: Check/Change the Kernel
1. Open your notebook
2. Look at the top-right corner - it should show "Python 3 (ipykernel)"
3. If it doesn't, go to: **Kernel → Change kernel → Python 3 (ipykernel)**

## Alternative: Install IPython Kernel

If the above doesn't work, install the kernel explicitly:

```bash
# Make sure you're in the virtual environment
source venv/bin/activate

# Install ipykernel in the venv
pip install ipykernel

# Add the virtual environment as a Jupyter kernel
python -m ipykernel install --user --name=venv --display-name="Python (venv)"
```

Then in Jupyter:
- **Kernel → Change kernel → Python (venv)**

## Test It Works

Run this in a cell:
```python
import sys
print(sys.executable)
# Should show: /Users/psweeney/leader-capacity-dashboard/venv/bin/python
```

## 🚀 One-Line Solution

I've already started Jupyter on port 8889. Open this URL in your browser:
**http://localhost:8889**

This instance is running with the correct virtual environment! 