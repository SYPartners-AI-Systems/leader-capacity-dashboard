#!/usr/bin/env python3
"""
Add sample vacation data for July-October 2025 to the Namely Vacation dataset.
This script adds realistic vacation records for existing leadership users.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random

def main():
    print("🏖️ Adding Sample Vacation Data for July-October 2025")
    print("="*60)
    
    # Load the original vacation data
    vacation_file = 'data/Namely Vacation and Leave Dataset.csv'
    df_vacation = pd.read_csv(vacation_file)
    original_count = len(df_vacation)
    print(f"✅ Loaded original vacation data: {original_count:,} records")
    
    # Load the users data to get leadership names
    df_users = pd.read_csv('data/10k Users.csv')
    selected_roles = ['Design', 'Principal', 'Program Management', 'Strategy', 'Studio', 'Tech']
    df_leadership = df_users[df_users['role'].isin(selected_roles)]
    
    # Get leadership users
    leadership_users = []
    for _, user in df_leadership.iterrows():
        # Get individual values to avoid Series boolean issues
        emp_num = user.get('employee_number', None)
        location = user.get('location', 'Remote')
        discipline = user.get('discipline', 'Leadership')
        
        leadership_users.append({
            'Full Name': f"{user['first_name']} {user['last_name']}",
            'First Name': user['first_name'],
            'Last Name': user['last_name'],
            'Employee Number': emp_num if pd.notna(emp_num) else f"EMP-{str(user['id']).zfill(6)}",
            'Employee Type': 'Staff Full Time',
            'Office Location': location if pd.notna(location) else 'Remote',
            'Job Title': user['role'],
            'Departments': discipline if pd.notna(discipline) else 'Leadership'
        })
    
    print(f"✅ Found {len(leadership_users)} leadership users")
    
    # Define vacation types and their typical durations
    vacation_types = [
        ('Vacation', 5, 10),  # Type, min days, max days
        ('Work From Anywhere', 3, 5),
        ('Sick', 1, 3),
        ('UAE Vacation', 7, 14),
        ('Family Caregiver Leave', 2, 5),
        ('Bereavement', 3, 3),
    ]
    
    # Create sample records for July-October 2025
    new_records = []
    months = [
        (datetime(2025, 7, 1), 'July'),
        (datetime(2025, 8, 1), 'August'),
        (datetime(2025, 9, 1), 'September'),
        (datetime(2025, 10, 1), 'October')
    ]
    
    # Sample 30% of leadership users for vacation records
    sample_size = max(20, int(len(leadership_users) * 0.3))
    sampled_users = random.sample(leadership_users, min(sample_size, len(leadership_users)))
    
    print(f"\n📊 Creating vacation records for {len(sampled_users)} users")
    
    for user in sampled_users:
        # Each user gets 1-3 vacation records across the 4 months
        num_vacations = random.randint(1, 3)
        
        for _ in range(num_vacations):
            # Pick a random month
            month_start, month_name = random.choice(months)
            
            # Pick a random vacation type
            vac_type, min_days, max_days = random.choice(vacation_types)
            days = random.randint(min_days, max_days)
            
            # Random start day within the month (avoiding weekends for start)
            start_day = random.randint(1, 20)
            start_date = month_start.replace(day=start_day)
            
            # Skip weekends for start date
            while start_date.weekday() >= 5:  # 5=Saturday, 6=Sunday
                start_date += timedelta(days=1)
            
            # Calculate end date
            end_date = start_date + timedelta(days=days-1)
            
            # Create the record matching the original format
            record = {
                'User status': 'Active Employee',
                'Scheduled From Accrued': 0.0,
                'Employee Type': user['Employee Type'],
                'Used': float(days),
                'Departments': user['Departments'],
                'Type': vac_type,
                'Employee Number': user['Employee Number'],
                'Departure date': end_date.strftime('%Y-%m-%d') if days > 1 else np.nan,
                'Full Name': user['Full Name'],
                'Start date': start_date.strftime('%Y-%m-%d'),
                'Office Location': user['Office Location'],
                'Job Title': user['Job Title'],
                'Accrual Year': 2025,
                'Units': 'days',
                'Scheduled': 0.0,
                'First Name': user['First Name'],
                'Last Name': user['Last Name'],
                '_BATCH_ID_': 99.0,  # New batch ID for sample data
                '_BATCH_LAST_RUN_': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            }
            
            new_records.append(record)
    
    # Convert new records to DataFrame
    df_new = pd.DataFrame(new_records)
    print(f"\n✅ Created {len(df_new)} new vacation records")
    
    # Show sample of new records
    print("\n📊 Sample of new vacation records:")
    sample_display = df_new[['Full Name', 'Type', 'Start date', 'Used', 'Job Title']].head(10)
    print(sample_display.to_string(index=False))
    
    # Show distribution by month
    df_new['Month'] = pd.to_datetime(df_new['Start date']).dt.strftime('%Y-%m')
    print("\n📅 New records by month:")
    print(df_new['Month'].value_counts().sort_index())
    
    # Combine with original data
    df_combined = pd.concat([df_vacation, df_new], ignore_index=True)
    
    # Save the updated file
    print(f"\n💾 Saving updated vacation data...")
    df_combined.to_csv(vacation_file, index=False)
    
    print(f"\n✅ Success! Updated vacation data saved:")
    print(f"   • Original records: {original_count:,}")
    print(f"   • New records added: {len(df_new)}")
    print(f"   • Total records: {len(df_combined):,}")
    print(f"\n📍 File saved to: {vacation_file}")
    
    # Create a backup of the original
    backup_file = vacation_file.replace('.csv', '_original_backup.csv')
    df_vacation.to_csv(backup_file, index=False)
    print(f"📦 Backup of original data saved to: {backup_file}")

if __name__ == "__main__":
    main() 