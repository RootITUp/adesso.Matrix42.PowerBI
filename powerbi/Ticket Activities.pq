let
    Requests = fxGetDataQuery(
        "42a841de-e5f4-c654-e632-08ddfc1ad1bc",
        RangeStart,
        RangeEnd       
    ),
    #"Changed Type" = Table.TransformColumnTypes(Requests,{{"Sys-Entity", type text}, {"TicketNumber", type text}, {"LastChangeDate", type datetimezone}, {"ClosedDate", type datetimezone}, {"CreatedDate", type datetimezone}, {"EscalatedDate", type datetimezone}, {"SolutionTimeEscalated", type logical}, {"ReactionTimeEscalated", type logical}, {"Ud_SolutionTimeEscalatedInRole", type text}, {"Ud_SolutionTimeEscalatedInRole_Value", type text}, {"SLA", type text}, {"SLA_Value", type text}, {"SolutionPoint", type datetimezone}, {"Category", type text}, {"Category_Value", type text}, {"RecipientRole", type text}, {"RecipientRole_Value", type text}, {"Creator", type text}, {"Creator_Value", type text}, {"Initiator", type text}, {"Initiator_Value", type text}, {"Recipient", type text}, {"Recipient_Value", type text}, {"InitiatorCompany", type text}, {"Id", type text}, {"Sys-ObjectId", type text}, {"Sys-DisplayName", type text}, {"Sys-Name", type text}, {"Sys-TimeStamp", type text}, {"State", type text}, {"State_Value", Int64.Type}, {"Sys-EntityState", Int64.Type}}),
    // Added a new step to inject the current datetime
    #"Added Timestamp" = Table.AddColumn(#"Changed Type", "RefreshTimestampUTC", each DateTimeZone.UtcNow(), type datetimezone)
in
    #"Added Timestamp"