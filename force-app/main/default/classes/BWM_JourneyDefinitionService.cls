/**
 * @description   Resolves BWM_Journey_Definition__mdt journey definitions and template
 *                aliases for messaging.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
public with sharing class BWM_JourneyDefinitionService {
  private static Map<String, BWM_Journey_Definition__mdt> definitionByJourneyName;

  private static final Map<String, String> WHATSAPP_TEMPLATE_ALIASES = new Map<String, String>{
    'u_prosp_not_resp' => 'prospect_not_responding_dept',
    'u_prospecting_not_resp' => 'prospecting_not_responding_dept',
    'u_prospect_de_not_rec' => 'prospect_details_not_received_dept',
    'u_prospecting_det_not_rec' => 'prospecting_details_not_received_dept',
    'u_prospect_enq_dept' => 'prospect_enq_dept',
    'u_prospect_enq_gen' => 'prospect_enq_gen',
    'u_dealer_enq_dept' => 'dealer_enq_dept',
    'u_dealer_enq_gen' => 'dealer_enq_gen'
  };

  public class JourneyOption {
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String label;
  }

  public class SendJourneyResult {
    @AuraEnabled
    public Integer sentCount = 0;
    @AuraEnabled
    public Integer skippedCount = 0;
    @AuraEnabled
    public List<String> messages = new List<String>();
  }

  public static List<JourneyOption> fetchActiveJourneys() {
    ensureDefinitionCacheLoaded();
    List<JourneyOption> options = new List<JourneyOption>();
    List<BWM_Journey_Definition__mdt> definitions = new List<BWM_Journey_Definition__mdt>(
      definitionByJourneyName.values()
    );
    definitions.sort(new JourneyDefinitionComparator());

    for (BWM_Journey_Definition__mdt definition : definitions) {
      if (definition.Is_Active__c != true) {
        continue;
      }
      JourneyOption option = new JourneyOption();
      option.value = definition.Journey_Name__c;
      option.label = definition.Journey_Name__c;
      options.add(option);
    }
    return options;
  }

  public static String buildPayloadForRecord(
    BWM_Messaging_Settings__mdt settings,
    SObject record,
    String journeyName,
    String phoneNumber
  ) {
    return buildPayloadForRecord(
      settings,
      record,
      journeyName,
      phoneNumber,
      false
    );
  }

  public static String buildPayloadForRecord(
    BWM_Messaging_Settings__mdt settings,
    SObject record,
    String journeyName,
    String phoneNumber,
    Boolean forCampaignSend
  ) {
    if (settings == null) {
      throw new AuraHandledException('Messaging settings are not configured.');
    }
    if (String.isBlank(journeyName)) {
      throw new AuraHandledException('Select a journey.');
    }
    if (String.isBlank(phoneNumber)) {
      throw new AuraHandledException('Phone number is required.');
    }

    String resolvedJourneyName = resolveJourneyNameForPayload(journeyName);

    BWM_Template_Mapping__mdt mapping = findMappingByJourneyName(resolvedJourneyName);
    if (mapping != null) {
      String payloadJson = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
        settings,
        mapping,
        record,
        phoneNumber,
        forCampaignSend == true,
        forCampaignSend == true
      );
      return finalizeCampaignBrochureHeaders(
        settings,
        record,
        payloadJson,
        mapping,
        forCampaignSend == true
      );
    }

    BWM_Journey_Definition__mdt definition = getDefinitionByJourneyName(
      resolvedJourneyName
    );
    if (definition == null || String.isBlank(definition.Payload_JSON__c)) {
      throw new AuraHandledException(
        'Journey definition not found for ' + journeyName + '.'
      );
    }

    BWM_Template_Mapping__mdt paramMapping = resolveParamMappingFromDefinition(
      resolvedJourneyName
    );

    List<String> resolvedParams = paramMapping != null
      ? BWM_FieldValueResolver.resolveParamsForRecord(record, paramMapping)
      : new List<String>();
    if (forCampaignSend == true) {
      resolvedParams = BWM_CampaignJourneyParamService.applyCampaignContactParamFixes(
        record,
        resolvedParams
      );
    }

    Map<String, Object> dataPayload = (Map<String, Object>) JSON.deserializeUntyped(
      definition.Payload_JSON__c
    );
    Map<String, Object> resolvedPayload = BWM_JourneyPayloadResolver.resolveDataPayload(
      record,
      dataPayload,
      paramMapping,
      resolvedParams
    );
    // Replace static DOCUMENT PDF links with department / corporate brochure URLs.
    resolvedPayload = BWM_MessagePayloadBuilder.applyDynamicDocumentHeaders(
      settings,
      record,
      resolvedPayload,
      paramMapping
    );

    Map<String, Object> payload = new Map<String, Object>{
      'channel' => BWM_MessagingConstants.CHANNEL_JOURNEY,
      'to' => new List<String>{ phoneNumber },
      'content' => new Map<String, Object>{ 'data' => resolvedPayload }
    };
    return JSON.serialize(payload);
  }

  /**
   * @description For campaign sends, rewrites WhatsApp DOCUMENT headers to department
   *              or corporate brochure URLs without changing send eligibility.
   * @param settings Messaging settings.
   * @param record Record being messaged.
   * @param payloadJson Serialized journey payload.
   * @param mapping Template mapping controlling brochure mode.
   * @param forCampaignSend True when called from Campaign Management.
   * @return Payload JSON with dynamic brochure headers when applicable.
   */
  private static String finalizeCampaignBrochureHeaders(
    BWM_Messaging_Settings__mdt settings,
    SObject record,
    String payloadJson,
    BWM_Template_Mapping__mdt mapping,
    Boolean forCampaignSend
  ) {
    if (forCampaignSend != true || String.isBlank(payloadJson)) {
      return payloadJson;
    }
    return BWM_MessagePayloadBuilder.finalizeCampaignPayload(
      settings,
      record,
      payloadJson,
      mapping
    );
  }

  public static BWM_Journey_Definition__mdt getDefinitionByJourneyName(
    String journeyName
  ) {
    ensureDefinitionCacheLoaded();
    return definitionByJourneyName.get(normalizeName(journeyName));
  }

  public static Map<String, Object> getJourneyNodeDataTemplate(
    String journeyName,
    String templateType
  ) {
    BWM_Journey_Definition__mdt definition = getDefinitionByJourneyName(journeyName);
    if (definition == null || String.isBlank(definition.Payload_JSON__c)) {
      return new Map<String, Object>();
    }

    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      definition.Payload_JSON__c
    );
    Map<String, Object> journeyPayload = (Map<String, Object>) payload.get(
      'journeypayload'
    );
    if (journeyPayload == null) {
      return new Map<String, Object>();
    }

    Map<String, Object> nodes = (Map<String, Object>) journeyPayload.get('nodes');
    if (nodes == null) {
      return new Map<String, Object>();
    }

    for (String nodeKey : nodes.keySet()) {
      Map<String, Object> node = (Map<String, Object>) nodes.get(nodeKey);
      if (node == null) {
        continue;
      }
      String nodeType = (String) node.get('templateType');
      if (nodeType != templateType) {
        continue;
      }

      Map<String, Object> data = (Map<String, Object>) node.get('data');
      return data == null ? new Map<String, Object>() : data;
    }

    return new Map<String, Object>();
  }

  public static Map<String, Object> getRcsBodyDataTemplate(String journeyName) {
    Map<String, Object> nodeData = getJourneyNodeDataTemplate(
      journeyName,
      'RCSMESSAGE'
    );
    Object bodyData = nodeData.get('bodyData');
    return bodyData instanceof Map<String, Object>
      ? (Map<String, Object>) bodyData
      : new Map<String, Object>();
  }

  public static Map<String, Object> getSmsVariableMappingsTemplate(
    String journeyName
  ) {
    Map<String, Object> nodeData = getJourneyNodeDataTemplate(
      journeyName,
      'SMS'
    );
    Object variableMappings = nodeData.get('variableMappings');
    return variableMappings instanceof Map<String, Object>
      ? (Map<String, Object>) variableMappings
      : new Map<String, Object>();
  }

  public static String findJourneyNameByWhatsAppTemplateName(
    String whatsAppTemplateName
  ) {
    if (String.isBlank(whatsAppTemplateName)) {
      return null;
    }

    String trimmedName = whatsAppTemplateName.trim();
    if (
      getDefinitionByJourneyName(trimmedName) != null ||
      findMappingByJourneyName(trimmedName) != null
    ) {
      return trimmedName;
    }

    String normalizedTemplateName = normalizeName(trimmedName);
    BWM_Template_Mapping__mdt mapping = findMappingByWhatsAppTemplateName(
      trimmedName
    );
    if (mapping != null && String.isNotBlank(mapping.Journey_Name__c)) {
      return mapping.Journey_Name__c;
    }

    ensureDefinitionCacheLoaded();
    for (BWM_Journey_Definition__mdt definition : definitionByJourneyName.values()) {
      Map<String, Object> whatsAppNodeData = getJourneyNodeDataTemplate(
        definition.Journey_Name__c,
        'WHATSAPP'
      );
      Object nodeTemplateName = whatsAppNodeData.get('templateName');
      if (
        nodeTemplateName != null &&
        whatsAppTemplateNamesMatch(
          String.valueOf(nodeTemplateName),
          normalizedTemplateName
        )
      ) {
        return definition.Journey_Name__c;
      }
    }

    if (WHATSAPP_TEMPLATE_ALIASES.containsKey(normalizedTemplateName)) {
      BWM_Journey_Definition__mdt aliasDefinition = getDefinitionByJourneyName(
        WHATSAPP_TEMPLATE_ALIASES.get(normalizedTemplateName)
      );
      if (aliasDefinition != null) {
        return aliasDefinition.Journey_Name__c;
      }
    }

    return trimmedName;
  }

  public static BWM_Template_Mapping__mdt findMappingByWhatsAppTemplateName(
    String whatsAppTemplateName
  ) {
    if (String.isBlank(whatsAppTemplateName)) {
      return null;
    }

    String normalizedTemplateName = normalizeName(whatsAppTemplateName);
    List<String> lookupNames = resolveWhatsAppTemplateLookupNames(
      normalizedTemplateName
    );
    BWM_Template_Mapping__mdt bestMatch;

    for (BWM_Template_Mapping__mdt mapping : [
      SELECT
        Trigger_Point__c,
        Lead_Source__c,
        Lead_Stage__c,
        Department_Mode__c,
        Department_Value__c,
        WhatsApp_Template_Name__c,
        Journey_Name__c,
        RCS_Template_Name__c,
        SMS_Template_Name__c,
        SMS_Text_Template__c,
        Include_Brochure_Header__c,
        Is_Active__c,
        Priority__c,
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c,
        RCS_SMS_Param_Limit__c,
        WhatsApp_Header_Format__c,
        WhatsApp_Header_Value_Field__c,
        Document_Header_URL__c,
        Brochure_Attachment_Mode__c,
        Object_Type__c,
        Recipient_Type__c,
        Lost_Reason__c
      FROM BWM_Template_Mapping__mdt
      WHERE Is_Active__c = TRUE AND WhatsApp_Template_Name__c != NULL
    ]) {
      Boolean matches = false;
      for (String lookupName : lookupNames) {
        if (
          whatsAppTemplateNamesMatch(
            mapping.WhatsApp_Template_Name__c,
            lookupName
          ) ||
          whatsAppTemplateNamesMatch(mapping.Journey_Name__c, lookupName)
        ) {
          matches = true;
          break;
        }
      }
      if (!matches) {
        continue;
      }

      if (
        bestMatch == null ||
        (mapping.Priority__c != null &&
          (bestMatch.Priority__c == null ||
            mapping.Priority__c < bestMatch.Priority__c))
      ) {
        bestMatch = mapping;
      }
    }

    return bestMatch;
  }

  public static String findJourneyNameBySmsTemplateName(String smsTemplateName) {
    if (String.isBlank(smsTemplateName)) {
      return null;
    }

    String normalizedTemplateName = normalizeName(smsTemplateName);
    BWM_Template_Mapping__mdt mapping = findMappingBySmsTemplateName(smsTemplateName);
    if (mapping != null && String.isNotBlank(mapping.Journey_Name__c)) {
      return mapping.Journey_Name__c;
    }

    ensureDefinitionCacheLoaded();
    for (BWM_Journey_Definition__mdt definition : definitionByJourneyName.values()) {
      Map<String, Object> smsNodeData = getJourneyNodeDataTemplate(
        definition.Journey_Name__c,
        'SMS'
      );
      Object nodeTemplateName = smsNodeData.get('templateName');
      if (
        nodeTemplateName != null &&
        normalizeName(String.valueOf(nodeTemplateName)) == normalizedTemplateName
      ) {
        return definition.Journey_Name__c;
      }
    }

    return smsTemplateName.trim();
  }

  public static BWM_Template_Mapping__mdt findMappingBySmsTemplateName(
    String smsTemplateName
  ) {
    if (String.isBlank(smsTemplateName)) {
      return null;
    }

    String normalizedTemplateName = normalizeName(smsTemplateName);
    BWM_Template_Mapping__mdt bestMatch;

    for (BWM_Template_Mapping__mdt mapping : [
      SELECT
        Trigger_Point__c,
        Journey_Name__c,
        SMS_Template_Name__c,
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c,
        RCS_SMS_Param_Limit__c,
        Priority__c,
        Include_Brochure_Header__c,
        Document_Header_URL__c,
        Brochure_Attachment_Mode__c
      FROM BWM_Template_Mapping__mdt
      WHERE Is_Active__c = TRUE AND SMS_Template_Name__c != NULL
    ]) {
      if (
        normalizeName(mapping.SMS_Template_Name__c) != normalizedTemplateName
      ) {
        continue;
      }

      if (
        bestMatch == null ||
        (mapping.Priority__c != null &&
          (bestMatch.Priority__c == null ||
            mapping.Priority__c < bestMatch.Priority__c))
      ) {
        bestMatch = mapping;
      }
    }

    return bestMatch;
  }

  public static BWM_Template_Mapping__mdt findMappingByJourneyName(String journeyName) {
    List<BWM_Template_Mapping__mdt> mappings = [
      SELECT
        Trigger_Point__c,
        Lead_Source__c,
        Lead_Stage__c,
        Department_Mode__c,
        Department_Value__c,
        WhatsApp_Template_Name__c,
        Journey_Name__c,
        RCS_Template_Name__c,
        SMS_Template_Name__c,
        SMS_Text_Template__c,
        Include_Brochure_Header__c,
        Is_Active__c,
        Priority__c,
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c,
        RCS_SMS_Param_Limit__c,
        WhatsApp_Header_Format__c,
        WhatsApp_Header_Value_Field__c,
        Document_Header_URL__c,
        Brochure_Attachment_Mode__c,
        Object_Type__c,
        Recipient_Type__c,
        Lost_Reason__c
      FROM BWM_Template_Mapping__mdt
      WHERE Is_Active__c = TRUE AND Journey_Name__c = :journeyName
      ORDER BY Priority__c ASC NULLS LAST
      LIMIT 1
    ];
    return mappings.isEmpty() ? null : mappings[0];
  }

  private static void ensureDefinitionCacheLoaded() {
    if (definitionByJourneyName != null) {
      return;
    }

    definitionByJourneyName = new Map<String, BWM_Journey_Definition__mdt>();
    for (BWM_Journey_Definition__mdt definition : [
      SELECT Journey_Name__c, Payload_JSON__c, Is_Active__c, Sort_Order__c
      FROM BWM_Journey_Definition__mdt
      WHERE Is_Active__c = TRUE
    ]) {
      if (String.isNotBlank(definition.Journey_Name__c)) {
        definitionByJourneyName.put(
          normalizeName(definition.Journey_Name__c),
          definition
        );
      }
    }
  }

  private static String normalizeName(String value) {
    return String.isBlank(value) ? '' : value.trim().toLowerCase();
  }

  /**
   * Campaign journeys may use a journey-name CMDT record whose Payload_JSON still
   * contains numeric placeholders. Resolve Param fields from the linked template
   * mapping (by WhatsApp / RCS / SMS template name) without changing journeyname.
   */
  private static BWM_Template_Mapping__mdt resolveParamMappingFromDefinition(
    String journeyName
  ) {
    Map<String, Object> whatsAppNode = getJourneyNodeDataTemplate(
      journeyName,
      'WHATSAPP'
    );
    Object whatsAppTemplateName = whatsAppNode.get('templateName');
    if (whatsAppTemplateName != null) {
      BWM_Template_Mapping__mdt mapping = findMappingByWhatsAppTemplateName(
        String.valueOf(whatsAppTemplateName)
      );
      if (mapping != null) {
        return mapping;
      }
    }

    Map<String, Object> rcsNode = getJourneyNodeDataTemplate(
      journeyName,
      'RCSMESSAGE'
    );
    Object rcsTemplateName = rcsNode.get('templateName');
    if (rcsTemplateName != null) {
      BWM_Template_Mapping__mdt mapping = findMappingByWhatsAppTemplateName(
        String.valueOf(rcsTemplateName)
      );
      if (mapping != null) {
        return mapping;
      }
    }

    Map<String, Object> smsNode = getJourneyNodeDataTemplate(journeyName, 'SMS');
    Object smsTemplateName = smsNode.get('templateName');
    if (smsTemplateName != null) {
      BWM_Template_Mapping__mdt mapping = findMappingBySmsTemplateName(
        String.valueOf(smsTemplateName)
      );
      if (mapping != null) {
        return mapping;
      }
    }

    return null;
  }

  private static String resolveJourneyNameForPayload(String templateOrJourneyName) {
    if (String.isBlank(templateOrJourneyName)) {
      return templateOrJourneyName;
    }

    String trimmedName = templateOrJourneyName.trim();
    if (
      getDefinitionByJourneyName(trimmedName) != null ||
      findMappingByJourneyName(trimmedName) != null
    ) {
      return trimmedName;
    }

    String resolvedName = findJourneyNameByWhatsAppTemplateName(trimmedName);
    if (
      getDefinitionByJourneyName(resolvedName) != null ||
      findMappingByJourneyName(resolvedName) != null
    ) {
      return resolvedName;
    }

    return trimmedName;
  }

  private static List<String> resolveWhatsAppTemplateLookupNames(
    String normalizedTarget
  ) {
    Set<String> lookupNames = new Set<String>{ normalizedTarget };
    if (WHATSAPP_TEMPLATE_ALIASES.containsKey(normalizedTarget)) {
      lookupNames.add(WHATSAPP_TEMPLATE_ALIASES.get(normalizedTarget));
    }
    for (String metaName : WHATSAPP_TEMPLATE_ALIASES.keySet()) {
      if (WHATSAPP_TEMPLATE_ALIASES.get(metaName) == normalizedTarget) {
        lookupNames.add(metaName);
      }
    }
    return new List<String>(lookupNames);
  }

  private static Boolean whatsAppTemplateNamesMatch(
    String candidate,
    String normalizedTarget
  ) {
    if (String.isBlank(candidate)) {
      return false;
    }

    String normalizedCandidate = candidate.trim().toLowerCase();
    return normalizedCandidate == normalizedTarget ||
      ('u_' + normalizedCandidate) == normalizedTarget ||
      normalizedCandidate == ('u_' + normalizedTarget);
  }

  @TestVisible
  static void clearCache() {
    definitionByJourneyName = null;
  }

  private class JourneyDefinitionComparator implements System.Comparator<BWM_Journey_Definition__mdt> {
    public Integer compare(
      BWM_Journey_Definition__mdt first,
      BWM_Journey_Definition__mdt second
    ) {
      Decimal firstOrder = first == null || first.Sort_Order__c == null
        ? 9999
        : first.Sort_Order__c;
      Decimal secondOrder = second == null || second.Sort_Order__c == null
        ? 9999
        : second.Sort_Order__c;
      if (firstOrder < secondOrder) {
        return -1;
      }
      if (firstOrder > secondOrder) {
        return 1;
      }

      String firstName = first == null || first.Journey_Name__c == null
        ? ''
        : first.Journey_Name__c.toLowerCase();
      String secondName = second == null || second.Journey_Name__c == null
        ? ''
        : second.Journey_Name__c.toLowerCase();
      return firstName.compareTo(secondName);
    }
  }
}