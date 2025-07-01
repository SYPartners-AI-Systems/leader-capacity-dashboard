# Leader Capacity Dashboard Notebook - Cell Index

## 📑 Complete Cell Listing (Updated)

### Overview Cells
- **[Cell 0]** - Table of Contents (Markdown)
- **[Cell 1]** - Project Overview (Markdown)
- **[Cell 2]** - Install Required Packages (Python) ⚠️ **RUN THIS FIRST IF GETTING ERRORS**
- **[Cell 3]** - Import Required Libraries (Python)

### Data Loading Cells
- **[Cell 4]** - Data Loading Section Header (Markdown)
- **[Cell 5]** - Load 10k Booking Data (Python)
- **[Cell 6]** - Load Vacation and Leave Data (Python)
- **[Cell 7]** - Load Salesforce Opportunity Data (Python)
- **[Cell 8]** - Load US Working Hours Data (Python)
- **[Cell 9]** - Load UAE Working Hours Data (Python)

### Data Processing Cells
- **[Cell 10]** - Data Processing Section Header (Markdown)
- **[Cell 11]** - Set Up Date Range for Dashboard (Python)
- **[Cell 12]** - Process Salesforce Opportunity Data Header (Markdown)
- **[Cell 13]** - Filter and Aggregate Salesforce Data (Python)
- **[Cell 14]** - Helper Functions Section Header (Markdown)
- **[Cell 15]** - Define Helper Functions for Capacity Calculations (Python)

### Dashboard Structure Cells
- **[Cell 16]** - Dashboard Structure Section Header (Markdown)
- **[Cell 17]** - Create Master Dashboard DataFrame (Python)

### Data Quality Cells
- **[Cell 18]** - Data Quality Section Header (Markdown)
- **[Cell 19]** - Data Quality Check Functions and Execution (Python)

### Export and Next Steps Cells
- **[Cell 20]** - Data Export Section Header (Markdown)
- **[Cell 21]** - Export Functions for Dashboard (Python)
- **[Cell 22]** - Next Steps and TODO Items (Markdown)

## 🚨 IMPORTANT: Fixing Import Errors

If you see `ModuleNotFoundError: No module named 'pandas'`:

1. **Go to Cell 2**
2. **Uncomment the pip install line**:
   ```python
   !pip install pandas numpy matplotlib seaborn openpyxl
   ```
3. **Run Cell 2**
4. **Continue with Cell 3**

## 🎯 Quick Reference

### Essential Cells to Run in Order:
1. **Cell 2** - Install packages (if needed)
2. **Cell 3** - Import libraries
3. **Cells 5-9** - Load all data sources
4. **Cell 11** - Set up date ranges
5. **Cell 13** - Process Salesforce data (if loaded)
6. **Cell 15** - Define helper functions
7. **Cell 17** - Create dashboard structure
8. **Cell 19** - Run data quality checks
9. **Cell 21** - Export functions (when ready)

### Key Variables Created:
- `df_10k` - 10k booking data (Cell 5)
- `df_vacation` - Vacation data (Cell 6)
- `df_salesforce` - Salesforce opportunities (Cell 7)
- `df_us_hours` - US working hours (Cell 8)
- `df_uae_hours` - UAE working hours (Cell 9)
- `dashboard_months` - 4-month date range (Cell 11)
- `df_dashboard` - Master dashboard structure (Cell 17)

### Helper Functions Available:
- `get_working_hours_for_month()` - Get working hours for a specific month/region
- `calculate_capacity_percentage()` - Calculate utilization percentage
- `aggregate_by_person_month()` - Aggregate hours by person and month
- `check_data_quality()` - Run quality checks on any dataframe
- `export_dashboard_data()` - Export data in various formats

## 📝 Notes
- All cells are numbered with [Cell X] format for easy reference
- Python cells include descriptive comments
- Error handling is implemented for all data loading operations
- The notebook is designed to be run sequentially but can handle missing data gracefully

## 🆕 New Files Created
- `requirements.txt` - List of all required Python packages
- `SETUP_GUIDE.md` - Detailed setup instructions for resolving installation issues 