SELECT
    ticket.ID,
    ticket.ClosedDate,
    -- ticket.[Expression-ObjectID] AS ObjectID, -- Uncomment if ObjectID is needed (Warning: performance impact)
    /* 
     Die Bedingung ist wahr, wenn das Ticket im Status "Geschlossen" ist und
     es keine historischen Aktionen vom Typ "Weiterleitung an Rolle" gibt,
     welche an eine NICHT-First-Level-Support-Rolle weitergeleitet wurden. 
     */
    CASE
        WHEN COUNT(journal.[Expression-ObjectID]) = 0 THEN 1
        ELSE 0
    END AS IsFirstLevelSupportResolution
FROM
    dbo.SPSActivityClassBase AS ticket
    LEFT OUTER JOIN (
        SELECT
            [Expression-ObjectID]
        FROM
            dbo.SPSCommonClassBase
        WHERE
            /* Nur Tickets im Status "Geschlossen" */
            State = 204
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
                /* Liste der First-Level-Support-Rollen, als IDs der SPSScRoleClassBase */
                '74f788df-1d40-e911-c1a2-005056858d73'
            )
    ) AS journal ON ticketCommon.[Expression-ObjectID] = journal.[Expression-ObjectID]
GROUP BY
    -- ticket.[Expression-ObjectID], -- Uncomment if ObjectID is needed (Warning: performance impact)
    ticket.ID,
    ticket.ClosedDate;