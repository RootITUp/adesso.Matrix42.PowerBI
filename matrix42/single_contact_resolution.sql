SELECT
    ticket.ID,
    -- ticket.[Expression-ObjectID] AS ObjectID, -- Uncomment if ObjectID is needed (Warning: performance impact)
    CASE
        WHEN ticketCommon.State = 204 THEN 1
        ELSE 0
    END AS IsClosed,
    /*
     Ein Ticket wurde im Single-Contact-Resolution-Verfahren gelöst, wenn:
     - das Ticket im Status "Geschlossen" ist UND
     - alle relevanten Aktionen (Annehmen und Schließen) historisch nur von einer einzigen Person durchgeführt wurden.
     */
    CASE
        WHEN ticketCommon.State = 204
        AND COUNT(DISTINCT journal.Creator) <= 1 THEN 1
        ELSE 0
    END AS IsSingleContactResolution
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
    LEFT OUTER JOIN dbo.SPSActivityClassUnitOfWork AS journal ON ticketCommon.[Expression-ObjectID] = journal.[Expression-ObjectID]
    AND (
        journal.ActivityAction = 7
        OR journal.ActivityAction = 8
    ) -- 7 = Accept / Annehmen, 8 = Close / Schließen
WHERE
    ticket.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window
GROUP BY
    -- ticket.[Expression-ObjectID], -- Uncomment if ObjectID is needed (Warning: performance impact)
    ticket.ID;