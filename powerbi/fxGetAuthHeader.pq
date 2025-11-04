() as text =>
let
    // 1) Call the endpoint, sending an empty JSON object
    rawResponse    = Web.Contents(
                        BaseUrl,
                        [
                           RelativePath = "/api/ApiToken/GenerateAccessTokenFromApiToken/",
                           Headers = [
                              #"Content-Type" = "application/json",
                              Authorization  = "Bearer " & ApiToken
                           ],
                          Content = Text.ToBinary("")
                        ]
                     ),

    // 2) Keep the raw response text for diagnostics
    responseText   = Text.FromBinary(rawResponse, TextEncoding.Utf8),

    // 3) Attempt to parse JSON, or throw a clear error
    parseAttempt   = try Json.Document(rawResponse) 
                     otherwise error "Invalid JSON from token endpoint: " & responseText,

    // 4) Ensure it’s not null and is a record
    responseRecord =
      if parseAttempt = null then 
         error "Token endpoint returned null instead of JSON."
      else if Value.Is(parseAttempt, type record) then 
         parseAttempt 
      else 
         error "Expected JSON record but got " 
               & Value.Type(parseAttempt) 
               & ". Full response: " 
               & responseText,

    // 5) Pull out the token (check both “RawToken” and “Token” fields)
    token =
      if Record.HasFields(responseRecord, "RawToken") then 
         responseRecord[RawToken]
      else if Record.HasFields(responseRecord, "Token") then 
         responseRecord[Token]
      else
         error  "No token field found. Available fields: " 
                & Text.Combine(Record.FieldNames(responseRecord), ", ") 
                & ". Response was: " 
                & responseText,

    // 7) Build the final header
    resultHeader = "Bearer " & token
in
    resultHeader