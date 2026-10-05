@isTest
public class TenderListingBatchMock implements HttpCalloutMock {

    public static final String TEST_PRODUCT_NAME = 'High Mast';

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');

        String endpoint = req.getEndpoint();
        String bodyStr = req.getBody();

        Boolean isTargetProduct = bodyStr != null && bodyStr.contains('"ProductName":"' + TEST_PRODUCT_NAME + '"');

        if (endpoint.contains('tender-listing-data-count')) {
            // Only the target product gets real count; everyone else gets 0
            // so only ONE product actually processes tenders in this test run.
            Integer count = isTargetProduct ? 23 : 0;
            res.setBody('{"Success":true,"Message":"Success","TotalRecord":' + count
                + ',"Data":[{"count":' + count + '}],"StatusCode":200}');
            return res;
        }

        if (endpoint.contains('tender-listing-data')) {
            if (isTargetProduct) {
                res.setBody(DUMMY_LISTING_JSON);
            } else {
                res.setBody('{"Success":true,"Message":"Success","TotalRecord":0,"Data":[],"StatusCode":200}');
            }
            return res;
        }

        if (endpoint.contains('probable-bidders-tenderIdWise')) {
            // Minimal valid response so Stage 2 doesn't error - empty bidder list.
            res.setBody('{"Success":true,"Message":"Success","TotalRecord":1,"Data":[{"probable_bidder":["Test Bidder A","Test Bidder B"]}],"StatusCode":200}');
            return res;
        }

        // Any other endpoint (contact details etc.) - safe empty success.
        res.setBody('{"Success":true,"Message":"Success","TotalRecord":0,"Data":[],"StatusCode":200}');
        return res;
    }

    // ---- Paste your full dummy JSON (the one you shared) here exactly as-is ----
    public static final String DUMMY_LISTING_JSON = '{"StatusCode":200,"Data":[{"documents":[{"type":"NOTICE","downloadLink":"https://documents.tender247.com/result/download-document/B01DB3CC657033E447498560D011F335D9311E5C120208EA5D8B19C98DBEA5905AAED81428BD43A69FB7BAF30D41C4F9","name":"c560add0-d2ed-4359-823a-ad4687ab3dba.html","documentid":66520577},{"type":"OTHER","downloadLink":"https://documents.tender247.com/result/download-document/B01DB3CC657033E447498560D011F335B98BE13F001AEF33E252BCBA670681B47CC85E951361835AF021470ED602541E","name":"boqcomparativechart.xlsx","documentid":66520578}],"location":[{"city":"Kollam","state":"Kerala","country":"India","bidawardid":17856079}],"bidderdetails":[{"createddate":"2026-08-04","bidRank":"L2","winner_bidder":false,"aoc_status":false,"financial_status":true,"technical_status":true,"bidValue":780500,"awardedValue":0,"bidderName":"akhil raj r","bidderId":90203220},{"createddate":"2026-08-04","bidRank":"L3","winner_bidder":false,"aoc_status":false,"financial_status":true,"technical_status":true,"bidValue":809250,"awardedValue":0,"bidderName":"johnson j","bidderId":90203221},{"createddate":"2026-08-04","bidRank":"L1","winner_bidder":false,"aoc_status":false,"financial_status":true,"technical_status":true,"bidValue":760875,"awardedValue":0,"bidderName":"sreekumar s","bidderId":90203222}],"category":["Vehicle Hiring"],"organization_name":"kerala state electricity board","aocupdationdate":"","technicalbidevaluationdate":"","financialbidevaluationdate":"","contractdate":"","resultstage":2,"aocdescription":"corrigendum : hiring a taxi jeep or equivalent vehicle (above 1500 cc) less than 15 years old, with experienced driver, fuel etc for the use of electrical section sathamcotta for one year (1750 km/month).","tenderid":133,"datecreated":"2026-08-04","value":0,"postingdate":"2026-08-01","sourcebidawardid":"2026_KSEB_857208_1","bidawardid":17856079},{"documents":[{"type":"NOTICE","downloadLink":"https://documents.tender247.com/result/download-document/EF1B4BC4BD59A2BA10C2C898584B1C384ECF5C5F46A452B9D8BA52530E3684C70F2CA95EE0130419CCE953889B69B101","name":"abe7935a-1e70-400f-bd86-959db1b4a809.html","documentid":66520394},{"type":"OTHER","downloadLink":"https://documents.tender247.com/result/download-document/EF1B4BC4BD59A2BA10C2C898584B1C38A61F0CEE5EBD0964B09DC984C862434B7BB0866CEC46C5BCBD7EE33FEBB1B7F1","name":"boqcomparativechart.xlsx","documentid":66520395}],"location":[{"city":"Varanasi","state":"Uttar Pradesh","country":"India","bidawardid":17855985}],"bidderdetails":[{"createddate":"2026-08-04","bidRank":"L2","winner_bidder":false,"aoc_status":false,"financial_status":true,"technical_status":true,"bidValue":314475,"awardedValue":0,"bidderName":"aadarsh traders","bidderId":90202920},{"createddate":"2026-08-04","bidRank":"L3","winner_bidder":false,"aoc_status":false,"financial_status":true,"technical_status":true,"bidValue":314789,"awardedValue":0,"bidderName":"bajrang iron hardware marble company","bidderId":90202921},{"createddate":"2026-08-04","bidRank":"L1","winner_bidder":false,"aoc_status":false,"financial_status":true,"technical_status":true,"bidValue":267571,"awardedValue":0,"bidderName":"shree badri vishal vibhu enterprises","bidderId":90202922}],"category":["desilting"," Shed Construction"," Well Work"],"organization_name":"municipal corporation","aocupdationdate":"","technicalbidevaluationdate":"","financialbidevaluationdate":"","contractdate":"","resultstage":2,"aocdescription":"ward no. 37, daniyalpur: desilting of well located at purana pul, shitla mata mandir marg, pulkohna bazar, construction of shed over well, and well repair work.","tenderid":122,"datecreated":"2026-08-04","value":0,"postingdate":"2026-08-03","sourcebidawardid":"2026_NNVAR_1172806_4","bidawardid":17855985}],"TotalRecord":2,"Message":"Success","Success":true}';
}