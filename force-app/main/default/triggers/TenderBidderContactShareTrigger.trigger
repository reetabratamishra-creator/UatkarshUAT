trigger TenderBidderContactShareTrigger on Bidders_Contact_Details__c (after insert) {

    // Independent toggle - new field on the same mdt type used by the other share triggers.
    Tender_Trigger_Controll__mdt setting =
        Tender_Trigger_Controll__mdt.getInstance('Tender_Bidder_Contact_Share_Trigger');

    if (setting != null && !setting.Is_Bidder_Contact_Share_Active__c) {
        return;
    }

    TenderBidderContactSharingHandler.shareContacts(Trigger.new);
}