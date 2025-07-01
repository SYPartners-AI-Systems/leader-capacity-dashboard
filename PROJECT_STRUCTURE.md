# Project Structure Guide

## 🗂️ Directory Layout

```
📁 leader-capacity-dashboard/
│
├── 📊 data/                    ← All data files (CSV)
│   ├── 10k Data for S3 (1).csv
│   ├── 10k Users.csv
│   ├── Namely Vacation and Leave Dataset.csv
│   ├── Salesforce Opportunity Data.csv
│   ├── UAE Working Hours.csv
│   └── Working Hours For US.csv
│
├── 📓 notebooks/               ← Jupyter notebooks
│   └── leader_capacity_data_engineering.ipynb
│
├── 🛠️ scripts/                 ← Utility scripts
│   ├── create_notebook.py      ← Creates new notebook structure
│   ├── quick_setup.sh          ← One-click setup
│   └── run_notebook.sh         ← Launch notebook
│
├── 📚 docs/                    ← Documentation
│   ├── LEADER_CAPACITY_DASHBOARD_PROJECT_PLAN.md
│   ├── NOTEBOOK_CELL_INDEX.md
│   ├── SETUP_GUIDE.md
│   ├── INSTALL_PYTHON_GUIDE.md
│   └── FIX_JUPYTER_KERNEL.md
│
├── 🖼️ images/                  ← Screenshots & diagrams
│   └── Screenshot 2025-07-01 at 4.25.15 PM.png
│
├── 🐍 venv/                    ← Virtual environment (auto-generated)
│
├── 📄 requirements.txt         ← Python dependencies
├── 📖 README.md               ← Main project documentation
├── 📋 PROJECT_STRUCTURE.md    ← This file
└── 🔒 .gitignore              ← Git ignore rules
```

## 🚀 Quick Actions

| Task | Command |
|------|---------|
| **Setup project** | `./scripts/quick_setup.sh` |
| **Run notebook** | `./scripts/run_notebook.sh` |
| **Activate environment** | `source venv/bin/activate` |
| **View documentation** | Open `docs/` folder |

## 📌 Key Files

- **Main Notebook**: `notebooks/leader_capacity_data_engineering.ipynb`
- **Project Plan**: `docs/LEADER_CAPACITY_DASHBOARD_PROJECT_PLAN.md`
- **Cell Reference**: `docs/NOTEBOOK_CELL_INDEX.md`

## 🎯 Workflow

1. **Data** flows from `data/` → 
2. **Processing** in `notebooks/` →
3. **Output** for Domo dashboard

The notebook filters for these leadership roles:
- Design
- Principal
- Program Management
- Strategy
- Studio
- Tech 