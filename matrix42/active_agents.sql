SELECT
    /* 
     * Schneidet das volle Datum mit Uhrzeit (z.B. 2025-11-10 14:30:05)
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
    AND Journal.ActivityAction IN (
        -- 0: Commented is excluded because it is also possible via SSP UI without agent interaction
        -- 1: Create is included because it indicates agent activity based on creation from service desk
        1,
        -- 2: Forward to User is included as it indicates agent interaction based on forwarding from within service desk
        2,
        -- 3: Forward to Role is included as it indicates agent interaction based on forwarding from within service desk
        3,
        -- 4: Edit is included as it indicates agent interaction based on modifications from within service desk
        4,
        -- 5: Pause is included as it indicates agent interaction based on pausing from within service desk
        5,
        -- 6: Pause reminder is excluded because it is an automated reminder without direct agent interaction
        -- 7: Accept is included as it indicates agent interaction based on acceptance from within service desk
        7,
        -- 8: Close is included as it indicates agent interaction based on closing from within service desk
        8,
        -- 9: Merge is included as it indicates agent interaction based on merging from within service desk
        9,
        -- 10: Reopen is excluded because it can be triggered by system processes or SSP users without direct agent interaction
        -- 11: Send E-mail is included as it indicates agent interaction based on sending emails from within service desk
        11,
        -- 12: Postback is excluded because it is typically an automated response without direct agent interaction
        -- 13: Escalated is excluded because it is triggered by system rules without direct agent interaction
        -- 14: Email robot reply is excluded because it is an automated response without direct agent interaction
        -- 18: Email robot create is excluded because it is an automated creation without direct agent interaction
        -- 19: Create from SSP is excluded because it is initiated by SSP users without direct agent interaction
        -- 20: Withdraw is excluded because it is initiated by SSP users without direct agent interaction
        -- 21 - 65: Various automated or not support related actions are excluded
        -- 66: Ticket to Incident Transformation is included as it indicates agent interaction based on transformation from within service desk
        66,
        -- 67: Ticket to Service Request Transformation is included as it indicates agent interaction based on transformation from within service desk
        67,
        -- 68: Incident to Service Request Transformation is included as it indicates agent interaction based on transformation from within service desk
        68,
        -- 69: Service Request to Incident Transformation is included as it indicates agent interaction based on transformation from within service desk
        69,
        -- 70 - 83: Various types of changes and automated actions are excluded
        -- 84: Resolve is included as it indicates agent interaction based on resolving from within service desk
        84 -- 85 - 706: Multiple actions to different CIs (Tasks, Changes, Problems, ...), automated actions and queue based interactions excluded 
    )
GROUP BY
    CAST(Journal.CreatedDate AS date),
    Journal.Creator
ORDER BY
    -- Optional: Sortiert die Ergebnisse für bessere Lesbarkeit (neueste zuerst)
    [Date] DESC,
    [UserId];