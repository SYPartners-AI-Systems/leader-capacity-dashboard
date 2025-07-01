# Leader Capacity Dashboard Project Plan

## Executive Summary
This project aims to recreate a leader capacity dashboard in Domo that provides real-time visibility into resource utilization, vacation schedules, and sales opportunities. The dashboard will display the current month plus three future months of capacity data.

## Project Objectives
1. **Primary Goal**: Create an automated dashboard showing leader/resource capacity utilization
2. **Key Metrics**:
   - Booked time as percentage of available monthly capacity
   - Vacation and leave schedules
   - Sales opportunities with probability and timeline
   - Regional breakdown (US, UAE, Europe)

## Data Sources

### 1. 10k Data (Time Booking System)
- **Purpose**: Track actual time booked by resources
- **Key Fields Needed**:
  - [ ] Employee/Resource Name
  - [ ] Project/Engagement Code
  - [ ] Hours Booked
  - [ ] Date/Period
  - [ ] Region/Office
- **TODO**: Map data structure once file is accessible

### 2. Namely Vacation and Leave Dataset
- **Purpose**: Track planned time off
- **Key Fields Needed**:
  - [ ] Employee Name
  - [ ] Leave Type
  - [ ] Start Date
  - [ ] End Date
  - [ ] Hours/Days
- **TODO**: Understand leave calculation logic

### 3. Salesforce Opportunity Data
- **Available Fields**:
  - Probability (0-100%)
  - Account Name
  - Engagement Name
  - Schedule Month
  - Schedule Amount
  - Region
  - Primary Partner
  - Engagement Dates
- **Status**: ✅ Structure understood

### 4. Working Hours Calendars
- **US Working Hours**: ✅ Loaded and structured
- **UAE Working Hours**: Needs verification
- **Key Data**: Net working hours per month, holidays, billable days

## Technical Architecture

### Phase 1: Data Engineering Pipeline
1. **Data Ingestion**
   - [ ] Set up automated data pulls from source systems
   - [ ] Handle large file processing (10k and vacation data)
   - [ ] Implement error handling and logging

2. **Data Transformation**
   - [ ] Standardize date formats across all sources
   - [ ] Create person-month aggregations
   - [ ] Calculate derived metrics (capacity %, weighted pipeline)
   - [ ] Handle regional differences in working hours

3. **Data Quality**
   - [ ] Implement validation rules
   - [ ] Create data quality dashboard
   - [ ] Set up alerting for anomalies

### Phase 2: Dashboard Development
1. **Domo Setup**
   - [ ] Create Domo datasets
   - [ ] Set up data refresh schedules
   - [ ] Design data flow architecture

2. **Dashboard Components**
   - [ ] **Capacity Overview**: 4-month rolling view
   - [ ] **Individual Drill-down**: Per-person capacity details
   - [ ] **Team/Regional Views**: Aggregated capacity by region
   - [ ] **Opportunity Pipeline**: Weighted by probability
   - [ ] **Vacation Calendar**: Visual timeline view

### Phase 3: Advanced Features
1. **Predictive Analytics**
   - [ ] Forecast capacity based on historical patterns
   - [ ] Identify potential resource constraints
   - [ ] Opportunity win probability modeling

2. **Alerting & Automation**
   - [ ] Over-allocation warnings
   - [ ] Upcoming vacation reminders
   - [ ] High-value opportunity notifications

## Implementation Timeline

### Week 1-2: Data Understanding & Preparation
- [ ] Complete data profiling for all sources
- [ ] Document data dictionaries
- [ ] Identify and resolve data quality issues
- [ ] Create initial data processing scripts

### Week 3-4: Pipeline Development
- [ ] Build ETL processes
- [ ] Implement data validation
- [ ] Create staging tables
- [ ] Test with sample data

### Week 5-6: Domo Integration
- [ ] Set up Domo connectors
- [ ] Create base datasets
- [ ] Build initial dashboard views
- [ ] Implement refresh logic

### Week 7-8: Dashboard Refinement
- [ ] Add interactive features
- [ ] Implement drill-down capabilities
- [ ] Create mobile views
- [ ] User acceptance testing

### Week 9-10: Launch & Training
- [ ] Deploy to production
- [ ] Create user documentation
- [ ] Conduct training sessions
- [ ] Establish support processes

## Key Considerations

### Data Privacy & Security
- [ ] Ensure PII is properly handled
- [ ] Implement role-based access control
- [ ] Audit trail for data changes
- [ ] Compliance with data regulations

### Performance Optimization
- [ ] Optimize large dataset processing
- [ ] Implement incremental updates
- [ ] Cache frequently accessed data
- [ ] Monitor query performance

### Change Management
- [ ] Stakeholder communication plan
- [ ] User training materials
- [ ] Feedback collection process
- [ ] Iterative improvement cycle

## Success Metrics
1. **Technical Metrics**
   - Dashboard refresh time < 5 minutes
   - 99.9% uptime
   - < 3 second load time for views

2. **Business Metrics**
   - Resource utilization visibility improved by 50%
   - Capacity planning accuracy increased by 30%
   - Reduced time spent on manual reporting by 80%

## Risk Mitigation

| Risk | Impact | Mitigation Strategy |
|------|--------|-------------------|
| Large data volume | High | Implement incremental processing and data archival |
| Data quality issues | Medium | Create validation rules and exception reporting |
| Integration complexity | Medium | Phase implementation and thorough testing |
| User adoption | Medium | Comprehensive training and change management |

## Required Resources
1. **Technical Team**
   - Data Engineer (1 FTE)
   - Domo Developer (0.5 FTE)
   - QA Analyst (0.5 FTE)

2. **Business Team**
   - Project Manager
   - Business Analyst
   - Subject Matter Experts

3. **Infrastructure**
   - Domo licenses
   - Data storage
   - Processing servers

## Open Questions & Decisions Needed

1. **Data Refresh Frequency**
   - [ ] Real-time vs. daily updates?
   - [ ] Different frequencies for different data sources?

2. **Historical Data**
   - [ ] How much historical data to maintain?
   - [ ] Archival strategy?

3. **Access Control**
   - [ ] Who should see individual vs. aggregated data?
   - [ ] Regional data restrictions?

4. **Integration Points**
   - [ ] Direct database connections vs. file imports?
   - [ ] API availability for source systems?

5. **Calculation Logic**
   - [ ] How to handle partial month allocations?
   - [ ] Treatment of holidays across regions?
   - [ ] Opportunity probability thresholds?

## Next Steps
1. Review and validate data field mappings with stakeholders
2. Prioritize dashboard features for MVP
3. Establish data governance policies
4. Schedule kickoff meeting with all stakeholders
5. Create detailed technical specifications

---

*This is a living document and will be updated as the project progresses.* 