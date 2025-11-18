/*
 Ermittelt für jede SLA:
 - die Priorität des Service Levels (mehrere pro SLA)
 - das zugehörige Zeitprofil und die Zeitzone
 */
WITH ServiceLevel2TimeProfilesAndPriorities(
    ID,
    Priority,
    TimeProfileObjectID,
    TimeZoneId
) AS (
    SELECT
        sla.ID,
        slaLevel.Priority,
        serviceTimeProfile.[Expression-ObjectID],
        timeZonePickup.TimeZoneId
    FROM
        dbo.SVCServiceLevelAgreementClassBase AS sla
        INNER JOIN dbo.SVCServiceLevelAgreementClassServiceLevels AS slaLevel ON sla.[Expression-ObjectID] = slaLevel.[Expression-ObjectID]
        INNER JOIN dbo.SVMServiceTimeProfileClassBase AS serviceTimeProfile ON slaLevel.ServiceTimeProfile = serviceTimeProfile.ID
        INNER JOIN dbo.SPSLocationPickupTimeZone AS timeZonePickup ON serviceTimeProfile.TimeZone = timeZonePickup.Value
),
/*
 Ermittelt für alle Tickets mit SLA die Start- und Endzeitpunkte in der lokalen Zeitzone des zugehörigen Zeitprofils.
 */
Activities2LocalTime(
    ID,
    TimeProfileObjectID,
    StartDateLocal,
    EndDateLocal
) AS(
    SELECT
        ticket.ID,
        sla2Profile.TimeProfileObjectID,
        -- Convert start and end dates from UTC to the profile's local time zone.
        ticket.CreatedDate AT TIME ZONE 'UTC' AT TIME ZONE sla2Profile.TimeZoneId AS StartDateLocal,
        ticket.ClosedDate AT TIME ZONE 'UTC' AT TIME ZONE sla2Profile.TimeZoneId AS EndDateLocal
    FROM
        dbo.SPSActivityClassBase AS ticket
        INNER JOIN ServiceLevel2TimeProfilesAndPriorities AS sla2Profile ON sla2Profile.ID = ticket.SLA
        AND sla2Profile.Priority = ticket.Priority
    WHERE
        ticket.SLA IS NOT NULL
        AND ticket.ClosedDate IS NOT NULL
        AND ticket.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window
),
/*
 Ermittelt die Arbeitszeiten pro Wochentag für jedes Zeitprofil.
 */
TimeProfile2WorkingHours(
    TimeProfileObjectID,
    WeekDayNumber,
    WorkingFrom,
    WorkingUntil
) AS (
    SELECT
        timeProfile.[Expression-ObjectID],
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
        SVMServiceTimeProfileClassBase AS timeProfile
        INNER JOIN dbo.SLMConfigClassBase AS timeConfig ON timeProfile.[Expression-ObjectID] = timeConfig.[Expression-ObjectID]
    WHERE
        timeConfig.StartTime IS NOT NULL
        AND timeConfig.EndTime IS NOT NULL
    GROUP BY
        timeProfile.[Expression-ObjectID],
        timeConfig.WeekDayNumber
)
SELECT
    LocalTicketWorkingTimes.ID,
    LocalTicketWorkingTimes.StartDateLocal,
    LocalTicketWorkingTimes.EndDateLocal,
    /*CAST(
     DATEDIFF(
     minute,
     LocalTicketWorkingTimes.StartDateLocal,
     LocalTicketWorkingTimes.EndDateLocal
     ) / 60.0 AS DECIMAL(10, 2)
     ) AS GrossTurnaroundHours,*/
    /*DATEDIFF(
     DAY,
     CAST(LocalTicketWorkingTimes.StartDateLocal AS DATE),
     CAST(LocalTicketWorkingTimes.EndDateLocal AS DATE)
     ) + 1 AS GrossTurnaroundDays,*/
    CAST(
        SUM(
            CASE
                WHEN LocalTicketWorkingTimes.EffectiveStartTime IS NOT NULL
                AND LocalTicketWorkingTimes.EffectiveEndTime IS NOT NULL THEN DATEDIFF(
                    minute,
                    LocalTicketWorkingTimes.EffectiveStartTime,
                    LocalTicketWorkingTimes.EffectiveEndTime
                )
                ELSE 0
            END
        ) / 60.0 AS DECIMAL(10, 2)
    ) AS NetTurnaroundHours,
    SUM (
        CASE
            /*
             Zählt nur Tage, an denen definierte Arbeitszeiten vorliegen.
             */
            WHEN LocalTicketWorkingTimes.EffectiveStartTime IS NOT NULL
            AND LocalTicketWorkingTimes.EffectiveEndTime IS NOT NULL THEN 1
            ELSE 0
        END
    ) AS NetTurnaroundDays
FROM
    (
        SELECT
            localTicket.ID,
            localTicket.StartDateLocal,
            localTicket.EndDateLocal,
            calendar.Ud_Date,
            -- Ermittelt die effektive Startzeit für den jeweiligen Tag
            /*
             a) Sollte für das Zeitprofil keine Arbeitszeiten definiert sein, wird NULL zurückgegeben.
             b) Am Tag des Ticket-Starts: Es wird die spätere Zeit von Arbeitsbeginn und Ticket-Startzeit verwendet, maximal aber bis Arbeitsende.
             c) An allen anderen Tagen: Beginn der Arbeitszeit.
             */
            CASE
                WHEN profile2Hours.WorkingFrom IS NULL THEN NULL
                ELSE CASE
                    WHEN calendar.Ud_Date = CAST(localTicket.StartDateLocal AS DATE) THEN CASE
                        WHEN profile2Hours.WorkingFrom > CAST(localTicket.StartDateLocal AS TIME) THEN profile2Hours.WorkingFrom
                        ELSE CASE
                            WHEN profile2Hours.WorkingUntil < CAST(localTicket.StartDateLocal AS TIME) THEN profile2Hours.WorkingUntil
                            ELSE CAST(localTicket.StartDateLocal AS TIME)
                        END
                    END
                    ELSE profile2Hours.WorkingFrom
                END
            END AS EffectiveStartTime,
            -- Ermittelt die effektive Endzeit für den jeweiligen Tag
            CASE
                /*
                 a) Sollte für das Zeitprofil keine Arbeitszeiten definiert sein, wird NULL zurückgegeben.
                 b) Am Tag des Ticket-Endes: Es wird die frühere Zeit von Arbeitsende und Ticket-Endzeit verwendet, frühestens aber ab Arbeitsbeginn.
                 c) An allen anderen Tagen: Ende der Arbeitszeit.
                 */
                WHEN profile2Hours.WorkingUntil IS NULL THEN NULL
                ELSE CASE
                    WHEN calendar.Ud_Date = CAST(localTicket.EndDateLocal AS DATE) THEN CASE
                        WHEN profile2Hours.WorkingUntil < CAST(localTicket.EndDateLocal AS TIME) THEN profile2Hours.WorkingUntil
                        ELSE CASE
                            WHEN profile2Hours.WorkingFrom > CAST(localTicket.EndDateLocal AS TIME) THEN profile2Hours.WorkingFrom
                            ELSE CAST(localTicket.EndDateLocal AS TIME)
                        END
                    END
                    ELSE profile2Hours.WorkingUntil
                END
            END AS EffectiveEndTime
        FROM
            Activities2LocalTime AS localTicket
            /*
             Wichtig: Die Kalender-Tabelle muss ausreichend viele Daten enthalten.
             Dies wird über das Installations-Skript sichergestellt.
             */
            INNER JOIN dbo.Ud_CalendarDateSeries AS calendar ON calendar.Ud_Date BETWEEN CAST(localTicket.StartDateLocal AS DATE)
            AND CAST(localTicket.EndDateLocal AS DATE)
            /*
             Die Verknüpfung mit den Arbeitszeiten des Zeitprofils ermöglicht die Berechnung der Netto-Bearbeitungszeit.
             Achtung, es kann passieren, dass für bestimmte Tage keine Arbeitszeiten definiert sind (z.B. Wochenenden oder Feiertage).
             In diesem Fall werden diese Tage automatisch bei der Netto-Berechnung ausgeschlossen. 
             */
            LEFT OUTER JOIN TimeProfile2WorkingHours AS profile2Hours ON localTicket.TimeProfileObjectID = profile2Hours.TimeProfileObjectID
            AND calendar.Ud_WeekDayNumber = profile2Hours.WeekDayNumber
    ) AS LocalTicketWorkingTimes
GROUP BY
    LocalTicketWorkingTimes.ID,
    LocalTicketWorkingTimes.StartDateLocal,
    LocalTicketWorkingTimes.EndDateLocal;