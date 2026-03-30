
-- 1. Employees who take most leaves by category
-- Insight: Identify top employees by leave days, grouped by leave type
-- Facts: FactLeaveDay | Dims: DimEmployee, DimLeaveType, DimStatus | Measure: SUM(fd.DayCount)
SELECT e.EmployeeID, e.FirstName, e.LastName, e.CompanyName,
       lt.LeaveTypeCode,
       SUM(fd.DayCount) AS TotalDaysTaken
FROM FactLeaveDay fd
JOIN DimEmployee e ON fd.EmployeeKey = e.EmployeeKey
JOIN DimLeaveType lt ON fd.LeaveTypeKey = lt.LeaveTypeKey
JOIN DimStatus s ON fd.StatusKey = s.StatusKey
WHERE s.StatusCode = 'APPROVED'
GROUP BY e.EmployeeID, e.FirstName, e.LastName, e.CompanyName, lt.LeaveTypeCode
ORDER BY TotalDaysTaken DESC
LIMIT 10;


-- 2. Leave Utilization by Company & Employee
-- Insight: Shows proportion of expected work time taken as leave
-- Facts: FactLeaveDay | Dims: DimEmployee, DimStatus, DimDate | Measures: SUM(fd.HoursTaken) vs StandardHoursPerDay * WorkDays
SELECT e.CompanyName,
       e.EmployeeID, e.FirstName, e.LastName,
       SUM(fd.HoursTaken) AS TotalLeaveHours,
       (e.StandardHoursPerDay * COUNT(DISTINCT d.DateKey)) AS ExpectedWorkHours,
       SUM(fd.HoursTaken) / (e.StandardHoursPerDay * COUNT(DISTINCT d.DateKey)) AS LeaveUtilizationRate
FROM FactLeaveDay fd
JOIN DimEmployee e ON fd.EmployeeKey = e.EmployeeKey
JOIN DimStatus s ON fd.StatusKey = s.StatusKey
JOIN DimDate d ON fd.DateKey = d.DateKey
WHERE s.StatusCode = 'APPROVED'
  AND d.IsWeekend = 0
  AND d.IsHoliday = 0
GROUP BY e.CompanyName, e.EmployeeID, e.FirstName, e.LastName, e.StandardHoursPerDay
ORDER BY LeaveUtilizationRate DESC;


-- 3. Leave Approval Efficiency
-- Insight: Approval ratios, status breakdown, and average lead time
-- Facts: FactLeaveRequest | Dims: DimStatus, DimEmployee, DimLeaveType, DimDate | Measures: Approval ratio, % status breakdown, AVG(DATEDIFF(StartDate, RequestDate))
SELECT e.CompanyName,
       SUM(CASE WHEN s.StatusCode = 'APPROVED' THEN 1 ELSE 0 END) AS ApprovedRequests,
       COUNT(*) AS TotalRequests,
       ROUND(SUM(CASE WHEN s.StatusCode = 'APPROVED' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS ApprovalRatioPct,
       ROUND(AVG(DATEDIFF(ddStart.FullDate, ddReq.FullDate)), 2) AS AvgLeadTimeDays
FROM FactLeaveRequest fr
JOIN DimStatus s ON fr.StatusKey = s.StatusKey
JOIN DimEmployee e ON fr.EmployeeKey = e.EmployeeKey
JOIN DimDate ddReq ON fr.RequestDateKey = ddReq.DateKey
JOIN DimDate ddStart ON fr.StartDateKey = ddStart.DateKey
GROUP BY e.CompanyName
ORDER BY ApprovalRatioPct DESC;


-- 4. Average Leave Duration per Request by Category & Company
-- Insight: Finds if staff prefer short breaks or long holidays by leave type
-- Facts: FactLeaveRequest, FactLeaveDay | Dims: DimLeaveType, DimStatus, DimEmployee | Measure: AVG(COUNT(fd.DateKey))
SELECT e.CompanyName,
       lt.LeaveTypeCode,
       AVG(RequestLength) AS AvgLeaveDuration
FROM (
    SELECT fr.LeaveRequestKey,
           fr.LeaveTypeKey,
           fr.EmployeeKey,
           COUNT(DISTINCT fd.DateKey) AS RequestLength
    FROM FactLeaveRequest fr
    JOIN FactLeaveDay fd ON fr.LeaveRequestKey = fd.LeaveRequestKey
    JOIN DimStatus s ON fr.StatusKey = s.StatusKey
    WHERE s.StatusCode = 'APPROVED'
    GROUP BY fr.LeaveRequestKey, fr.LeaveTypeKey, fr.EmployeeKey
) sub
JOIN DimLeaveType lt ON sub.LeaveTypeKey = lt.LeaveTypeKey
JOIN DimEmployee e ON sub.EmployeeKey = e.EmployeeKey
GROUP BY e.CompanyName, lt.LeaveTypeCode
ORDER BY e.CompanyName, AvgLeaveDuration DESC;


-- 5. Sick & Unpaid Leave Trends
-- Insight: Tracks absenteeism trends over months (company + leave type)
-- Facts: FactLeaveDay | Dims: DimDate, DimLeaveType, DimEmployee, DimStatus | Measure: SUM(fd.DayCount)
SELECT e.CompanyName,
       d.Year, 
       d.MonthName,
       lt.LeaveTypeCode,
       SUM(fd.DayCount) AS TotalDays
FROM FactLeaveDay fd
JOIN DimDate d ON fd.DateKey = d.DateKey
JOIN DimLeaveType lt ON fd.LeaveTypeKey = lt.LeaveTypeKey
JOIN DimStatus s ON fd.StatusKey = s.StatusKey
JOIN DimEmployee e ON fd.EmployeeKey = e.EmployeeKey
WHERE lt.LeaveTypeCode IN ('SICK','UNPAID')
GROUP BY e.CompanyName, d.Year, d.MonthName, lt.LeaveTypeCode
ORDER BY e.CompanyName, d.Year, d.Month, lt.LeaveTypeCode;


-- 6. Leave Application Lead Time (Last-Minute vs Planned)
-- Insight: Shows if employees apply last minute or plan ahead
-- Facts: FactLeaveRequest | Dims: DimEmployee, DimDate | Measures: AVG lead time, counts of last-minute vs advance requests
SELECT e.CompanyName,
       e.EmployeeID, e.FirstName, e.LastName,
       AVG(DATEDIFF(ddStart.FullDate, ddReq.FullDate)) AS AvgLeadTimeDays,
       SUM(CASE WHEN DATEDIFF(ddStart.FullDate, ddReq.FullDate) <= 1 THEN 1 ELSE 0 END) AS LastMinuteRequests,
       SUM(CASE WHEN DATEDIFF(ddStart.FullDate, ddReq.FullDate) > 7 THEN 1 ELSE 0 END) AS PlannedInAdvanceRequests
FROM FactLeaveRequest fr
JOIN DimEmployee e ON fr.EmployeeKey = e.EmployeeKey
JOIN DimDate ddReq ON fr.RequestDateKey = ddReq.DateKey
JOIN DimDate ddStart ON fr.StartDateKey = ddStart.DateKey
GROUP BY e.CompanyName, e.EmployeeID, e.FirstName, e.LastName
ORDER BY e.CompanyName, AvgLeadTimeDays ASC;


-- 7. Current & Upcoming Coverage (Who’s on Leave)
-- Insight: Shows employees absent per company & day in next X days
-- Facts: FactLeaveDay | Dims: DimEmployee, DimDate, DimStatus, DimLeaveType | Measure: employee list on leave
SET @StartDate = CURDATE();
SET @EndDate   = DATE_ADD(CURDATE(), INTERVAL 30 DAY);

SELECT e.CompanyName,
       d.FullDate,
       e.EmployeeID,
       e.FirstName,
       e.LastName,
       lt.LeaveTypeCode
FROM FactLeaveDay fd
JOIN DimEmployee e ON fd.EmployeeKey = e.EmployeeKey
JOIN DimDate d ON fd.DateKey = d.DateKey
JOIN DimStatus s ON fd.StatusKey = s.StatusKey
JOIN DimLeaveType lt ON fd.LeaveTypeKey = lt.LeaveTypeKey
WHERE d.FullDate BETWEEN @StartDate AND @EndDate
ORDER BY e.CompanyName, d.FullDate, e.LastName, e.FirstName;


-- 8. Pre-Termination Absenteeism
-- Insight: Detects spikes in leave before resignation/termination
-- Facts: FactLeaveDay | Dims: DimEmployee, DimDate, DimStatus | Measure: SUM(fd.DayCount) last 90 days before termination
SELECT e.CompanyName,
       e.EmployeeID, e.FirstName, e.LastName,
       e.TerminationDate,
       SUM(fd.DayCount) AS LeaveDaysLast3Months
FROM DimEmployee e
JOIN FactLeaveDay fd ON e.EmployeeKey = fd.EmployeeKey
JOIN DimDate d ON fd.DateKey = d.DateKey
JOIN DimStatus s ON fd.StatusKey = s.StatusKey
WHERE e.TerminationDate IS NOT NULL
  AND d.FullDate BETWEEN DATE_SUB(e.TerminationDate, INTERVAL 90 DAY) AND e.TerminationDate
GROUP BY e.CompanyName, e.EmployeeID, e.FirstName, e.LastName, e.TerminationDate
ORDER BY e.CompanyName, e.TerminationDate DESC;


-- 9. Monthly Leave Seasonality (All applied leaves)
-- Insight: Finds peak leave months and quiet periods per company (all requests)
-- Facts: FactLeaveRequest, FactLeaveDay | Dims: DimEmployee, DimDate, DimStatus | Measures: COUNT(DISTINCT LeaveRequestKey), SUM(fd.DayCount)
SELECT e.CompanyName,
       d.Month,
       d.MonthName,
       COUNT(DISTINCT fr.LeaveRequestKey) AS TotalLeaveRequests,
       SUM(fd.DayCount) AS TotalLeaveDays
FROM FactLeaveRequest fr
JOIN FactLeaveDay fd ON fr.LeaveRequestKey = fd.LeaveRequestKey
JOIN DimEmployee e ON fr.EmployeeKey = e.EmployeeKey
JOIN DimDate d ON fd.DateKey = d.DateKey
JOIN DimStatus s ON fr.StatusKey = s.StatusKey
GROUP BY e.CompanyName, d.Month, d.MonthName
ORDER BY e.CompanyName, TotalLeaveDays DESC;

