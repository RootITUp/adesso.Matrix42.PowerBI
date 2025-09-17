-- Check if the table already exists to prevent errors on re-running
IF OBJECT_ID('dbo.Ud_CalendarDateSeries', 'U') IS NOT NULL
BEGIN
    PRINT 'Table dbo.Ud_CalendarDateSeries already exists.';
END
ELSE
BEGIN
    SET DATEFIRST 1;
    PRINT 'Creating table dbo.Ud_CalendarDateSeries...';
    -- Create the table to hold the date dimension
    CREATE TABLE dbo.Ud_CalendarDateSeries (
        [Date] DATE NOT NULL,
        [Year] AS YEAR([Date]) PERSISTED,
        [Quarter] AS DATEPART(quarter, [Date]) PERSISTED,
        [Month] AS MONTH([Date]) PERSISTED,
        [DayOfYear] AS DATEPART(dayofyear, [Date]) PERSISTED,
        [WeekDayNumber] TINYINT NOT NULL,
        CONSTRAINT PK_Ud_CalendarDateSeries PRIMARY KEY CLUSTERED ([Date] ASC)
    );

    PRINT 'Populating Calendar table...';

    DECLARE @StartDate DATE = '2010-01-01';
    DECLARE @EndDate DATE = '2099-12-31';
    DECLARE @NumberOfDays INT = DATEDIFF(day, @StartDate, @EndDate);

    -- Use a recursive CTE to generate a sequence of numbers from 0 to @NumberOfDays.
    ;WITH NumberSequence(n) AS (
        SELECT 0
        UNION ALL
        SELECT n + 1 FROM NumberSequence WHERE n < @NumberOfDays
    )

    -- The PERSISTED columns will be calculated and stored automatically upon insert.
    INSERT INTO dbo.Ud_CalendarDateSeries ([Date], [WeekDayNumber])
    SELECT
        DATEADD(day, n, @StartDate),
        DATEPART(weekday, DATEADD(day, n, @StartDate))
    FROM
        NumberSequence
    OPTION (MAXRECURSION 0); -- Required to allow recursion beyond the default 100 level limit.

    PRINT 'Table dbo.Ud_CalendarDateSeries created and populated successfully.';
END;

-- Add a non-clustered index on WeekDayNumber for fast filtering and joins
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Ud_CalendarDateSeries_WeekDayNumber' AND object_id = OBJECT_ID('dbo.Ud_CalendarDateSeries'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Ud_CalendarDateSeries_WeekDayNumber
    ON dbo.Ud_CalendarDateSeries (WeekDayNumber);
    PRINT 'Created non-clustered index on WeekDayNumber.';
END;