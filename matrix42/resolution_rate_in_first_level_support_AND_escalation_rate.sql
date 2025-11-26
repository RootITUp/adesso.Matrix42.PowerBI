WITH FirstLevelSupportTeams(RoleId) AS (
    /* 1. First-Level-Support Roles
     Identifies all Roles classified as First-Level-Support.
     These Role IDs are used to determine if a ticket was created for First-Level-Support
     and whether it was escalated to higher support levels.
     */
    SELECT
        role.ID
    FROM
        dbo.SPSScRoleClassBase AS role
    WHERE
        role.Ud_SupportRoleType = 10 -- First-Level-Support
),
ParticipatingRoles(TicketObjectId, ValidFrom, RoleId) AS (
    /* 2. HISTORY OF ROLE ASSIGNMENTS
     Reconstructs the timeline of which Role was assigned to a ticket and when.
     Parses XML 'SolutionParams' to find the Target Role ID.
     */
    SELECT
        [Expression-ObjectID],
        CreatedDate,
        TRY_CAST(SolutionParams AS XML).value(
            '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[1]',
            'uniqueidentifier'
        )
    FROM
        SPSActivityClassUnitOfWork AS CreateJournal
    WHERE
        ActivityAction = 1 -- Ticket Creation in Service Desk
        OR ActivityAction = 18 -- Ticket Creation in Self Service Portal
    UNION
    SELECT
        [Expression-ObjectID],
        CreatedDate,
        TRY_CAST(SolutionParams AS XML).value(
            '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[1]',
            'uniqueidentifier'
        )
    FROM
        SPSActivityClassUnitOfWork AS ForwardJournal
    WHERE
        ActivityAction = 3 -- Forward to Role
        OR ActivityAction = 30 -- Forward to Role AND User
    UNION
    SELECT
        [Expression-ObjectID],
        CreatedDate,
        TRY_CAST(SolutionParams AS XML).value(
            '(/parameters/JournalEntryParameterBase/FragmentIds/fragmentId)[2]',
            'uniqueidentifier'
        )
    FROM
        SPSActivityClassUnitOfWork AS ChangeJournal
    WHERE
        ActivityAction = 74 -- Change Assigned Role From Old -> New
    UNION
    SELECT
        [Expression-ObjectID],
        COALESCE(ClosedDate, GETDATE()),
        RecipientRole
    FROM
        SPSActivityClassBase
    WHERE
        RecipientRole IS NOT NULL
),
RankedParticipatingRoles(TicketObjectId, RoleId, RoleAssignmentRank) AS (
    /* 3. RANKED ROLE ASSIGNMENTS
     Assigns a rank to each Role assignment per Ticket based on the ValidFrom date.
     This allows identifying the first assigned Role and any subsequent Role changes.
     */
    SELECT
        TicketObjectId,
        RoleId,
        ROW_NUMBER() OVER (
            PARTITION BY TicketObjectId
            ORDER BY
                ValidFrom ASC
        ) AS RoleAssignmentRank
    FROM
        ParticipatingRoles
    WHERE
        RoleId IS NOT NULL -- this ASSUMES that for activity=18 (mail) a dispatch to a role happens BEFORE any work is performed!
),
SELECT
    ticket.ID,
    CASE
        WHEN ticketCommon.State = 204 THEN 1
        ELSE 0
    END AS IsClosed,
    /*
     A ticket was created for First-Level-Support if:
     - the first "relevant" role assigned to the ticket is a First-Level-Support role
     */
    /*
     A ticket was closed without escalation if:
     - the ticket is in "Closed" status AND
     - there are NO non-First-Level-Support role assignments in the ticket history
     - the first "relevant" role assigned to the ticket is a First-Level-Support role
     */
    /*
     A ticket was escalated if:
     - there is at least one non-First-Level-Support role assignment in the ticket history
     - the first "relevant" role assigned to the ticket is a First-Level-Support role
     */
FROM
    dbo.SPSActivityClassBase AS Ticket
    INNER JOIN (
        SELECT
            [Expression-ObjectID],
            State
        FROM
            dbo.SPSCommonClassBase
    ) AS TicketCommon ON Ticket.[Expression-ObjectID] = TicketCommon.[Expression-ObjectID] --Join with a minimal set of common properties 
    INNER JOIN RankedParticipatingRoles ON Ticket.[Expression-ObjectID] = RankedParticipatingRoles.TicketObjectId -- Join with Participating Users to find ~all users involved with the ticket
    LEFT OUTER JOIN FirstLevelSupportTeams ON ParticipatingRoles.RoleId = FirstLevelSupportTeams.RoleId
WHERE
    Ticket.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window    
    AND (
        Ticket.UsedInTypeSPSActivityTypeTicket IS NOT NULL
        OR Ticket.UsedInTypeSPSActivityTypeIncident IS NOT NULL
        OR Ticket.UsedInTypeSPSActivityTypeServiceRequest IS NOT NULL
    )
GROUP BY
    TicketCommon.State,
    Ticket.ID;