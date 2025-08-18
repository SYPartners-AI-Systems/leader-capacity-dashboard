# Leader Capacity Dashboard

A data engineering project to recreate a leader capacity dashboard showing resource utilization, vacation data, and sales pipeline for current month plus 3 future months.

## 📁 Project Structure

```
leader-capacity-dashboard/
├── data/                    # All data files
│   ├── 10k Data for S3 (1).csv
│   ├── 10k Users.csv
│   ├── Namely Vacation and Leave Dataset.csv
│   ├── Salesforce Opportunity Data.csv
│   ├── UAE Working Hours.csv
│   └── Working Hours For US.csv
├── notebooks/               # Jupyter notebooks
│   └── leader_capacity_data_engineering.ipynb
├── scripts/                 # Utility scripts
│   ├── create_notebook.py
│   ├── quick_setup.sh
│   └── run_notebook.sh
├── docs/                    # Documentation
│   ├── LEADER_CAPACITY_DASHBOARD_PROJECT_PLAN.md
│   ├── NOTEBOOK_CELL_INDEX.md
│   ├── SETUP_GUIDE.md
│   ├── INSTALL_PYTHON_GUIDE.md
│   └── FIX_JUPYTER_KERNEL.md
├── images/                  # Screenshots and images
│   └── Screenshot 2025-07-01 at 4.25.15 PM.png
├── venv/                    # Python virtual environment
├── requirements.txt         # Python dependencies
└── README.md               # This file
```

## 🚀 Quick Start

1. **Setup Environment**
   ```bash
   cd leader-capacity-dashboard
   ./scripts/quick_setup.sh
   ```

2. **Activate Virtual Environment**
   ```bash
   source venv/bin/activate
   ```

3. **Run Jupyter Notebook**
   ```bash
   ./scripts/run_notebook.sh
   ```
   
   Or manually:
   ```bash
   jupyter notebook notebooks/leader_capacity_data_engineering.ipynb
   ```

## 📊 Dashboard Overview

The dashboard displays:
- **Capacity Utilization**: Booked time as % of available working time
- **Filtered Roles**: Design, Principal, Program Management, Strategy, Studio, Tech
- **Time Period**: Current month + 3 future months
- **Regional Data**: US and UAE working hours
- **Pipeline Data**: Salesforce opportunities with probability weighting

## 📋 Key Features

- Filters 10k booking data by selected leadership roles
- Calculates capacity percentages based on regional working hours
- Integrates vacation/leave data
- Includes weighted sales pipeline from Salesforce
- Exports data in multiple formats (CSV, Excel, JSON)

## 📖 Documentation

- **[Project Plan](docs/LEADER_CAPACITY_DASHBOARD_PROJECT_PLAN.md)** - Comprehensive project overview
- **[Setup Guide](docs/SETUP_GUIDE.md)** - Detailed installation instructions
- **[Notebook Index](docs/NOTEBOOK_CELL_INDEX.md)** - Cell-by-cell reference
- **[Python Install Guide](docs/INSTALL_PYTHON_GUIDE.md)** - Python setup help
- **[Jupyter Kernel Fix](docs/FIX_JUPYTER_KERNEL.md)** - Troubleshooting guide

## 🛠️ Requirements

- Python 3.13.5+
- See `requirements.txt` for Python packages
- ~50MB of CSV data files

## 📝 Notes

- Data files contain sensitive information and should not be committed to version control
- The notebook filters for specific leadership roles only
- All timestamps are handled in UTC

## 🧩 Domo MySQL DataFlows (Comp + Titles + Philosophy)

This project includes SQL transforms intended for a Domo MySQL DataFlow to create a Consulting-only compensation history with title overrides and salary philosophy mapping.

- Inputs (as shown in Domo left panel):
  - `namely_comp_data_history_w_notes` (Namely Comp Data w/ Notes)
  - `namely_title_history_data_aq` (Namely Title History)
  - `Comp Philosophy - Salary Adjustments (input for modeling) - All.csv` (salary philosophy table)

- Core rules applied in SQL (see `Consulting Salary History for Modeling/Consultants_Salary_Data_projection.SQL`):
  - Division = Consulting; Start Date >= 2016-01-01
  - Effective date for comp rows: `COALESCE(Salary Start Date, Start Date)`
  - Title override from Title History:
    - Prefer change within ±15 days of comp effective date (favor on/before)
    - Fallback to latest title on/before comp effective date
  - Title normalization: optional CASE mapping to canonical titles

- Philosophy mapping (third input CSV):
  - Columns used: `Step & Level`, `Annual Salary USD`, `Salary Start/End Effective Date`, `Department`, `Roles/ Titles`
  - Blank philosophy end dates are treated as open-ended (current)
  - Mapping method by comp effective date:
    - Before 2022‑02‑01: nearest-step match by minimizing % difference between comp `Salary` and philosophy `Annual Salary`
    - On/after 2022‑02‑01: exact match on `Step & Level` = `Level` + ' - Step ' + `Step`
  - Output fields include mapped step/level, target annual salary, and variance %

- Misalignment report:
  - Separate SQL transform outputs rows where no title could be matched (neither ±15d nor fallback)
  - Includes nearest title change dates before/after and a reason string for diagnosis

Tip: If your Domo MySQL does not support CTEs/window functions, use the provided MySQL 5.7–compatible queries (no CTEs) from the conversation and adapt table names to your inputs.

