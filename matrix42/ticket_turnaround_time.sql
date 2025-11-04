/*
 Ermittelt für jede SLA das zugehörige Zeitprofil und die Zeitzone.
 Wichtig: Es wird davon ausgegangen, dass eine SLA genau ein Zeitprofil hat.
 Sollte dies nicht der Fall sein, wird das mit der niedrigsten Objekt-ID ausgewählt.
 */
WITH ServiceLevel2TimeProfile(
    ID,
    TimeProfileObjectID,
    Country,
    TimeZoneId
) AS (
    SELECT
        ID,
        TimeProfileObjectID,
        Country,
        TimeZoneId
    FROM
        (
            SELECT
                serviceLevelAgreement.ID,
                serviceTimeProfile.[Expression-ObjectID] AS TimeProfileObjectID,
                serviceTimeProfile.Country,
                timeZonePickup.TimeZoneId,
                ROW_NUMBER() OVER(
                    PARTITION BY serviceLevelAgreement.ID
                    ORDER BY
                        serviceTimeProfile.[Expression-ObjectID] ASC
                ) as ranking
            FROM
                dbo.SVCServiceLevelAgreementClassBase AS serviceLevelAgreement
                INNER JOIN dbo.SVCServiceLevelAgreementClassServiceLevels AS slaLevel ON serviceLevelAgreement.[Expression-ObjectID] = slaLevel.[Expression-ObjectID]
                INNER JOIN dbo.SVMServiceTimeProfileClassBase AS serviceTimeProfile ON slaLevel.ServiceTimeProfile = serviceTimeProfile.ID
                INNER JOIN dbo.SPSLocationPickupTimeZone AS timeZonePickup ON serviceTimeProfile.TimeZone = timeZonePickup.Value
        ) AS RankedProfiles
    WHERE
        ranking = 1
),
/*
 Konvertiert die Erstellungs- und Schließzeiten der Tickets in die lokale Zeit der SLA.
 Nur Tickets mit SLA und geschlossenem Datum werden berücksichtigt.
 */
ActivitiesInLocalTime AS (
    SELECT
        ticket.ID,
        ticket.SLA,
        -- Convert start and end dates from UTC to the profile's local time zone.
        ticket.CreatedDate AT TIME ZONE 'UTC' AT TIME ZONE sla2Profile.TimeZoneId AS StartDateLocal,
        ticket.ClosedDate AT TIME ZONE 'UTC' AT TIME ZONE sla2Profile.TimeZoneId AS EndDateLocal
    FROM
        dbo.SPSActivityClassBase AS ticket
        INNER JOIN ServiceLevel2TimeProfile AS sla2Profile ON sla2Profile.ID = ticket.SLA
    WHERE
        ticket.SLA IS NOT NULL
        AND ticket.ClosedDate IS NOT NULL
        AND ticket.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window
),
/*
 Ermittelt für eine SLA die Arbeitszeiten pro Wochentag.
 Wichtige Annahme: Die Arbeitszeiten sind für alle Prioritäten identisch.
 Sollte diese Annahme nicht zutreffen, approximiert diese Abfrage die Arbeitszeiten mit der niedrigsten Startzeit und der höchsten Endzeit.
 */
ServiceLevel2WorkingHours AS (
    SELECT
        sla2Profile.ID,
        timeConfig.WeekDayNumber,
        CONVERT(
            TIME,
            DATEADD(minute, MIN(timeConfig.StartTime), 0)
        ) AS WorkingFrom,
        CONVERT(
            TIME,
            DATEADD(minute, MAX(timeConfig.EndTime), 0)
        ) AS WorkingUntil
    FROM
        ServiceLevel2TimeProfile AS sla2Profile
        INNER JOIN dbo.SLMConfigClassBase AS timeConfig ON sla2Profile.TimeProfileObjectID = timeConfig.[Expression-ObjectID]
    WHERE
        timeConfig.StartTime IS NOT NULL
        AND timeConfig.EndTime IS NOT NULL
    GROUP BY
        sla2Profile.ID,
        timeConfig.WeekDayNumber
)
SELECT
    ticket.ID,
    ticket.StartDateLocal,
    ticket.EndDateLocal,
    CAST(
        DATEDIFF(
            minute,
            ticket.StartDateLocal,
            ticket.EndDateLocal
        ) / 60.0 AS DECIMAL(10, 2)
    ) AS GrossTurnaroundHours,
    DATEDIFF(
        DAY,
        CAST(ticket.StartDateLocal AS DATE),
        CAST(ticket.EndDateLocal AS DATE)
    ) + 1 AS GrossTurnaroundDays,
    CAST(
        SUM(
            DATEDIFF(
                minute,
                -- Ermittelt die effektive Startzeit für den jeweiligen Tag
                CASE
                    WHEN calendar.Ud_Date = CAST(ticket.StartDateLocal AS DATE)
                    AND sla2h.WorkingFrom < CAST(ticket.StartDateLocal AS TIME) THEN CAST(ticket.StartDateLocal AS TIME)
                    ELSE sla2h.WorkingFrom
                END,
                -- Ermittelt die effektive Endzeit für den jeweiligen Tag
                CASE
                    WHEN calendar.Ud_Date = CAST(ticket.EndDateLocal AS DATE)
                    AND sla2h.WorkingUntil > CAST(ticket.EndDateLocal AS TIME) THEN CAST(ticket.EndDateLocal AS TIME)
                    ELSE sla2h.WorkingUntil
                END
            )
        ) / 60.0 AS DECIMAL(10, 2)
    ) AS NetTurnaroundHours,
    COUNT(calendar.Ud_Date) AS NetTurnaroundDays
FROM
    ActivitiesInLocalTime AS ticket
    /*
     Wichtig: Die Kalender-Tabelle muss ausreichend viele Daten enthalten.
     Dies wird über das Installations-Skript sichergestellt.
     */
    INNER JOIN dbo.Ud_CalendarDateSeries AS calendar ON calendar.Ud_Date BETWEEN CAST(ticket.StartDateLocal AS DATE)
    AND CAST(ticket.EndDateLocal AS DATE)
    INNER JOIN ServiceLevel2WorkingHours AS sla2h ON ticket.SLA = sla2h.ID
    AND calendar.Ud_WeekDayNumber = sla2h.WeekDayNumber
GROUP BY
    ticket.ID,
    ticket.StartDateLocal,
    ticket.EndDateLocal;