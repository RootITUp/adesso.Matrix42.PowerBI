-- Drop the calendar table and its indexes
IF EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Ud_CalendarDateSeries_WeekDayNumber' AND object_id = OBJECT_ID('dbo.Ud_CalendarDateSeries'))
BEGIN
    DROP INDEX IX_Ud_CalendarDateSeries_WeekDayNumber ON dbo.Ud_CalendarDateSeries;
    PRINT 'Dropped index IX_Ud_CalendarDateSeries_WeekDayNumber.';
END;

IF OBJECT_ID('dbo.Ud_CalendarDateSeries', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.Ud_CalendarDateSeries;
    PRINT 'Dropped table dbo.Ud_CalendarDateSeries.';
END;