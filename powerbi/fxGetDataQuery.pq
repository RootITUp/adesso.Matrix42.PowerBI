(dataQueryId as text, startDate as datetime, endDate as datetime) as table =>
let
		// =======================================================================
    	// == DOCUMENTATION ======================================================
    	// =======================================================================
   		/*
        	Description:
            	Fetches data from a paginated API endpoint for a specific data query and date range.
            	This function is designed for use with Power BI's incremental refresh feature.

        	Parameters:
            	- dataQueryId: The unique identifier for the data query to be executed.
            	- startDate: The start of the date range (inclusive), typically provided by incremental refresh.
            	- endDate: The end of the date range (exclusive), typically provided by incremental refresh.
        
        	Returns:
            	A table containing the combined and expanded data from all pages of the API response.
            	Includes diagnostic metadata about the execution.
    	*/

    	// =======================================================================
    	// == CONFIGURATION ======================================================
    	// =======================================================================

    	// Define how many records to fetch per API call.
    	// Choose a high number, but be mindful of API limits.
    	pageSize = 10000,

    	// Set the API timeout. Increase if API calls are slow.
    	apiTimeout = #duration(0, 0, 5, 0), // 5 minutes

    	// The page number to start from (0 for zero-based, 1 for one-based APIs).
    	startPage = 0,

    	// =======================================================================
    	// == INCREMENTAL REFRESH BODY (No changes here) =========================
    	// =======================================================================

    	// 1. Format dates to UTC ISO 8601 text format ("o").
    	startDateText = DateTimeZone.ToText(DateTime.AddZone(startDate, 0), "o"),
    	endDateText = DateTimeZone.ToText(DateTime.AddZone(endDate, 0), "o"),

		// 2. Define the JSON body for the date filter.
    	bodyAsRecord = [
        	LogicalOperator = 2, // 2 = OR
        	Conditions = {
            		[
                		Operator = 14, // NOT SET
                		Property = "ClosedDate",
                		Value = {}
            		],
            		[
                		Operator = 12, // BETWEEN
                		Property = "LastChangeDate",
                		Value = {startDateText, endDateText}
            		]
        	},
        	Groups = {}
    	],

		// 3. Convert the record into a JSON text string.
    	jsonBody = Text.FromBinary(Json.FromValue(bodyAsRecord)),

		// 4. Get the authorization header
		authHeader = fxGetAuthHeader(),

		// =======================================================================
    	// == PAGINATION LOGIC ===================================================
    	// =======================================================================
		// 5. Create a function that gets a single page of data.
		GetPage = (pageNumber as number) as table =>
        	let
        			// Attempt to fetch and process the data for the given page.
            		apiResponse = try Json.Document(
                		Web.Contents(
                    			BaseUrl,
                    			[
                        			RelativePath = "/api/DataQuery/" & dataQueryId,
                        			Headers = [
                            				#"Content-Type" = "application/json",
                            				Authorization = authHeader
                        			],
                        			// Add the pagination parameters to the URL query
                        			Query = [
                            				page = Text.From(pageNumber),
                           	 				pageSize = Text.From(pageSize)
                        			],
                        			Timeout = apiTimeout,
                        			Content = Text.ToBinary(jsonBody)
                    			]
               			)
            		),

					// If the API call fails, log the error and return an empty list.
        			// This prevents the entire refresh from failing on a single page error.
        			resultList = if apiResponse[HasError] then
            		(
                		Diagnostics.Trace(
							TraceLevel.Error,
							"API call failed for page " & Text.From(pageNumber) & ". Error: " & apiResponse[Error][Message],
							{} // Return an empty list on error.
						)
            		)
   			 		else
            			// If the call succeeded, extract the list of records.
						apiResponse[Value],

        			// Convert the final list of records to a table.
            		resultTable = Table.FromList(resultList, Splitter.SplitByNothing(), null, null, ExtraValues.Error)
        	in
            		resultTable,

		// 6. Generate a list of tables, one for each page, by calling GetPage repeatedly.
		// The loop continues until GetPage returns an empty table.
    	ListOfPages = List.Generate(
        	() => [PageContent = GetPage(startPage), PageNumber = startPage], 				// Initial step: get page 0
        	each not Table.IsEmpty([PageContent]),            								// Condition: continue while the returned table is not empty
        	each [PageContent = GetPage([PageNumber] + 1), PageNumber = [PageNumber] + 1],	// Next step: get the next page
        	each [PageContent]                                								// Selector: select only the data table from each step
    	),

		// 7. Combine the list of tables from all pages into a single table.
    	CombinedTable = if List.IsEmpty(ListOfPages) then #table({},{}) else Table.Combine(ListOfPages),

    	// 8. Dynamically expand the record column into multiple columns.
    	// This check is crucial: it prevents an error if the API returns no data at all.
    	ExpandedTable = if Table.IsEmpty(CombinedTable) then
        	CombinedTable
    	else
        	// This robust method finds all unique column names across all records
        	// before expanding, preventing errors if records have different structures.
        	let
            	ColumnToExpand = Table.ColumnNames(CombinedTable){0},
            	FieldNames = List.Distinct(List.Combine(List.Transform(Table.Column(CombinedTable, ColumnToExpand), each if _ is record then Record.FieldNames(_) else {})))
        	in
            	Table.ExpandRecordColumn(CombinedTable, ColumnToExpand, FieldNames),

    	// =======================================================================
    	// == FINAL OUTPUT & METADATA ============================================
    	// =======================================================================
    
    	// 9. Add diagnostic metadata to the function's output.
    	// This helps in debugging by showing how many pages were fetched.
    	AddMetadata = Value.ReplaceMetadata(
        	ExpandedTable,
        	[
            	Documentation.Name = "Production-Ready API Fetcher",
            	Documentation.Description = "Fetches and combines paginated data from the target API.",
            	Diagnostics.PagesFetched = List.Count(ListOfPages),
            	Diagnostics.RowsFetched = Table.RowCount(ExpandedTable),
            	Diagnostics.ExecutionTime = DateTimeZone.UtcNow()
        	]
    	)
in
    AddMetadata