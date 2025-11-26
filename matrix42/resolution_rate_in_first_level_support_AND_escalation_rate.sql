WITH FirstLevelSupportTeams(RoleId) AS (
    /* 
     1. First-Level-Support Roles
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
    /* 
     2. HISTORY OF ROLE ASSIGNMENTS
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
        ActivityAction = 1
        OR ActivityAction = 19 -- Ticket Creation (Service Desk/SSP) [18 from mail does not expose recipient role!]
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
),
PaddedParticipatingRoles(TicketObjectId, ValidFrom, RoleId) AS (
    /*
     3. PAD ROLE HISTORY
     Adds a fallback entry for tickets that never had their role changed and no creation journal exists.
     Uses the Ticket's RecipientRole as the initial role assignment date.
     */
    SELECT
        [Expression-ObjectID],
        COALESCE(
            MAX(ParticipatingRoles.ValidFrom),
            Ticket.CreatedDate
        ),
        Ticket.RecipientRole
    FROM
        ParticipatingRoles
        INNER JOIN SPSActivityClassBase AS Ticket ON ParticipatingRoles.TicketObjectId = Ticket.[Expression-ObjectID]
    WHERE
        Ticket.RecipientRole IS NOT NULL
    GROUP BY
        [Expression-ObjectID],
        Ticket.CreatedDate,
        Ticket.RecipientRole
),
RankedParticipatingRoles(TicketObjectId, RoleId, RoleAssignmentRank) AS (
    /* 
     4. RANKED ROLE ASSIGNMENTS
     Assigns a rank to each Role assignment per Ticket based on the ValidFrom date.
     This allows identifying the first assigned Role and any subsequent Role changes.
     */
    SELECT
        TicketObjectId,
        ParticipatingRoles.RoleId,
        ROW_NUMBER() OVER (
            PARTITION BY TicketObjectId
            ORDER BY
                ValidFrom ASC
        ) AS RoleAssignmentRank
    FROM
        ParticipatingRoles
        LEFT OUTER JOIN FirstLevelSupportTeams ON ParticipatingRoles.RoleId = FirstLevelSupportTeams.RoleId
    WHERE
        /*
         We have the problem, that sometimes we have no knowledge about the initial role assigned to a ticket (NULL) or a default role (interpreted as Dispatcher) is assigned. 
         We want to ignore these roles when determining if a ticket started in First-Level-Support or was escalated.
         */
        ParticipatingRoles.RoleId IS NOT NULL
        AND (
            FirstLevelSupportTeams.RoleId IS NOT NULL
            OR ParticipatingRoles.RoleId NOT IN (
                SELECT
                    DefaultResponsibleRoleTickets
                FROM
                    SPSGlobalConfigurationClassServiceDesk
                UNION
                SELECT
                    DefaultResponsibleRoleIncidents
                FROM
                    SPSGlobalConfigurationClassServiceDesk
                UNION
                SELECT
                    DefaultResponsibleRoleServiceRequests
                FROM
                    SPSGlobalConfigurationClassServiceDesk
            )
        )
),
TicketStatistics AS (
    /* 
     5. AGGREGATION
     Determine FLS status and Escalation status before joining back to main ticket data.
     */
    SELECT
        RankedParticipatingRoles.TicketObjectId,
        /*
         A ticket was created for First-Level-Support if:
         - the first "relevant" role assigned to the ticket is a First-Level-Support role
         */
        MAX(
            CASE
                WHEN RankedParticipatingRoles.RoleAssignmentRank = 1
                AND FirstLevelSupportTeams.RoleId IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS StartedInFLS,
        -- Check if ANY role assigned in the history was NOT a First-Level-Support role
        MAX(
            CASE
                WHEN FirstLevelSupportTeams.RoleId IS NULL THEN 1
                ELSE 0
            END
        ) AS HasNonFLSHistory
    FROM
        RankedParticipatingRoles
        LEFT JOIN FirstLevelSupportTeams ON RankedParticipatingRoles.RoleId = FirstLevelSupportTeams.RoleId
    GROUP BY
        RankedParticipatingRoles.TicketObjectId
)
/*
 * 6. Final Output
 */
SELECT
    Ticket.ID,
    CASE
        WHEN TicketCommon.State = 204 THEN 1
        ELSE 0
    END AS IsClosed,
    -- Metric 1: Created for First-Level-Support
    Stats.StartedInFLS AS IsCreatedForFirstLevelSupport,
    -- Metric 2: Resolved in First-Level-Support (No Escalation)
    CASE
        WHEN Stats.StartedInFLS = 1
        AND Stats.HasNonFLSHistory = 0
        AND TicketCommon.State = 204 THEN 1
        ELSE 0
    END AS IsFirstLevelSupportResolution,
    -- Metric 3: Escalated from First-Level-Support
    CASE
        WHEN Stats.StartedInFLS = 1
        AND Stats.HasNonFLSHistory = 1 THEN 1
        ELSE 0
    END AS IsEscalated
FROM
    dbo.SPSActivityClassBase AS Ticket
    INNER JOIN (
        SELECT
            [Expression-ObjectID],
            State
        FROM
            dbo.SPSCommonClassBase
    ) AS TicketCommon ON Ticket.[Expression-ObjectID] = TicketCommon.[Expression-ObjectID]
    INNER JOIN TicketStatistics AS Stats ON Ticket.[Expression-ObjectID] = Stats.TicketObjectId
WHERE
    Ticket.CreatedDate >= DATEADD(year, -3, GETDATE()) -- 3 year sliding window    
    AND (
        Ticket.UsedInTypeSPSActivityTypeTicket IS NOT NULL
        OR Ticket.UsedInTypeSPSActivityTypeIncident IS NOT NULL
        OR Ticket.UsedInTypeSPSActivityTypeServiceRequest IS NOT NULL
    )