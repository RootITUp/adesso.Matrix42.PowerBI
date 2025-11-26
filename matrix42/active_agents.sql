WITH ParticipatingRoles(TicketObjectId, ValidFrom, RoleId) AS (
    /* 1. HISTORY OF ROLE ASSIGNMENTS
     Reconstructs the timeline of which Role was assigned to a ticket and when.
     Parses XML 'SolutionParams' to find the Target Role ID.
     */
    SELECT
        [Expression-ObjectID],
        CreatedDate,
        -- Extract Role ID from XML for Ticket Creation
        TRY_CAST(SolutionParams AS XML).value(
            '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[1]',
            'uniqueidentifier'
        )
    FROM
        SPSActivityClassUnitOfWork AS CreateJournal
    WHERE
        ActivityAction = 1 -- Ticket Creation (Service Desk) [18 from mail does not expose recipient role!]
    UNION
    SELECT
        [Expression-ObjectID],
        CreatedDate,
        -- Extract Role ID from XML for Forwarding
        TRY_CAST(SolutionParams AS XML).value(
            '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[1]',
            'uniqueidentifier'
        )
    FROM
        SPSActivityClassUnitOfWork AS ForwardJournal
    WHERE
        ActivityAction = 3 -- Forward to Role
        OR ActivityAction = 30 -- Forward to Role & User
    UNION
    SELECT
        [Expression-ObjectID],
        CreatedDate,
        -- Extract New Role ID from XML for Role Changes (Node [2] is usually the 'New' value)
        TRY_CAST(SolutionParams AS XML).value(
            '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[2]',
            'uniqueidentifier'
        )
    FROM
        SPSActivityClassUnitOfWork AS ChangeJournal
    WHERE
        ActivityAction = 74 -- Change Assigned Role
    UNION
    SELECT
        [Expression-ObjectID],
        COALESCE(ClosedDate, GETDATE()),
        -- Fallback for active tickets
        RecipientRole
    FROM
        SPSActivityClassBase
    WHERE
        RecipientRole IS NOT NULL
),
AgentInteractions(
    TicketObjectId,
    CreatedDate,
    Creator
) AS (
    /*
     2. AGENT ACTIVITY
     Filters the journal for specific manual actions (Edits, Emails, Closures)
     performed by agents within the last 3 years.
     */
    SELECT
        Ticket.[Expression-ObjectID],
        Journal.CreatedDate,
        Journal.Creator
    FROM
        dbo.SPSActivityClassUnitOfWork AS Journal
        INNER JOIN dbo.SPSActivityClassBase AS Ticket ON Journal.[Expression-ObjectID] = Ticket.[Expression-ObjectID]
    WHERE
        Journal.Creator IS NOT NULL
        AND Journal.CreatedDate >= DATEADD(year, -3, GETDATE())
        AND Journal.ActivityAction IN (
            -- 4: Editing/Taking over a Ticket
            -- 7: Accepting a Ticket
            -- 8: Closing a Ticket
            -- 9, 33, 34: Merging a Ticket
            -- 11: Sending an E-mail
            -- 66: Ticket to Incident Transformation
            -- 67: Ticket to Service Request Transformation
            -- 68: Incident to Service Request Transformation
            -- 69: Service Request to Incident Transformation
            -- 82 + 83: Pausing a Ticket
            -- 84: Resolving a Ticket
            4,
            7,
            8,
            9,
            11,
            33,
            34,
            66,
            67,
            68,
            69,
            82,
            83,
            84
        )
        AND (
            Ticket.UsedInTypeSPSActivityTypeTicket IS NOT NULL
            OR Ticket.UsedInTypeSPSActivityTypeIncident IS NOT NULL
            OR Ticket.UsedInTypeSPSActivityTypeServiceRequest IS NOT NULL
        )
),
RankedRolesPerInteraction AS (
    /*
     3. MATCH INTERACTION TO ACTIVE ROLE
     Joins interactions with role history.
     Uses ROW_NUMBER to find the MOST RECENT role assignment relative to the interaction date.
     */
    SELECT
        AgentInteractions.TicketObjectId,
        AgentInteractions.CreatedDate AS InteractionDate,
        AgentInteractions.Creator,
        Roles.RoleId,
        -- Rank 1 is the most recent role assignment before the interaction happened
        ROW_NUMBER() OVER (
            PARTITION BY AgentInteractions.TicketObjectId,
            AgentInteractions.CreatedDate,
            AgentInteractions.Creator
            ORDER BY
                Roles.ValidFrom DESC
        ) AS RoleRank
    FROM
        AgentInteractions
        INNER JOIN ParticipatingRoles AS Roles ON AgentInteractions.TicketObjectId = Roles.TicketObjectId
    WHERE
        -- Ensure we only look at roles assigned BEFORE or AT the same time as the interaction
        Roles.ValidFrom <= AgentInteractions.CreatedDate
        AND -- This is an unlucky case where RoleId extraction might fail; we exclude NULLs here => Might falsify results slightly
        Roles.RoleId IS NOT NULL
)
/*
 4. FINAL OUTPUT
 Filters for Rank 1 to retrieve only the single active role for that specific interaction.
 */
SELECT
    CAST(InteractionDate AS date) AS [Date],
    Creator,
    RoleId,
    COUNT(*) AS InteractionCount
FROM
    RankedRolesPerInteraction
WHERE
    RoleRank = 1
GROUP BY
    CAST(InteractionDate AS date),
    Creator,
    RoleId
ORDER BY
    -- Optional: Sorts by date descending, then by Creator and RoleId to improve readability
    [Date] DESC,
    [Creator],
    [RoleId];