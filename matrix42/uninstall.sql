-- 1. Ensure a proper cleanup of the weekday index
IF EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Ud_CalendarDateSeries_WeekDayNumber' AND object_id = OBJECT_ID('dbo.Ud_CalendarDateSeries'))
BEGIN
    DROP INDEX IX_Ud_CalendarDateSeries_WeekDayNumber ON dbo.Ud_CalendarDateSeries;
    PRINT 'Dropped index IX_Ud_CalendarDateSeries_WeekDayNumber.';
END;

-- 2. Ensure a proper cleanup of the date index
IF EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Ud_CalendarDateSeries_Date' AND object_id = OBJECT_ID('dbo.Ud_CalendarDateSeries'))
BEGIN
    DROP INDEX IX_Ud_CalendarDateSeries_Date ON dbo.Ud_CalendarDateSeries;
    PRINT 'Dropped index IX_Ud_CalendarDateSeries_Date.';
END;