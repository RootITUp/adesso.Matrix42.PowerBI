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
        slaWithMinProfile.ID,
        slaWithMinProfile.TimeProfileObjectID,
        serviceTimeProfile.Country,
        timeZonePickup.TimeZoneId
    FROM
        (
            SELECT
                serviceLevelAgreement.ID,
                MIN(serviceTimeProfile.[Expression-ObjectID]) AS TimeProfileObjectID
            FROM
                dbo.SVCServiceLevelAgreementClassBase AS serviceLevelAgreement
                INNER JOIN dbo.SVCServiceLevelAgreementClassServiceLevels AS slaLevel ON serviceLevelAgreement.[Expression-ObjectID] = slaLevel.[Expression-ObjectID]
                INNER JOIN dbo.SVMServiceTimeProfileClassBase AS serviceTimeProfile ON slaLevel.ServiceTimeProfile = serviceTimeProfile.ID
            GROUP BY
                serviceLevelAgreement.ID
        ) AS slaWithMinProfile
        INNER JOIN dbo.SVMServiceTimeProfileClassBase AS serviceTimeProfile ON slaWithMinProfile.TimeProfileObjectID = serviceTimeProfile.[Expression-ObjectID]
        INNER JOIN dbo.SPSLocationPickupTimeZone AS timeZonePickup ON serviceTimeProfile.TimeZone = timeZonePickup.Value
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
),
/*
 Ermittelt für jedes Ticket und jeden Tag zwischen Start- und Enddatum die Arbeitszeiten.
 Für den ersten und letzten Tag werden die Arbeitszeiten entsprechend der Start- und Endzeit angepasst.
 */
Activites2WorkingHours AS (
    SELECT
        ticket.ID,
        ticket.StartDateLocal,
        ticket.EndDateLocal,
        calendar.[Date],
        CASE
            WHEN calendar.[Date] = CAST(ticket.StartDateLocal AS DATE) THEN CASE
                WHEN sla2Hours.WorkingFrom > CAST(ticket.StartDateLocal AS TIME) THEN sla2Hours.WorkingFrom
                ELSE CAST(ticket.StartDateLocal AS TIME)
            END
            ELSE sla2Hours.WorkingFrom
        END AS WorkingFrom,
        CASE
            WHEN calendar.[Date] = CAST(ticket.EndDateLocal AS DATE) THEN CASE
                WHEN sla2Hours.WorkingUntil < CAST(ticket.EndDateLocal AS TIME) THEN sla2Hours.WorkingUntil
                ELSE CAST(ticket.EndDateLocal AS TIME)
            END
            ELSE sla2Hours.WorkingUntil
        END AS WorkingUntil
    FROM
        ActivitiesInLocalTime AS ticket
        /*
         Wichtig: Die Kalender-Tabelle muss ausreichend viele Daten enthalten, um alle Tage zwischen dem frühesten Startdatum und dem spätesten Enddatum der Tickets abzudecken.
         Dies wird über das Installations-Skript sichergestellt.
         */
        INNER JOIN dbo.Ud_CalendarDateSeries AS calendar ON calendar.[Date] >= CAST(ticket.StartDateLocal AS DATE)
        AND calendar.[Date] <= CAST(ticket.EndDateLocal AS DATE)
        INNER JOIN ServiceLevel2WorkingHours AS sla2Hours ON sla2Hours.ID = ticket.SLA
        AND sla2Hours.WeekDayNumber = calendar.WeekDayNumber
)
SELECT
    ticket.ID,
    ticket.StartDateLocal,
    ticket.EndDateLocal,
    CAST(
        DATEDIFF(minute, ticket.StartDateLocal, ticket.EndDateLocal) / 60.0 AS DECIMAL(10, 2)
    ) AS GrossTurnaroundHours,
    DATEDIFF(
        DAY,
        CAST(ticket.StartDateLocal AS DATE),
        CAST(ticket.EndDateLocal AS DATE)
    ) + 1 AS GrossTurnaroundDays,
    CAST(
        SUM(
            DATEDIFF(minute, ticket.WorkingFrom, ticket.WorkingUntil)
        ) / 60.0 AS DECIMAL(10, 2)
    ) AS NetTurnaroundHours,
    COUNT(*) AS NetTurnaroundDays
FROM
    Activites2WorkingHours AS ticket
GROUP BY
    ticket.ID,
    ticket.StartDateLocal,
    ticket.EndDateLocal;