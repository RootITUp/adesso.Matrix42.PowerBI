-- 1. Populate the Calendar table with dates from 2010-01-01 to 2099-12-31
BEGIN TRANSACTION;
    SET DATEFIRST 1;
    -- Clear any existing data (if any)
    PRINT 'Clearing Calendar table...';
    DELETE FROM dbo.Ud_CalendarDateSeries;

    -- Populate the table with dates from 2010-01-01 to 2099-12-31
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

    INSERT INTO dbo.Ud_CalendarDateSeries ([Value], [Ud_Date], [Ud_WeekDayNumber])
    SELECT
        n,
        DATEADD(day, n, @StartDate),
        DATEPART(weekday, DATEADD(day, n, @StartDate))
    FROM
        NumberSequence
    OPTION (MAXRECURSION 0); -- Required to allow recursion beyond the default 100 level limit.

    PRINT 'Table dbo.Ud_CalendarDateSeries populated successfully.';
COMMIT;

-- 2. Add a non-clustered index on WeekDayNumber for fast filtering and joins
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Ud_CalendarDateSeries_WeekDayNumber' AND object_id = OBJECT_ID('dbo.Ud_CalendarDateSeries'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Ud_CalendarDateSeries_WeekDayNumber
    ON dbo.Ud_CalendarDateSeries (Ud_WeekDayNumber);
    PRINT 'Created non-clustered index on WeekDayNumber.';
END;

-- 3. Add a non-clustered index on Date for fast filtering and joins
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Ud_CalendarDateSeries_Date' AND object_id = OBJECT_ID('dbo.Ud_CalendarDateSeries'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Ud_CalendarDateSeries_Date
    ON dbo.Ud_CalendarDateSeries (Ud_Date);
    PRINT 'Created non-clustered index on Date.';
END;
