SELECT
    /* Schneidet das volle Datum mit Uhrzeit (z.B. 2025-11-10 14:30:05)
     * auf das reine Datum (z.B. 2025-11-10) zu.
     * Dies ermöglicht es uns, alle Interaktionen innerhalb desselben Kalendertages zu gruppieren.
     */
    CAST(Journal.CreatedDate AS date) AS [Date],
    -- Der Agent, der den Journaleintrag erstellt hat
    Journal.Creator AS [UserId],
    -- Zählt die Gesamtzahl der Einträge für diesen Agenten an diesem Tag
    COUNT(*) AS [JournalInteractions]
FROM
    [dbo].[SPSActivityClassUnitOfWork] AS Journal
WHERE
    Journal.Creator IS NOT NULL
    AND Journal.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window
GROUP BY
    CAST(Journal.CreatedDate AS date),
    Journal.Creator
ORDER BY
    -- Optional: Sortiert die Ergebnisse für bessere Lesbarkeit (neueste zuerst)
    [Date] DESC,
    [UserId];