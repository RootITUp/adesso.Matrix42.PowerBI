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
    /* 
     Die Bedingung ist wahr, wenn das Ticket im Status "Geschlossen" ist und
     es keine historischen Aktionen vom Typ "Weiterleitung an Rolle" gibt,
     welche an eine NICHT-First-Level-Support-Rolle weitergeleitet wurden. 
     */
    CASE
        WHEN ticketCommon.State = 204
        AND COUNT(journal.[Expression-ObjectID]) = 0 THEN 1
        ELSE 0
    END AS IsFirstLevelSupportResolution,
    /*
     Die Bedingung ist wahr, wenn es mindestens eine historische Aktion vom Typ "Weiterleitung an Rolle" gibt,
     welche an eine NICHT-First-Level-Support-Rolle weitergeleitet wurde. 
     */
    CASE
        WHEN COUNT(journal.[Expression-ObjectID]) > 0 THEN 1
        ELSE 0
    END AS IsEscalated
FROM
    dbo.SPSActivityClassBase AS ticket
    LEFT OUTER JOIN (
        SELECT
            [Expression-ObjectID],
            State
        FROM
            dbo.SPSCommonClassBase
    ) AS ticketCommon ON ticket.[Expression-ObjectID] = ticketCommon.[Expression-ObjectID]
    /* Wir erzeugen Zeilen, in welcher entweder (NULL) oder die KPI verletzende Weiterleitungs-Aktion vorkommt. */
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
    ) AS journal ON ticketCommon.[Expression-ObjectID] = journal.[Expression-ObjectID]
WHERE
    ticket.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window
GROUP BY
    -- ticket.[Expression-ObjectID], -- Uncomment if ObjectID is needed (Warning: performance impact)
    ticketCommon.State,
    ticket.ID;