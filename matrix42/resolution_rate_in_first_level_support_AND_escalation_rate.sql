WITH FirstLevelSupportTeams(RoleID) AS (
    SELECT
        role.ID
    FROM
        dbo.SPSScRoleClassBase AS role
    WHERE
        role.Ud_SupportRoleType = 10 -- First-Level-Support
)
SELECT
    ticket.ID,
    -- ticket.[Expression-ObjectID] AS ObjectID, -- Uncomment if ObjectID is needed (Warning: performance impact)
    CASE
        WHEN ticketCommon.State = 204 THEN 1
        ELSE 0
    END AS IsClosed,
    CASE
        WHEN COUNT(
            firstLevelTicketCreationJournal.[Expression-ObjectID]
        ) > 0 THEN 1
        ELSE 0
    END AS IsCreatedForFirstLevelSupport,
    /*
     Ein Ticket wurde im First-Level-Support gelöst, wenn:
     - das Ticket im Status "Geschlossen" ist UND
     - es keine historischen Aktionen vom Typ "Weiterleitung an Rolle" für eine NICHT-First-Level-Support-Rolle gibt UND
     - die initiale Bearbeitungsrolle eine First-Level-Support-Rolle war
     */
    CASE
        WHEN ticketCommon.State = 204
        AND COUNT(
            firstLevelTicketCreationJournal.[Expression-ObjectID]
        ) > 0
        AND COUNT(
            secondLevelTicketForwardJournal.[Expression-ObjectID]
        ) = 0 THEN 1
        ELSE 0
    END AS IsFirstLevelSupportResolution,
    /*
     Ein Ticket wurde eskaliert, wenn:
     - es mind. eine historischen Aktionen vom Typ "Weiterleitung an Rolle" für eine NICHT-First-Level-Support-Rolle gibt UND
     - die initiale Bearbeitungsrolle eine First-Level-Support-Rolle war
     */
    CASE
        WHEN COUNT(
            secondLevelTicketForwardJournal.[Expression-ObjectID]
        ) > 0
        AND COUNT(
            firstLevelTicketCreationJournal.[Expression-ObjectID]
        ) > 0 THEN 1
        ELSE 0
    END AS IsEscalated
FROM
    dbo.SPSActivityClassBase AS ticket
    /*
     Verknüpfung mit den Ticket-Metadaten, um den aktuellen Status zu erhalten.
     */
    INNER JOIN (
        SELECT
            [Expression-ObjectID],
            State
        FROM
            dbo.SPSCommonClassBase
    ) AS ticketCommon ON ticket.[Expression-ObjectID] = ticketCommon.[Expression-ObjectID]
    /* 
     Verknüpfung mit den Journal-Einträgen, um die Ticket-Erstellungs-Aktion zu identifizieren.
     Ziel ist es zu prüfen, ob das Ticket ursprünglich für den First-Level-Support erstellt wurde.
     */
    LEFT OUTER JOIN (
        SELECT
            [Expression-ObjectID]
        FROM
            dbo.SPSActivityClassUnitOfWork
        WHERE
            /* Nur Journal-Einträge für "Erstellt"" */
            ActivityAction = 1
            AND
            /* Nur Fragmente, WELCHE der SPSScRoleClassBase einer First-Level-Support-Rolle entsprechen */
            CAST(SolutionParams AS XML).value(
                '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[1]',
                'uniqueidentifier'
            ) IN (
                SELECT
                    RoleID
                FROM
                    FirstLevelSupportTeams
            )
    ) AS firstLevelTicketCreationJournal ON ticketCommon.[Expression-ObjectID] = firstLevelTicketCreationJournal.[Expression-ObjectID]
    /*
     Verknüpfung mit den Journal-Einträgen, um Weiterleitungs-Aktionen zu identifizieren.
     Ziel ist es zu prüfen, ob das Ticket an eine NICHT-First-Level-Support-Rolle weitergeleitet (eskaliert) wurde.
     */
    LEFT OUTER JOIN (
        SELECT
            [Expression-ObjectID]
        FROM
            dbo.SPSActivityClassUnitOfWork
        WHERE
            /* Nur Journal-Einträge für "Weiterleitung an Rolle" */
            ActivityAction = 3
            AND
            /* Nur Fragmente, welche NICHT der SPSScRoleClassBase einer First-Level-Support-Rolle entsprechen */
            CAST(SolutionParams AS XML).value(
                '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[1]',
                'uniqueidentifier'
            ) NOT IN (
                SELECT
                    RoleID
                FROM
                    FirstLevelSupportTeams
            )
    ) AS secondLevelTicketForwardJournal ON ticketCommon.[Expression-ObjectID] = secondLevelTicketForwardJournal.[Expression-ObjectID]
WHERE
    ticket.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window
GROUP BY
    -- ticket.[Expression-ObjectID], -- Uncomment if ObjectID is needed (Warning: performance impact)
    ticketCommon.State,
    ticket.ID;