/**
 * Agentforce Apex Action: GetProductsForAge_HF_Saathi
 *
 * Fetches all HF Finance insurance products (Product2_ExternalOrgSF__dlm) and their
 * associated premium plans (Premium__dlm) from Data Cloud, then filters by the
 * customer's age using the Age_Band__c field on Premium__dlm.
 *
 * Returns a formatted list grouped by product so the agent can present every
 * available plan in one clean response without asking the customer for income,
 * life stage, or any other personal detail.
 */
public with sharing class GetProductsForAge_HF_Saathi {

    @InvocableMethod(
        label='Get Products For Age'
        description='Returns all HF Finance insurance products and premium plans from Data Cloud filtered by the customer\'s age. Ask only for age — no other details needed.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(fetchProducts(req.customerAge));
        }
        return results;
    }

    private static Result fetchProducts(Integer age) {
        Result res = new Result();

        if (age == null || age < 1 || age > 99) {
            res.productSummary = 'Please share your age so I can suggest the right plans for you.';
            return res;
        }

        try {
            // ── Fetch all products from Data Cloud ────────────────────────────────
            ConnectApi.CdpQueryInput prodQI = new ConnectApi.CdpQueryInput();
            prodQI.sql =
                'SELECT Product_Code__c, Name__c, Insurance_Type__c, Description__c, ' +
                'Sum_Assured_Min__c, Sum_Assured_Max__c, Policy_Term_Min__c, Policy_Term_Max__c ' +
                'FROM Product2_ExternalOrgSF__dlm ' +
                'ORDER BY Insurance_Type__c ASC';
            ConnectApi.CdpQueryOutputV2 prodRes = ConnectApi.CdpQuery.queryAnsiSqlV2(prodQI);

            if (prodRes == null || prodRes.data == null || prodRes.data.isEmpty()) {
                res.productSummary = 'Our product catalog is temporarily unavailable. Please try again shortly.';
                return res;
            }

            // Build ordered product map
            Map<String, ProductInfo> productMap = new Map<String, ProductInfo>();
            List<String> productOrder = new List<String>();
            for (ConnectApi.CdpQueryV2Row row : prodRes.data) {
                List<Object> c = row.rowData;
                String code = str(c, 0);
                if (String.isBlank(code) || productMap.containsKey(code)) continue;
                ProductInfo p   = new ProductInfo();
                p.code          = code;
                p.name          = str(c, 1);
                p.insuranceType = str(c, 2);
                p.description   = str(c, 3);
                p.sumAssuredMin = dec(c, 4);
                p.sumAssuredMax = dec(c, 5);
                p.policyTermMin = dec(c, 6);
                p.policyTermMax = dec(c, 7);
                p.premiums      = new List<PremiumInfo>();
                productMap.put(code, p);
                productOrder.add(code);
            }

            if (productMap.isEmpty()) {
                res.productSummary = 'No products found at this time. Please contact our team for assistance.';
                return res;
            }

            // ── Fetch premiums, filter by age ─────────────────────────────────────
            String codeList = '\'' + String.join(productOrder, '\',\'') + '\'';
            ConnectApi.CdpQueryInput premQI = new ConnectApi.CdpQueryInput();
            premQI.sql =
                'SELECT Product_Code__c, Premium_Amount__c, Sum_Assured__c, ' +
                'Policy_Term__c, Age_Band__c, Premium_Frequency__c ' +
                'FROM Premium__dlm ' +
                'WHERE Product_Code__c IN (' + codeList + ') ' +
                'ORDER BY Product_Code__c ASC, Sum_Assured__c ASC';
            ConnectApi.CdpQueryOutputV2 premRes = ConnectApi.CdpQuery.queryAnsiSqlV2(premQI);

            if (premRes != null && premRes.data != null) {
                for (ConnectApi.CdpQueryV2Row row : premRes.data) {
                    List<Object> c = row.rowData;
                    String pCode   = str(c, 0);
                    String ageBand = str(c, 4);
                    if (!ageInBand(age, ageBand)) continue;
                    if (!productMap.containsKey(pCode)) continue;
                    PremiumInfo pp    = new PremiumInfo();
                    pp.premiumAmount  = dec(c, 1);
                    pp.sumAssured     = dec(c, 2);
                    pp.policyTerm     = str(c, 3);
                    pp.premiumFreq    = str(c, 5);
                    productMap.get(pCode).premiums.add(pp);
                }
            }

            // ── Build formatted response ──────────────────────────────────────────
            List<String> lines = new List<String>();
            lines.add('Here are HF Finance plans available for age ' + age + ':\n');

            List<String> availableProducts = new List<String>();
            Integer idx = 1;

            for (String code : productOrder) {
                ProductInfo p = productMap.get(code);
                if (p.premiums.isEmpty()) continue;

                String productLabel = String.isNotBlank(p.name) ? p.name : p.insuranceType;
                availableProducts.add(productLabel);

                lines.add(idx + '. *' + productLabel + '*'
                    + (String.isNotBlank(p.insuranceType) && p.insuranceType != productLabel
                        ? ' (' + p.insuranceType + ')' : ''));

                if (String.isNotBlank(p.description)) lines.add('   ' + p.description);

                for (PremiumInfo pp : p.premiums) {
                    String line = '   • Cover: ' + fmtCcy(pp.sumAssured);
                    if (String.isNotBlank(pp.policyTerm)) line += ' | Term: ' + pp.policyTerm + ' yrs';
                    line += ' | Premium: ' + fmtCcy(pp.premiumAmount)
                        + '/' + (String.isNotBlank(pp.premiumFreq) ? pp.premiumFreq : 'month');
                    lines.add(line);
                }
                lines.add('');
                idx++;
            }

            if (idx == 1) {
                res.productSummary = 'We currently have no plans configured for age ' + age + '. '
                    + 'Please contact our team for personalised assistance.';
                return res;
            }

            lines.add('Which plan suits you? I\'ll register your interest right away.');
            res.productSummary    = String.join(lines, '\n').trim();
            res.availableProducts = String.join(availableProducts, ',');

        } catch (System.NoAccessException ex) {
            // Data Cloud feature not enabled for the agent bot user.
            // Admin must assign the appropriate Data Cloud permission set to the agent user.
            ExceptionLogger_HF_Saathi.log('GetProductsForAge_HF_Saathi', 'fetchProducts', ex, String.valueOf(age));
            res.productSummary = 'Our product catalog is currently being set up. '
                + 'Please speak with an HF Finance representative for the latest insurance plans.';
        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetProductsForAge_HF_Saathi', 'fetchProducts', ex, String.valueOf(age));
            res.productSummary = 'Unable to load plans right now. Please try again shortly.';
        }
        return res;
    }

    // ── Age band parser ───────────────────────────────────────────────────────
    // Handles formats: "18-35", "18-35 years", "Above 60", "Below 18", blank (no restriction)
    private static Boolean ageInBand(Integer age, String band) {
        if (String.isBlank(band)) return true;
        try {
            String b = band.trim().toLowerCase().replaceAll('[^0-9\\-]', ' ').trim();
            if (band.toLowerCase().contains('-')) {
                List<String> parts = band.replaceAll('[^0-9\\-]', '').split('-');
                if (parts.size() == 2) {
                    Integer lo = Integer.valueOf(parts[0].trim());
                    Integer hi = Integer.valueOf(parts[1].trim());
                    return age >= lo && age <= hi;
                }
            } else if (band.toLowerCase().contains('above') || band.toLowerCase().contains('over')) {
                Integer lo = Integer.valueOf(band.replaceAll('[^0-9]', ''));
                return age > lo;
            } else if (band.toLowerCase().contains('below') || band.toLowerCase().contains('under')) {
                Integer hi = Integer.valueOf(band.replaceAll('[^0-9]', ''));
                return age < hi;
            }
        } catch (Exception e) { /* unparseable band — include the premium */ }
        return true;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    private static String str(List<Object> row, Integer i) {
        return (i < row.size() && row[i] != null) ? String.valueOf(row[i]) : '';
    }
    private static Decimal dec(List<Object> row, Integer i) {
        if (i >= row.size() || row[i] == null) return null;
        try { return Decimal.valueOf(String.valueOf(row[i])); } catch (Exception e) { return null; }
    }
    private static String fmtCcy(Decimal d) {
        if (d == null) return '--';
        return 'Rs.' + String.valueOf(d.setScale(0)).replaceAll('(\\d)(?=(\\d{2})+(?!\\d))', '$1,');
    }

    private class ProductInfo {
        String code, name, insuranceType, description;
        Decimal sumAssuredMin, sumAssuredMax, policyTermMin, policyTermMax;
        List<PremiumInfo> premiums;
    }
    private class PremiumInfo {
        Decimal premiumAmount, sumAssured;
        String policyTerm, premiumFreq;
    }

    public class Request {
        @InvocableVariable(
            label='Customer Age'
            description='Customer age in years — the only input needed to filter applicable insurance plans.'
            required=true
        )
        public Integer customerAge;
    }

    public class Result {
        @InvocableVariable(label='Product Summary' description='Formatted list of all insurance products and premium plans available for this age.')
        public String productSummary;

        @InvocableVariable(label='Available Products' description='Comma-separated product names for reference in opportunity creation.')
        public String availableProducts;
    }
}