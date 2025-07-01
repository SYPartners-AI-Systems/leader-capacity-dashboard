#!/bin/bash

# Navigate to project directory
cd /Users/psweeney/leader-capacity-dashboard

# Activate virtual environment
source venv/bin/activate

# Start Jupyter notebook
echo "🚀 Starting Jupyter Notebook..."
echo "📝 Your notebook will open in your default browser"
echo "🛑 Press Ctrl+C to stop the notebook server when done"
echo ""

jupyter notebook notebooks/leader_capacity_data_engineering.ipynb 