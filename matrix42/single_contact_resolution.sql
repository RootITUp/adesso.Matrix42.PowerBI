WITH ParticipatingUsers(TicketObjectId, UserId) AS (
    /* 1. HISTORY OF USER ASSIGNMENTS
     Reconstructs the timeline of which User was assigned to a ticket.
     Might parse XML 'SolutionParams' to find the Target User ID.
     */
    SELECT
        [Expression-ObjectID],
        Creator
    FROM
        dbo.SPSActivityClassUnitOfWork
    WHERE
        ActivityAction IN (7, 8, 11, 84) -- 7 = Accept / Annehmen, 8 = Close / Schließen, 11 = Sending Email, 84 = Resolving Ticket
    UNION
    SELECT
        [Expression-ObjectID],
        TRY_CAST(SolutionParams AS XML).value(
            '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[1]',
            'uniqueidentifier'
        )
    FROM
        dbo.SPSActivityClassUnitOfWork
    WHERE
        ActivityAction = 2 -- Forward to User
    UNION
    SELECT
        [Expression-ObjectID],
        TRY_CAST(SolutionParams AS XML).value(
            '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[2]',
            'uniqueidentifier'
        )
    FROM
        dbo.SPSActivityClassUnitOfWork
    WHERE
        ActivityAction = 30 -- Forward to Role & User
)
/*
 * 2. Final Output
 */
SELECT
    ticket.ID,
    CASE
        WHEN ticketCommon.State = 204 THEN 1
        ELSE 0
    END AS IsClosed,
    /*
     A ticket was closed using the Single Contact Resolution method if:
     - the ticket is in "Closed" status AND
     - all relevant actions (Accepting, Closing, ...) were historically performed by a single person only.
     */
    CASE
        WHEN ticketCommon.State = 204
        AND COUNT(DISTINCT ParticipatingUsers.UserId) <= 1 THEN 1
        ELSE 0
    END AS IsSingleContactResolution
FROM
    dbo.SPSActivityClassBase AS Ticket -- Join with a minimal set of common properties
    INNER JOIN (
        SELECT
            [Expression-ObjectID],
            State
        FROM
            dbo.SPSCommonClassBase
    ) AS ticketCommon ON ticket.[Expression-ObjectID] = ticketCommon.[Expression-ObjectID] -- Join with Participating Users to find ~all users involved with the ticket
    INNER JOIN ParticipatingUsers ON ticket.[Expression-ObjectID] = ParticipatingUsers.TicketObjectId
WHERE
    ticket.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window
    AND (
        Ticket.UsedInTypeSPSActivityTypeTicket IS NOT NULL
        OR Ticket.UsedInTypeSPSActivityTypeIncident IS NOT NULL
        OR Ticket.UsedInTypeSPSActivityTypeServiceRequest IS NOT NULL
    )
    AND ParticipatingUsers.UserId IS NOT NULL
GROUP BY
    ticketCommon.State,
    ticket.ID;