public class SteelPipesExcelMHTMLController {
    private static final String BOUNDARY = '----=_NextPart_ExcelReport_001';

    public Quote   quoteRecord { get; private set; }
    public String  mhtmlContent { get; set; }

    public SteelPipesExcelMHTMLController(ApexPages.StandardController stdController) {
        if (!Test.isRunningTest()) {
            stdController.addFields(new List<String>{
                'QuoteNumber', 'Quote_Value__c', 'CreatedDate', 'ContactId'
            });
        }
        buildReport(stdController.getId());
    }

    private void buildReport(Id quoteId) {
        quoteRecord = [
            SELECT Id, Name, QuoteNumber, Quote_Value__c, CreatedDate,
                Account.Name, Account.BillingStreet, Account.BillingCity,
                Account.BillingState, Account.BillingPostalCode, Account.Phone, Account.Email__c,
                Contact.Name, Contact.Phone, Contact.Email, Contact.MobilePhone,
                BillingStreet, BillingCity, BillingState, BillingPostalCode
            FROM Quote WHERE Id = :quoteId LIMIT 1
        ];

        // ── Logo ──────────────────────────────────────────────────────────────
        String logoBase64    = '';
        String logoMimeType  = 'image/png';
        try {
            StaticResource sr = [SELECT Body, ContentType FROM StaticResource WHERE Name = 'UtkarshLogo' LIMIT 1];
            logoBase64   = formatBase64ForMime(EncodingUtil.base64Encode(sr.Body));
            logoMimeType = sr.ContentType;
        } catch(Exception e) {
            System.debug('Logo static resource not found: ' + e.getMessage());
        }

        // ── Offer Number & Date ───────────────────────────────────────────────
        Integer createdMonth = quoteRecord.CreatedDate.month();
        Integer createdYear  = quoteRecord.CreatedDate.year();
        Integer fyStart      = (createdMonth >= 4) ? createdYear : createdYear - 1;
        String  fyLabel      = fyShort(fyStart) + '-' + fyShort(fyStart + 1);
        String  offerNumber  = 'UIL/STEEL/' + quoteRecord.QuoteNumber + '/' + fyLabel;
        String  todayDate    = Date.today().format();

        // ── Company / Contact ─────────────────────────────────────────────────
        String addr = '';
        if (quoteRecord.Account != null) {
            List<String> parts = new List<String>();
            if (String.isNotBlank(quoteRecord.Account.BillingStreet))     parts.add(quoteRecord.Account.BillingStreet);
            if (String.isNotBlank(quoteRecord.Account.BillingCity))       parts.add(quoteRecord.Account.BillingCity);
            if (String.isNotBlank(quoteRecord.Account.BillingState))      parts.add(quoteRecord.Account.BillingState);
            if (String.isNotBlank(quoteRecord.Account.BillingPostalCode)) parts.add(quoteRecord.Account.BillingPostalCode);
            addr = String.join(parts, ', ');
        }
        String contactName  = (quoteRecord.Contact != null && quoteRecord.Contact.Name  != null) ? quoteRecord.Contact.Name  : '';
        String contactEmail = '';
        if (quoteRecord.Contact != null && String.isNotBlank(quoteRecord.Contact.Email)) {
            contactEmail = quoteRecord.Contact.Email;
        } else if (quoteRecord.Account != null && String.isNotBlank(quoteRecord.Account.Email__c)) {
            contactEmail = quoteRecord.Account.Email__c;
        }
        String contactNo    = '';
        if (quoteRecord.Contact != null && String.isNotBlank(quoteRecord.Contact.Phone)) {
            contactNo = quoteRecord.Contact.Phone;
        } else if (quoteRecord.Account != null && quoteRecord.Account.Phone != null) {
            contactNo = quoteRecord.Account.Phone;
        }
        String accountName = (quoteRecord.Account != null && quoteRecord.Account.Name != null) ? quoteRecord.Account.Name : '';

        // ── Parse JSON ────────────────────────────────────────────────────────
        Map<String, Object>        jsonData          = new Map<String, Object>();
        List<Map<String, Object>>  standardLineItems = new List<Map<String, Object>>();
        List<Map<String, Object>>  specialLineItems  = new List<Map<String, Object>>();
        List<String>               specialHeaderCols = new List<String>();
        Decimal totalAmount        = 0;
        Decimal standardTotalAmount = 0;
        String  quoteNotes         = '';

        if (String.isNotBlank(quoteRecord.Quote_Value__c)) {
            try {
                jsonData = (Map<String, Object>) JSON.deserializeUntyped(quoteRecord.Quote_Value__c);

                List<String> requiredKeys = new List<String>{
                    'market_type','tc_offer_validity','tc_delivery_period','tc_price_variation',
                    'tc_payment_terms','tc_vehicle_load','tc_qty_tolerance','tc_tolerance',
                    'tc_inspection','tc_pre_dispatch_inspection','tc_work_address','tc_gst_tin_number'
                };
                for (String k : requiredKeys) {
                    if (!jsonData.containsKey(k) || jsonData.get(k) == null) jsonData.put(k, '-');
                }

                // Transportation
                String transportText = 'Included';
                if (jsonData.containsKey('freight_steel_pipes') && jsonData.get('freight_steel_pipes') != null) {
                    if (String.valueOf(jsonData.get('freight_steel_pipes')).trim().equalsIgnoreCase('Ex-works')) {
                        transportText = 'Excluded';
                    }
                }
                jsonData.put('tc_transportation', transportText);

                // Notes
                if (jsonData.containsKey('Note') && jsonData.get('Note') != null) {
                    quoteNotes = String.valueOf(jsonData.get('Note'));
                }

                // Line items
                if (jsonData.containsKey('_Saved_Table_Rows')) {
                    List<Object> rawRows = (List<Object>) jsonData.get('_Saved_Table_Rows');
                    Integer slNo     = 1;
                    Integer colIndex = 1;

                    for (Object rowObj : rawRows) {
                        Map<String, Object> row = (Map<String, Object>) rowObj;

                        String spHeader = row.get('special_description_header') != null ? String.valueOf(row.get('special_description_header')).trim() : '';
                        
                        // We now use static columns for Length and Special Description instead of dynamic headers
                        if (specialHeaderCols.isEmpty()) {
                            specialHeaderCols.add('Length');
                            specialHeaderCols.add('Special Description');
                        }

                        String std      = s(row.get('standard_spec_grade'));
                        String pClass   = s(row.get('pipe_class'));
                        String customThk = s(row.get('custom_thickness'));
                        String shapeVal = s(row.get('shape'));

                        String displayClassThk;
                        if (std.contains('IS 1239') || std.contains('10577')) {
                            displayClassThk = String.isNotBlank(shapeVal) ? shapeVal : pClass;
                        } else {
                            Decimal thkVal = 0;
                            if (String.isNotBlank(customThk)) { try { thkVal = Decimal.valueOf(customThk); } catch(Exception ex){} }
                            displayClassThk = (thkVal > 0) ? customThk : pClass;
                        }

                        String reflectInDoc = row.get('reflect_in_offer_doc') != null ? String.valueOf(row.get('reflect_in_offer_doc')) : 'Yes';
                        if (!reflectInDoc.equalsIgnoreCase('Yes')) displayClassThk = '-';

                        Decimal qty   = d(row.get('quantity'));
                        Decimal rate  = d(row.get('rate'));
                        Decimal total = row.get('total_price') != null ? d(row.get('total_price')) : (qty * rate);
                        
                        // Copying precise math from PDF controller
                        Decimal unitGst = row.get('gst') != null ? d(row.get('gst')) : 0.0;
                        Decimal gstPercentage = (rate > 0) ? (unitGst / rate) * 100.0 : 0.0;
                        gstPercentage = gstPercentage.setScale(0, System.RoundingMode.HALF_UP);
                        
                        Decimal discountPercent = row.get('discount') != null ? d(row.get('discount')) : 0.0;
                        Decimal discountedRate = rate * (1 - (discountPercent / 100.0));
                        discountedRate = discountedRate.setScale(2, System.RoundingMode.HALF_UP);
                        
                        Decimal baseTotal = 0.0;
                        if (gstPercentage > 0) {
                            baseTotal = total / (1 + (gstPercentage / 100.0));
                        } else {
                            baseTotal = total;
                        }
                        baseTotal = baseTotal.setScale(2, System.RoundingMode.HALF_UP);
                        
                        Decimal gstAmount = total - baseTotal;
                        
                        Decimal pdf_rate = discountedRate;
                        Decimal pdf_base_total = baseTotal;
                        Decimal pdf_gst_amount = gstAmount;
                        Decimal pdf_total_price = total;
                        String uom = row.get('uom') != null ? s(row.get('uom')) : '-';

                        totalAmount  += total; // We probably want this to be pdf_total_price but let's leave as is for now

                        String cHeader = jsonData.containsKey('c' + colIndex + '_Header') ? s(jsonData.get('c' + colIndex + '_Header')) : '';
                        String cValue  = jsonData.containsKey('c' + colIndex + '_Value')  ? s(jsonData.get('c' + colIndex + '_Value'))  : '';

                        Map<String, Object> pr = new Map<String, Object>{
                            'SlNo'                   => slNo++,
                            'designation'            => s(row.get('designation')),
                            'standard_spec_grade'    => std,
                            'display_class_thickness'=> displayClassThk,
                            'size_nb'                => s(row.get('size_nb')),
                            'end_finish'             => s(row.get('end_finish')),
                            'quantity'               => qty,
                            'rate'                   => rate,
                            'total_price'            => total,
                            'special_description_header' => spHeader,
                            'special_description'    => s(row.get('special_description'))
                        ,
                            'pdf_rate'               => pdf_rate,
                            'pdf_base_total'         => pdf_base_total,
                            'pdf_gst_amount'         => pdf_gst_amount,
                            'pdf_total_price'        => pdf_total_price,
                            'uom'                    => uom
                        };

                        if (String.isNotBlank(cHeader) && String.isNotBlank(cValue)) {
                            pr.put('customHeader', cHeader);
                            pr.put('customValue',  cValue);
                            specialLineItems.add(pr);
                        } else {
                            standardTotalAmount += total;
                            standardLineItems.add(pr);
                        }
                        colIndex++;
                    }

                    // Build specialValuesList aligned with our static columns (Length and Special Description)
                    for (Map<String, Object> row : standardLineItems) {
                        List<String> sVals = new List<String>();
                        String lengthVal = s(row.get('special_description_header'));
                        String descVal   = s(row.get('special_description'));
                        
                        sVals.add(String.isNotBlank(lengthVal) ? lengthVal : '-');
                        sVals.add(String.isNotBlank(descVal)   ? descVal   : '-');
                        
                        row.put('specialValuesList', sVals);
                    }
                }
            } catch(Exception e) {
                System.debug('Error parsing JSON: ' + e.getMessage());
            }
        }

        // ── Build HTML ────────────────────────────────────────────────────────
        String html = buildHtml(
            offerNumber, todayDate, accountName, addr, contactName, contactNo, contactEmail,
            standardLineItems, specialLineItems, specialHeaderCols,
            standardTotalAmount, totalAmount, jsonData, quoteNotes
        );

        // ── Wrap in MHTML ─────────────────────────────────────────────────────
        String crlf  = '\r\n';
        String mhtml = 'MIME-Version: 1.0' + crlf
            + 'Content-Type: multipart/related; type="text/html"; boundary="' + BOUNDARY + '"' + crlf + crlf
            + '--' + BOUNDARY + crlf
            + 'Content-Type: text/html; charset="UTF-8"' + crlf + crlf
            + html + crlf;

        if (String.isNotBlank(logoBase64)) {
            mhtml += '--' + BOUNDARY + crlf
                  + 'Content-Type: ' + logoMimeType + crlf
                  + 'Content-Transfer-Encoding: base64' + crlf
                  + 'Content-ID: <logo@utkarshsteel>' + crlf + crlf
                  + logoBase64 + crlf;
        }

        mhtml += '--' + BOUNDARY + '--';
        mhtmlContent = mhtml;
    }

    // ── HTML Builder ──────────────────────────────────────────────────────────
    // Uses ONE unified table (same as old QuoteOfferExcel.page) so that T&C
    // colspan values naturally align with the data table columns.
    // Logo added to the header row using rowspan.
    private String buildHtml(
        String offerNumber, String todayDate, String accountName, String addr,
        String contactName, String contactNo, String contactEmail,
        List<Map<String, Object>> stdRows, List<Map<String, Object>> spRows,
        List<String> spHeaders, Decimal stdTotal, Decimal grandTotal,
        Map<String, Object> jd, String notes
    ) {
        Integer extraCols = spHeaders.size();
        Integer totalCols = 9 + extraCols;
        Integer leftCols  = totalCols - 3; // logo occupies rightmost 3 cols in header rows

        String css = '<style>'
            + 'body{font-family:sans-serif;font-size:10px;}'
            + 'table{border-collapse:collapse;}'
            + 'th,td{border:1px solid black;padding:5px;text-align:left;}'
            + '.header-text{text-align:center;font-size:12px;font-weight:bold;}'
            + '.bg-green{background-color:#92D050;font-weight:bold;}'
            + '.text-center{text-align:center;}'
            + '.text-right{text-align:right;}'
            + '.no-border{border:none!important;}'
            + '</style>';

        String h = '<!DOCTYPE html><html><head>' + css + '</head><body>';

        // ── ONE big table for everything (mirrors QuoteOfferExcel.page) ───────
        h += '<table>';

        // ── Header rows: company name LEFT, logo RIGHT (rowspan covers 3 rows) ─
        // Row 1: company title | logo (rowspan=3)
        h += '<tr>';
        h += '<td class="no-border header-text" colspan="' + leftCols + '" style="text-align:center;vertical-align:middle;">'
           + '<h2 style="margin:2px 0;">UTKARSH INDIA LIMITED</h2>'
           + '<p style="font-weight:normal;margin:2px 0;">Corporate Office: Arrjavv Square, 4th Floor, 95A, E.M. Bypass, Kolkata - 700010</p>'
           + '<h3 style="margin:2px 0;">QUOTATION FOR STEEL PIPES</h3>'
           + '</td>';
        h += '<td class="no-border" colspan="3" rowspan="3" style="text-align:center;vertical-align:middle;">'
           + '<img src="cid:logo@utkarshsteel" width="130" alt="Utkarsh Logo"/>'
           + '</td>';
        h += '</tr>';

        // Row 2: spacing (leftCols only, logo covers right 3)
        h += '<tr><td colspan="' + leftCols + '" class="no-border"></td></tr>';

        // Row 3: spacing buffer (logo rowspan ends after this row)
        h += '<tr><td colspan="' + leftCols + '" class="no-border"></td></tr>';

        // Row 4+: logo rowspan done — rows now span FULL totalCols width

        // Offer No & Date
        h += '<tr>'
           + '<td colspan="4" style="font-weight:bold;">Offer No. ' + esc(offerNumber) + '</td>'
           + '<td colspan="' + (5 + extraCols) + '" style="font-weight:bold;text-align:right;">Date - ' + esc(todayDate) + '</td>'
           + '</tr>';

        // Company info
        h += '<tr>'
           + '<td colspan="4" style="font-weight:bold;vertical-align:top;">'
           +   'Name of the Company - ' + esc(accountName) + '<br/>'
           +   'Address - ' + esc(addr) + '<br/>'
           +   'Kind Attention - ' + esc(contactName) + '<br/>'
           +   'Contact No - ' + esc(contactNo)
           + '</td>'
           + '<td colspan="' + (5 + extraCols) + '" style="font-weight:bold;text-align:center;vertical-align:middle;">'
           +   'Mail - ' + esc(contactEmail)
           + '</td>'
           + '</tr>';

        // Spacing
        h += '<tr><td colspan="' + totalCols + '" class="no-border"></td></tr>';

        // ── Standard Line Items ───────────────────────────────────────────────
        if (!stdRows.isEmpty()) {
            h += '<tr><td colspan="' + totalCols + '" class="no-border">'
               + '<h3 style="text-decoration:underline;margin-bottom:5px;">SCHEDULE OF MATERIAL</h3>'
               + '</td></tr>';

            // Column headers
            h += '<tr style="background-color:#FFFF00;">';
            h += '<th class="text-center">SL No</th>';
            h += '<th class="text-center">Pipe / Designation</th>';
            h += '<th class="text-center">Size(NB)</th>';
            h += '<th class="text-center">Thickness(mm/Standard)</th>';
            h += '<th class="text-center">Quantity in UOM</th>';
            h += '<th class="text-center">UOM</th>';
            h += '<th class="text-center">End Finish</th>';
            h += '<th class="text-center">IS Specification</th>';
            for (String col : spHeaders) {
                h += '<th class="text-center">' + esc(col) + '</th>';
            }
            h += '<th class="text-center">Rate per UOM</th>';
            h += '<th class="text-center">Total</th>';
            h += '<th class="text-center">GST @18%</th>';
            h += '<th class="text-center">Total Price</th>';
            h += '</tr>';

            // Data rows
            for (Map<String, Object> row : stdRows) {
                h += '<tr>';
                h += '<td class="text-center">' + esc(s(row.get('SlNo'))) + '</td>';
                h += '<td class="text-center">' + esc(s(row.get('designation'))) + '</td>';
                h += '<td class="text-center">' + esc(s(row.get('size_nb'))) + '</td>';
                String dct = s(row.get('display_class_thickness'));
                h += '<td class="text-center">' + (String.isBlank(dct) ? '-' : esc(dct)) + '</td>';
                h += '<td class="text-center">' + fmt((Decimal) row.get('quantity'), 0) + '</td>';
                h += '<td class="text-center">' + esc(s(row.get('uom'))) + '</td>';
                h += '<td class="text-center">' + esc(s(row.get('end_finish'))) + '</td>';
                h += '<td class="text-center">' + esc(s(row.get('standard_spec_grade'))) + '</td>';
                List<Object> sValsObj = (List<Object>) row.get('specialValuesList');
                if (sValsObj != null) {
                    for (Object sv : sValsObj) {
                        h += '<td class="text-center">' + esc(s(sv)) + '</td>';
                    }
                }
                h += '<td class="text-right">' + fmt((Decimal) row.get('pdf_rate'), 2) + '</td>';
                h += '<td class="text-right">' + fmt((Decimal) row.get('pdf_base_total'), 2) + '</td>';
                h += '<td class="text-right">' + fmt((Decimal) row.get('pdf_gst_amount'), 2) + '</td>';
                h += '<td class="text-right">' + fmt((Decimal) row.get('pdf_total_price'), 2) + '</td>';
                h += '</tr>';
            }

            // Sub total
            h += '<tr>'
               + '<td colspan="' + (8 + extraCols) + '" class="text-right" style="font-weight:bold;">Sub Total:</td>'
               + '<td class="text-right" style="font-weight:bold;">' + fmt(stdTotal, 2) + '</td>'
               + '</tr>';
        }

        // ── Special Line Items ────────────────────────────────────────────────
        for (Map<String, Object> spRow : spRows) {
            String spHdr = s(spRow.get('customHeader'));
            h += '<tr><td colspan="' + totalCols + '" class="no-border"></td></tr>';
            h += '<tr><td colspan="' + totalCols + '" class="no-border">'
               + '<h3 style="text-decoration:underline;margin-bottom:5px;margin-top:15px;">SPECIAL ITEM - ' + esc(spHdr) + '</h3>'
               + '</td></tr>';

            h += '<tr style="background-color:#f2f2f2;">';
            h += '<th class="text-center">Sl. No.</th>';
            h += '<th class="text-center">Designation</th>';
            h += '<th class="text-center">Standard / Spec / Grade</th>';
            h += '<th class="text-center">Class/ Thickness</th>';
            h += '<th class="text-center">Size / NB</th>';
            h += '<th class="text-center">End Finish</th>';
            h += '<th class="text-center" style="background-color:#e6f2ff;">' + esc(spHdr) + '</th>';
            h += '<th class="text-center">Qty (Meters)</th>';
            h += '<th class="text-center">Rate</th>';
            h += '<th class="text-center">Total</th>';
            if (extraCols > 1) {
                h += '<td colspan="' + (extraCols - 1) + '" class="no-border"></td>';
            }
            h += '</tr>';

            h += '<tr>';
            h += '<td class="text-center">' + esc(s(spRow.get('SlNo'))) + '</td>';
            h += '<td class="text-center">' + esc(s(spRow.get('designation'))) + '</td>';
            h += '<td class="text-center">' + esc(s(spRow.get('standard_spec_grade'))) + '</td>';
            String dct2 = s(spRow.get('display_class_thickness'));
            h += '<td class="text-center">' + (String.isBlank(dct2) ? '-' : esc(dct2)) + '</td>';
            h += '<td class="text-center">' + esc(s(spRow.get('size_nb'))) + '</td>';
            h += '<td class="text-center">' + esc(s(spRow.get('end_finish'))) + '</td>';
            h += '<td class="text-center" style="font-weight:bold;">' + esc(s(spRow.get('customValue'))) + '</td>';
            h += '<td class="text-right">' + fmt((Decimal) spRow.get('quantity'), 0) + '</td>';
            h += '<td class="text-right">' + fmt((Decimal) spRow.get('rate'), 2) + '</td>';
            h += '<td class="text-right">' + fmt((Decimal) spRow.get('total_price'), 2) + '</td>';
            if (extraCols > 1) {
                h += '<td colspan="' + (extraCols - 1) + '" class="no-border"></td>';
            }
            h += '</tr>';

            h += '<tr>'
               + '<td colspan="9" class="text-right" style="font-weight:bold;">Sub Total:</td>'
               + '<td class="text-right" style="font-weight:bold;">' + fmt((Decimal) spRow.get('total_price'), 2) + '</td>';
            if (extraCols > 1) {
                h += '<td colspan="' + (extraCols - 1) + '" class="no-border"></td>';
            }
            h += '</tr>';
        }

        // Grand Total
        if (!spRows.isEmpty()) {
            h += '<tr><td colspan="' + totalCols + '" class="no-border"></td></tr>';
            h += '<tr>'
               + '<td colspan="' + (8 + extraCols) + '" class="text-right no-border" style="font-weight:bold;font-size:12px;">OVERALL GRAND TOTAL:</td>'
               + '<td class="text-right" style="border:1px solid #000;font-weight:bold;font-size:12px;">' + fmt(grandTotal, 2) + '</td>'
               + '</tr>';
        }

        // Spacing
        h += '<tr><td colspan="' + totalCols + '" class="no-border"></td></tr>';

        // ── Commercial Terms (same table, colspan mirrors old VF page) ─────────
        h += '<tr><td colspan="' + totalCols + '" class="no-border">'
           + '<h3 style="text-decoration:underline;margin-bottom:5px;">COMMERCIAL TERMS &amp; CONDITIONS</h3>'
           + '</td></tr>';

        Integer tcValCols = 6 + extraCols;
        h += '<tr><td colspan="3" class="bg-green">Offer Validity</td><td colspan="'         + tcValCols + '">' + escHtml(s(jd.get('tc_offer_validity')))          + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Delivery Period</td><td colspan="'        + tcValCols + '">' + escHtml(s(jd.get('tc_delivery_period')))         + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Payment Terms</td><td colspan="'          + tcValCols + '">' + escHtml(s(jd.get('tc_payment_terms')))           + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Price Variation Clause</td><td colspan="' + tcValCols + '">' + escHtml(s(jd.get('tc_price_variation')))        + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Transportation</td><td colspan="'         + tcValCols + '">' + escHtml(s(jd.get('tc_transportation')))          + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Vehicle Load</td><td colspan="'           + tcValCols + '">' + escHtml(s(jd.get('tc_vehicle_load')))            + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Qty Tolerance</td><td colspan="'          + tcValCols + '">' + escHtml(s(jd.get('tc_qty_tolerance')))           + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Tolerance</td><td colspan="'              + tcValCols + '">' + escHtml(s(jd.get('tc_tolerance')))               + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Inspection</td><td colspan="'             + tcValCols + '">' + escHtml(s(jd.get('tc_inspection')))              + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Pre Dispatch Inspection</td><td colspan="'+ tcValCols + '">' + escHtml(s(jd.get('tc_pre_dispatch_inspection'))) + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">Work Address</td><td colspan="'           + tcValCols + '">' + escHtml(s(jd.get('tc_work_address')))            + '</td></tr>';
        h += '<tr><td colspan="3" class="bg-green">GST TIN Number</td><td colspan="'        + tcValCols + '">' + escHtml(s(jd.get('tc_gst_tin_number')))         + '</td></tr>';

        if (String.isNotBlank(notes)) {
            h += '<tr><td colspan="' + totalCols + '" class="no-border"></td></tr>';
            h += '<tr><td colspan="' + totalCols + '" class="no-border">'
               + '<b>Notes / Remarks:</b><br/>' + escHtml(notes)
               + '</td></tr>';
        }

        h += '</table>';
        h += '</body></html>';
        return h;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // ── Helpers ───────────────────────────────────────────────────────────────
    // tcRow: allow <br/> tags through so T&C multi-line values render correctly in Excel
    private String tcRow(String label, String val) {
        return '<tr><td class="bggreen">' + esc(label) + '</td><td>' + escHtml(val) + '</td></tr>';
    }

    private String td(String content, String cssClass) {
        return '<td class="' + cssClass + '">' + esc(content) + '</td>';
    }

    private String esc(String v) {
        if (v == null) return '';
        return v.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }

    // escHtml: escape but preserve <br/> and <br> tags (used for T&C values)
    private String escHtml(String v) {
        if (v == null) return '';
        // Temporarily protect <br/> and <br> before escaping
        String safe = v.replace('<br/>', '~~~BR~~~').replace('<br />', '~~~BR~~~').replace('<br>', '~~~BR~~~');
        safe = esc(safe);
        // Restore as real HTML line breaks
        return safe.replace('~~~BR~~~', '<br/>');
    }

    private String s(Object o) {
        return o != null ? String.valueOf(o) : '';
    }

    private Decimal d(Object o) {
        if (o == null) return 0;
        try { return Decimal.valueOf(String.valueOf(o)); } catch(Exception e) { return 0; }
    }

    private String fmt(Decimal v, Integer decimals) {
        if (v == null) v = 0;
        return v.setScale(decimals, System.RoundingMode.HALF_UP).format();
    }

    private String fyShort(Integer year) {
        String y = String.valueOf(year);
        return y.substring(y.length() - 2);
    }

    // Split base64 into 76-char lines as required by MIME spec
    private String formatBase64ForMime(String b64) {
        String result = '';
        Integer lineLen = 76;
        for (Integer i = 0; i < b64.length(); i += lineLen) {
            Integer endIdx = Math.min(i + lineLen, b64.length());
            result += b64.substring(i, endIdx) + '\r\n';
        }
        return result;
    }
}