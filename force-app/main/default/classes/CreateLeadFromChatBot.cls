public class CreateLeadFromChatBot {
    
    public class ChatBotInput {
        @InvocableVariable(required=true label='JSON Payload' description='Raw JSON string from the chatbot')
        public String jsonInput;
    }
    
    public class ChatBotData {
        public String userName;
        public List<LeadDetail> leadDetails;
    }
    
    public class LeadDetail {
        public String fieldLabel;
        public String apiName;
        public String value;
    }
    
    /**
* @description Creates a Lead record and returns its direct Lightning view URL string.
* @param inputs List of ChatBotInput payloads.
* @return List<String> contains the direct view URL string for the created Lead.
*/
    @InvocableMethod(label='Create Lead and Return URL' description='Creates a Lead record and returns its direct Lightning view URL string')
    public static List<String> createLeadRecord(List<ChatBotInput> inputs) {
        List<String> createdRecordUrls = new List<String>();
        
        for (ChatBotInput input : inputs) {
            if (String.isBlank(input.jsonInput)) {
                createdRecordUrls.add('');
                continue;
            }
            
            try {
                // 1. Deserialize the incoming JSON structure
                ChatBotData data = (ChatBotData) JSON.deserialize(input.jsonInput, ChatBotData.class);
                
                if (data.leadDetails != null && !data.leadDetails.isEmpty()) {
                    Lead newLead = new Lead();
                    
                    // Set your baseline static values
                    newLead.Company = 'Agentforce Service Agent'; 
                    newLead.Status = 'Prospect';
                    
                    // ========================================================
                    // 🔑 NEW: LOOK UP AND ASSIGN LEAD OWNER FROM USERNAME
                    // ========================================================
                    if (String.isNotBlank(data.userName)) {
                        // Query using a list to safely avoid "List has no rows" exceptions if username is mismatched
                        List<User> matchingUsers = [
                            SELECT Id 
                            FROM User 
                            WHERE Username = :data.userName AND IsActive = true 
                            LIMIT 1
                        ];
                        
                        if (!matchingUsers.isEmpty()) {
                            newLead.OwnerId = matchingUsers[0].Id; // Assigning the real logged-in user as the Lead Owner
                        }
                    }
                    
                    
                    // 2. Map dynamic values from the chatbot JSON arrays
                    for (LeadDetail detail : data.leadDetails) {
                        if (String.isNotBlank(detail.apiName) && detail.value != null) {
                            
                            String sanitizedValue = detail.value.trim(); 
                            
                            newLead.put(detail.apiName, sanitizedValue);
                            
                        }
                    }
                    
                    // 3. Insert the Lead immediately to generate a valid Record ID
                    insert newLead;
                    
                    // 4. Construct the direct Lightning Record URL string dynamically
                    String lightningHost = DomainCreator.getLightningHostname();
                    String recordUrl = 'https://' + lightningHost + '/lightning/r/Lead/' + newLead.Id + '/view';
                    
                    // 5. Add the generated URL string to the return list
                    createdRecordUrls.add(recordUrl);
                } else {
                    createdRecordUrls.add('');
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed to create lead and generate URL: ' + e.getMessage());
                throw new AuraHandledException('Error processing Lead structure: ' + e.getMessage());
            }
        }
        
        return createdRecordUrls;
    }
}