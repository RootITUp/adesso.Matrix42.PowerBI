WITH ParticipatingRoles(TicketObjectId, ValidFrom, RoleId) AS (
    SELECT
        [Expression-ObjectID],
        CreatedDate,
        CAST(SolutionParams AS XML).value(
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
        CAST(SolutionParams AS XML).value(
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
        CAST(SolutionParams AS XML).value(
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
)
SELECT
    *
FROM
    ParticipatingRoles
ORDER BY
    TicketObjectId,
    ValidFrom ASC;