

-- DDLs for schema model--------------------------------------
-- ==============================
-- Drop if exists (safety)
-- ==============================
-- DROP TABLE IF EXISTS FactLeaveDay;
-- DROP TABLE IF EXISTS FactLeaveRequest;
-- DROP TABLE IF EXISTS DimEmployee;
-- DROP TABLE IF EXISTS DimLeaveType;
-- DRO P TABLE IF EXISTS DimStatus;
-- DROP TABLE IF EXISTS DimDate;

-- ==============================
-- Dimension Tables
-- ==============================

-- Employee Dimension (includes company info, SCD2-ready)
CREATE TABLE DimEmployee (
    EmployeeKey INT AUTO_INCREMENT PRIMARY KEY,
    EmployeeID INT NOT NULL,
    EmployeeNumber VARCHAR(50),
    FirstName VARCHAR(100),
    LastName VARCHAR(100),
    HireDate DATE,
    TerminationDate DATE,
    StandardHoursPerDay DECIMAL(4,2),
    CompanyID INT NOT NULL,
    CompanyName VARCHAR(200) NOT NULL,
    EffectiveStartDate DATE,
    EffectiveEndDate DATE,
    IsCurrent TINYINT(1)
);

-- Leave Type Dimension
CREATE TABLE DimLeaveType (
    LeaveTypeKey INT AUTO_INCREMENT PRIMARY KEY,
    LeaveTypeCode ENUM('ANNUAL','SICK','UNPAID','OTHER') NOT NULL,
    LeaveTypeDescription VARCHAR(100)
);

-- Leave Status Dimension
CREATE TABLE DimStatus (
    StatusKey INT AUTO_INCREMENT PRIMARY KEY,
    StatusCode ENUM('PENDING','APPROVED','REJECTED','CANCELLED') NOT NULL,
    StatusDescription VARCHAR(100)
);

-- Date Dimension
CREATE TABLE DimDate (
    DateKey INT PRIMARY KEY,  -- YYYYMMDD
    FullDate DATE NOT NULL,
    DayOfWeek INT,
    DayName VARCHAR(20),
    Month INT,
    MonthName VARCHAR(20),
    Quarter INT,
    Year INT,
    IsWeekend TINYINT(1),
    IsHoliday TINYINT(1) DEFAULT 0
);

-- ==============================
-- Fact Tables
-- ==============================

-- Leave Request Fact
CREATE TABLE FactLeaveRequest (
    LeaveRequestKey INT AUTO_INCREMENT PRIMARY KEY,
    EmployeeKey INT NOT NULL,
    LeaveTypeKey INT NOT NULL,
    StatusKey INT NOT NULL,
    RequestDateKey INT NOT NULL,
    StartDateKey INT NOT NULL,
    EndDateKey INT NOT NULL,
    ApproverKey INT,
    RequestedDays INT,
    ApprovedDays INT,
    RequestCount INT DEFAULT 1,
    SourceLeaveRequestID INT,
    FOREIGN KEY (EmployeeKey) REFERENCES DimEmployee(EmployeeKey),
    FOREIGN KEY (LeaveTypeKey) REFERENCES DimLeaveType(LeaveTypeKey),
    FOREIGN KEY (StatusKey) REFERENCES DimStatus(StatusKey),
    FOREIGN KEY (RequestDateKey) REFERENCES DimDate(DateKey),
    FOREIGN KEY (StartDateKey) REFERENCES DimDate(DateKey),
    FOREIGN KEY (EndDateKey) REFERENCES DimDate(DateKey)
);

-- Leave Day Fact
CREATE TABLE FactLeaveDay (
    LeaveDayKey INT AUTO_INCREMENT PRIMARY KEY,
    LeaveRequestKey INT NOT NULL,
    EmployeeKey INT NOT NULL,
    LeaveTypeKey INT NOT NULL,
    StatusKey INT NOT NULL,
    DateKey INT NOT NULL,
    HoursTaken DECIMAL(6,2),
    DayCount INT DEFAULT 1,
    FOREIGN KEY (LeaveRequestKey) REFERENCES FactLeaveRequest(LeaveRequestKey),
    FOREIGN KEY (EmployeeKey) REFERENCES DimEmployee(EmployeeKey),
    FOREIGN KEY (LeaveTypeKey) REFERENCES DimLeaveType(LeaveTypeKey),
    FOREIGN KEY (StatusKey) REFERENCES DimStatus(StatusKey),
    FOREIGN KEY (DateKey) REFERENCES DimDate(DateKey)
);


-- insert data into start schema tables


INSERT INTO DimEmployee (EmployeeID, EmployeeNumber, FirstName, LastName,
                         HireDate, TerminationDate, StandardHoursPerDay,
                         CompanyID, CompanyName,
                         EffectiveStartDate, EffectiveEndDate, IsCurrent)
SELECT e.EmployeeID,
       e.EmployeeNumber,
       e.FirstName,
       e.LastName,
       e.HireDate,
       e.TerminationDate,
       e.StandardHoursPerDay,
       c.CompanyID,
       c.CompanyName,
       e.HireDate,
       '9999-12-31',
       1
FROM Employee e
JOIN Company c ON e.CompanyID = c.CompanyID;

Select * from DimEmployee limit 100; 

INSERT INTO DimLeaveType (LeaveTypeCode, LeaveTypeDescription)
Select distinct LeaveTypeCode, 
       CASE LeaveTypeCode
        WHEN 'ANNUAL' THEN 'Annual Leave'
        WHEN 'SICK'   THEN 'Sick Leave'
        WHEN 'UNPAID' THEN 'Unpaid Leave'
        WHEN 'OTHER'  THEN 'Other Leave'
        ELSE 'Unknown'
    END AS LeaveType
  from LeaveRequest;
  
  Select * from DimLeaveType;
  
INSERT INTO FactLeaveRequest
(EmployeeKey, LeaveTypeKey, StatusKey, RequestDateKey, StartDateKey, EndDateKey,
 ApproverKey, RequestedDays, ApprovedDays, RequestCount, SourceLeaveRequestID)
SELECT de.EmployeeKey,
       dlt.LeaveTypeKey,
       ds.StatusKey,
       ddReq.DateKey,
       ddStart.DateKey,
       ddEnd.DateKey,
       NULL,
       DATEDIFF(lr.EndDate, lr.StartDate) + 1,
       CASE WHEN lr.StatusCode='APPROVED'
            THEN (DATEDIFF(lr.EndDate, lr.StartDate) + 1) ELSE 0 END,
       1,
       lr.LeaveRequestID              -- store source business key
FROM LeaveRequest lr
JOIN DimEmployee de ON lr.EmployeeID = de.EmployeeID
JOIN DimLeaveType dlt ON lr.LeaveTypeCode = dlt.LeaveTypeCode
JOIN DimStatus ds ON lr.StatusCode = ds.StatusCode
JOIN DimDate ddReq ON ddReq.FullDate = lr.RequestDate
JOIN DimDate ddStart ON ddStart.FullDate = lr.StartDate
JOIN DimDate ddEnd ON ddEnd.FullDate = lr.EndDate;


INSERT INTO FactLeaveDay
(LeaveRequestKey, EmployeeKey, LeaveTypeKey, StatusKey, DateKey, HoursTaken, DayCount)
SELECT fr.LeaveRequestKey,          -- surrogate key to keep referential integrity
       fr.EmployeeKey,
       fr.LeaveTypeKey,
       fr.StatusKey,
       dd.DateKey,
       ld.Hours,
       1
FROM LeaveDay ld
JOIN LeaveRequest lr ON ld.LeaveRequestID = lr.LeaveRequestID
JOIN FactLeaveRequest fr ON lr.LeaveRequestID = fr.SourceLeaveRequestID
JOIN DimDate dd ON dd.FullDate = ld.LeaveDate;





