import { LightningElement, track, api } from 'lwc';
import getExistingRates from '@salesforce/apex/QuoteRateCardController.getExistingRates';

const STEEL_TYPE_OPTIONS = [
    { label: "Black Steel", value: "Black Steel" },
    { label: "Galvanized Iron (GI)", value: "Galvanized Iron (GI)" },
    { label: "Stainless Steel", value: "Stainless Steel" }
];

const DESIGNATION_OPTIONS = [
    { label: "MS ERW", value: "MS ERW" },
    { label: "GI ERW", value: "GI ERW" },
    { label: "CS ERW", value: "CS ERW" }
];

const STANDARD_OPTIONS = [
    { label: "ASTM A53", value: "ASTM A53" },
    { label: "ASTM A 135", value: "ASTM A 135" },
    { label: "ASTM A 500", value: "ASTM A 500" },
    { label: "ASTM A 795", value: "ASTM A 795" },
    { label: "ISO 65", value: "ISO 65" },
    { label: "AS 1074", value: "AS 1074" },
    { label: "EN 10255", value: "EN 10255" },
    { label: "BS 1387", value: "BS 1387" },
    { label: "EN 39", value: "EN 39" },
    { label: "AS 1163", value: "AS 1163" },
    { label: "EN 10219", value: "EN 10219" }
];

const GRADE_OPTIONS = [
    { label: "Grade A", value: "Grade A" },
    { label: "Grade B", value: "Grade B" }
];

const GRADE_TOLERANCE_MAP = {
    "Grade A": 12.5,
    "Grade B": 12.5
};

const SERIES_OPTIONS = [
    { label: "Light", value: "Light" },
    { label: "Medium", value: "Medium" },
    { label: "Heavy", value: "Heavy" },
    { label: "Manual", value: "Manual" }
];

const END_FINISH_OPTIONS = [
    { label: "Plain End", value: "Plain End" },
    { label: "Beveled End", value: "Beveled End" },
    { label: "Screwed & Socket", value: "Screwed & Socket" },
    { label: "Grooved End", value: "Grooved End" }
];

const UOM_OPTIONS = [
    { label: "MT", value: "MT" },
    { label: "Meters", value: "Meters" },
    { label: "Pieces", value: "Pieces" }
];

const CURRENCY_OPTIONS = [
    { label: "USD", value: "USD" },
    { label: "GBP", value: "GBP" },
    { label: "EUR", value: "EUR" },
    { label: "AED", value: "AED" }
];

const FREIGHT_OPTIONS = [
    { label: "FOB", value: "FOB" },
    { label: "CFR", value: "CFR" },
    { label: "CIF", value: "CIF" }
];

const AS1163_OD_MAP = {
    "15": { od: 21.3, wt: 2.0 }, "20": { od: 26.9, wt: 2.0 }, "25": { od: 33.7, wt: 2.0 },
    "32": { od: 42.4, wt: 2.0 }, "40": { od: 48.3, wt: 2.0 }, "50": { od: 60.3, wt: 2.0 },
    "65": { od: 76.1, wt: 2.0 }, "80": { od: 88.9, wt: 2.0 }, "90": { od: 101.6, wt: 2.0 },
    "100": { od: 114.3, wt: 2.5 }, "110": { od: 127.0, wt: 2.9 }, "125": { od: 139.7, wt: 3.0 },
    "135": { od: 152.4, wt: 3.0 }, "150": { od: 165.1, wt: 3.0 }, "175": { od: 193.7, wt: 4.0 },
    "200": { od: 219.1, wt: 4.0 }, "250": { od: 273.0, wt: 5.0 }, "300": { od: 323.9, wt: 6.0 },
    "350": { od: 355.6, wt: 5.0 }
};

const EN_10255_SIZE_MAP = {
    15: '21.3 mm (1/2")', 20: '26.9 mm (3/4")', 25: '33.7 mm (1")', 32: '42.4 mm (1¼")',
    40: '48.3 mm (1½")', 50: '60.3 mm (2")', 65: '76.1 mm (2½")', 80: '88.9 mm (3")',
    100: '114.3 mm (4")', 125: '139.7 mm (5")', 150: '165.1 mm (6")'
};

const CATALOG_MAP = {
    "EN 10255|Light|15": { "od": 21.4, "wt": 2 }, "EN 10255|Medium|15": { "od": 21.8, "wt": 2.6 }, "EN 10255|Heavy|15": { "od": 21.8, "wt": 3.2 },
    "EN 10255|Light|20": { "od": 26.9, "wt": 2.3 }, "EN 10255|Medium|20": { "od": 27.3, "wt": 2.6 }, "EN 10255|Heavy|20": { "od": 27.3, "wt": 3.2 },
    "EN 10255|Light|25": { "od": 33.8, "wt": 2.6 }, "EN 10255|Medium|25": { "od": 34.2, "wt": 3.2 }, "EN 10255|Heavy|25": { "od": 34.2, "wt": 4 },
    "EN 10255|Light|32": { "od": 42.5, "wt": 2.6 }, "EN 10255|Medium|32": { "od": 42.9, "wt": 3.2 }, "EN 10255|Heavy|32": { "od": 42.9, "wt": 4 },
    "EN 10255|Light|40": { "od": 48.4, "wt": 2.9 }, "EN 10255|Medium|40": { "od": 48.8, "wt": 3.2 }, "EN 10255|Heavy|40": { "od": 48.8, "wt": 4 },
    "EN 10255|Light|50": { "od": 60.2, "wt": 2.9 }, "EN 10255|Medium|50": { "od": 60.8, "wt": 3.6 }, "EN 10255|Heavy|50": { "od": 60.8, "wt": 4.5 },
    "EN 10255|Light|65": { "od": 76, "wt": 3.2 }, "EN 10255|Medium|65": { "od": 76.6, "wt": 3.6 }, "EN 10255|Heavy|65": { "od": 76.6, "wt": 4.5 },
    "EN 10255|Light|80": { "od": 88.7, "wt": 3.2 }, "EN 10255|Medium|80": { "od": 89.5, "wt": 4 }, "EN 10255|Heavy|80": { "od": 89.5, "wt": 5 },
    "EN 10255|Light|100": { "od": 113.9, "wt": 3.6 }, "EN 10255|Medium|100": { "od": 115, "wt": 4.5 }, "EN 10255|Heavy|100": { "od": 115, "wt": 5.4 },
    "EN 10255|Medium|125": { "od": 140.8, "wt": 5 }, "EN 10255|Heavy|125": { "od": 140.8, "wt": 5.4 },
    "EN 10255|Medium|150": { "od": 166.5, "wt": 5 }, "EN 10255|Heavy|150": { "od": 166.5, "wt": 5.4 },

    "BS 1387|Light|15": { "od": 21.4, "wt": 2 }, "BS 1387|Medium|15": { "od": 21.8, "wt": 2.6 }, "BS 1387|Heavy|15": { "od": 21.8, "wt": 3.2 },
    "BS 1387|Light|20": { "od": 26.9, "wt": 2.3 }, "BS 1387|Medium|20": { "od": 27.3, "wt": 2.6 }, "BS 1387|Heavy|20": { "od": 27.3, "wt": 3.2 },
    "BS 1387|Light|25": { "od": 33.8, "wt": 2.6 }, "BS 1387|Medium|25": { "od": 34.2, "wt": 3.2 }, "BS 1387|Heavy|25": { "od": 34.2, "wt": 4 },
    "BS 1387|Light|32": { "od": 42.5, "wt": 2.6 }, "BS 1387|Medium|32": { "od": 42.9, "wt": 3.2 }, "BS 1387|Heavy|32": { "od": 42.9, "wt": 4 },
    "BS 1387|Light|40": { "od": 48.4, "wt": 2.9 }, "BS 1387|Medium|40": { "od": 48.8, "wt": 3.2 }, "BS 1387|Heavy|40": { "od": 48.8, "wt": 4 },
    "BS 1387|Light|50": { "od": 60.2, "wt": 2.9 }, "BS 1387|Medium|50": { "od": 60.8, "wt": 3.6 }, "BS 1387|Heavy|50": { "od": 60.8, "wt": 4.5 },
    "BS 1387|Light|65": { "od": 76, "wt": 3.2 }, "BS 1387|Medium|65": { "od": 76.6, "wt": 3.6 }, "BS 1387|Heavy|65": { "od": 76.6, "wt": 4.5 },
    "BS 1387|Light|80": { "od": 88.7, "wt": 3.2 }, "BS 1387|Medium|80": { "od": 89.5, "wt": 4 }, "BS 1387|Heavy|80": { "od": 89.5, "wt": 5 },
    "BS 1387|Light|100": { "od": 113.9, "wt": 3.6 }, "BS 1387|Medium|100": { "od": 115, "wt": 4.5 }, "BS 1387|Heavy|100": { "od": 115, "wt": 5.4 },
    "BS 1387|Medium|125": { "od": 140.8, "wt": 5 }, "BS 1387|Heavy|125": { "od": 140.8, "wt": 5.4 },
    "BS 1387|Medium|150": { "od": 166.5, "wt": 5 }, "BS 1387|Heavy|150": { "od": 166.5, "wt": 5.4 },
    
    "ASTM A53|Schedule 10|300": { "od": 323.9, "wt": 6.35 }, "ASTM A53|Schedule 10|350": { "od": 355.6, "wt": 6.35 },
    "ASTM A53|Schedule 20|200": { "od": 219.1, "wt": 6.35 }, "ASTM A53|Schedule 20|250": { "od": 273.0, "wt": 6.35 }, "ASTM A53|Schedule 20|300": { "od": 323.9, "wt": 6.35 }, "ASTM A53|Schedule 20|350": { "od": 355.6, "wt": 7.92 }, "ASTM A53|Schedule 20|400": { "od": 406.4, "wt": 7.92 },
    "ASTM A53|Schedule 30|200": { "od": 219.1, "wt": 7.04 }, "ASTM A53|Schedule 30|250": { "od": 273.0, "wt": 7.80 }, "ASTM A53|Schedule 30|300": { "od": 323.9, "wt": 8.38 }, "ASTM A53|Schedule 30|350": { "od": 355.6, "wt": 9.52 }, "ASTM A53|Schedule 30|400": { "od": 406.4, "wt": 9.52 },
    "ASTM A53|Schedule 40|15": { "od": 21.3, "wt": 2.77 }, "ASTM A53|Schedule 40|20": { "od": 26.7, "wt": 2.87 }, "ASTM A53|Schedule 40|25": { "od": 33.4, "wt": 3.38 }, "ASTM A53|Schedule 40|32": { "od": 42.2, "wt": 3.56 }, "ASTM A53|Schedule 40|40": { "od": 48.3, "wt": 3.68 }, "ASTM A53|Schedule 40|50": { "od": 60.3, "wt": 3.91 }, "ASTM A53|Schedule 40|65": { "od": 73.0, "wt": 5.16 }, "ASTM A53|Schedule 40|80": { "od": 88.9, "wt": 5.49 }, "ASTM A53|Schedule 40|90": { "od": 101.6, "wt": 5.74 }, "ASTM A53|Schedule 40|100": { "od": 114.3, "wt": 6.02 }, "ASTM A53|Schedule 40|125": { "od": 141.3, "wt": 6.55 }, "ASTM A53|Schedule 40|150": { "od": 168.3, "wt": 7.11 }, "ASTM A53|Schedule 40|200": { "od": 219.1, "wt": 8.18 }, "ASTM A53|Schedule 40|250": { "od": 273.0, "wt": 9.27 }, "ASTM A53|Schedule 40|300": { "od": 323.9, "wt": 10.31 }, "ASTM A53|Schedule 40|350": { "od": 355.6, "wt": 11.13 }, "ASTM A53|Schedule 40|400": { "od": 406.4, "wt": 12.7 },
    "ASTM A53|Schedule 60|200": { "od": 219.1, "wt": 10.31 },
    "AS 1074|Light|15": { "od": 21.4, "wt": 2 }, "AS 1074|Light|20": { "od": 26.9, "wt": 2.3 }, "AS 1074|Light|25": { "od": 33.8, "wt": 2.6 },
    "AS 1074|Light|32": { "od": 42.5, "wt": 2.6 }, "AS 1074|Light|40": { "od": 48.4, "wt": 2.9 }, "AS 1074|Light|50": { "od": 60.2, "wt": 2.9 },
    "AS 1074|Light|65": { "od": 76, "wt": 3.2 }, "AS 1074|Light|80": { "od": 88.7, "wt": 3.2 }, "AS 1074|Light|100": { "od": 113.9, "wt": 3.6 },
    "AS 1074|Light 1|15": { "od": 21.3, "wt": 2 }, "AS 1074|Light 2|15": { "od": 21.4, "wt": 2 }, "AS 1074|Medium|15": { "od": 21.7, "wt": 2.6 }, "AS 1074|Heavy|15": { "od": 21.7, "wt": 3.2 },
    "AS 1074|Light 1|20": { "od": 26.9, "wt": 2.3 }, "AS 1074|Light 2|20": { "od": 26.9, "wt": 2.3 }, "AS 1074|Medium|20": { "od": 27.2, "wt": 2.6 }, "AS 1074|Heavy|20": { "od": 27.2, "wt": 3.2 },
    "AS 1074|Light 1|25": { "od": 33.7, "wt": 2.6 }, "AS 1074|Light 2|25": { "od": 33.8, "wt": 2.6 }, "AS 1074|Medium|25": { "od": 34.2, "wt": 3.2 }, "AS 1074|Heavy|25": { "od": 34.2, "wt": 4 },
    "AS 1074|Light 1|32": { "od": 42.4, "wt": 2.6 }, "AS 1074|Light 2|32": { "od": 42.5, "wt": 2.6 }, "AS 1074|Medium|32": { "od": 42.9, "wt": 3.2 }, "AS 1074|Heavy|32": { "od": 42.9, "wt": 4 },
    "AS 1074|Light 1|40": { "od": 48.3, "wt": 2.9 }, "AS 1074|Light 2|40": { "od": 48.6, "wt": 2.9 }, "AS 1074|Medium|40": { "od": 48.8, "wt": 3.2 }, "AS 1074|Heavy|40": { "od": 48.8, "wt": 4 },
    "AS 1074|Light 1|50": { "od": 60.3, "wt": 2.9 }, "AS 1074|Light 2|50": { "od": 60.2, "wt": 2.9 }, "AS 1074|Medium|50": { "od": 60.8, "wt": 3.6 }, "AS 1074|Heavy|50": { "od": 60.8, "wt": 4.5 },
    "AS 1074|Light 1|65": { "od": 76.1, "wt": 3.2 }, "AS 1074|Light 2|65": { "od": 76, "wt": 3.2 }, "AS 1074|Medium|65": { "od": 76.6, "wt": 3.6 }, "AS 1074|Heavy|65": { "od": 76.6, "wt": 4.5 },
    "AS 1074|Light 1|80": { "od": 88.9, "wt": 3.2 }, "AS 1074|Light 2|80": { "od": 88.7, "wt": 3.2 }, "AS 1074|Medium|80": { "od": 89.5, "wt": 4 }, "AS 1074|Heavy|80": { "od": 89.5, "wt": 5 },
    "AS 1074|Light 1|100": { "od": 114.3, "wt": 3.6 }, "AS 1074|Light 2|100": { "od": 113.9, "wt": 3.6 }, "AS 1074|Medium|100": { "od": 114.9, "wt": 4.5 }, "AS 1074|Heavy|100": { "od": 114.9, "wt": 5.4 },
    "AS 1074|Medium|125": { "od": 140.6, "wt": 5 }, "AS 1074|Heavy|125": { "od": 140.6, "wt": 5.4 },
    "AS 1074|Medium|150": { "od": 166.1, "wt": 5 }, "AS 1074|Heavy|150": { "od": 166.1, "wt": 5.4 }
};

export default class SteelPipeExportConfig extends LightningElement {
    @track pipeCount = 1;
    @track pipes = [];
    @track showCalculations = true;
    
    @track globalCurrencyCode = 'USD';
    @track globalExchangeRate = 1.0;
    
    @track globalRodtepPercent = 0.45;
    @track globalIncentivePercent = 1.5;
    
    @track dynamicBaseRates = {};
    WEIGHT_MAP = {};
    SHAPE_DEPENDENT_MAP = {};
    CLASS_DEPENDENT_MAP = {};

    @api savedPipes = [];
    @api isReadOnly = false;

    get currencyOptions() {
        return CURRENCY_OPTIONS;
    }

    get calcButtonVariant() {
        return this.showCalculations ? 'brand' : 'border-filled';
    }

    get tableWidthStyle() {
        return this.showCalculations ? 'width: 100%; min-width: 4980px;' : 'width: 100%; min-width: 4220px;';
    }

    getDesignationOptions(steelType) {
        if (steelType === 'Black Steel') {
            return [
                { label: "MS ERW", value: "MS ERW" },
                { label: "CS ERW", value: "CS ERW" }
            ];
        } else if (steelType === 'Galvanized Iron (GI)') {
            return [
                { label: "GI ERW", value: "GI ERW" }
            ];
        } else if (steelType === 'Stainless Steel') {
            return [
                { label: "SS ERW", value: "SS ERW" }
            ];
        }
        return DESIGNATION_OPTIONS;
    }

    async connectedCallback() {
        await this.fetchConfigData();
        this.initializePipes();
    }

    fetchConfigData() {
        return getExistingRates({ recordDeveloperName: 'Steel_Pipes_Export' })
            .then(record => {
                if (record) {
                    let payload = record.JSON_Payload__c || record.rateCard__c;
                    if (payload) {
                        try {
                            const config = JSON.parse(payload);
                            let tempMap = config.WEIGHT_MAP || {};
                            this.WEIGHT_MAP = {};
                            for (let k in tempMap) {
                                let cleanKey = k.replace(/&#124;/g, '|');
                                this.WEIGHT_MAP[cleanKey] = tempMap[k];
                            }
                            this.SHAPE_DEPENDENT_MAP = config.SHAPE_DEPENDENT_MAP || {};
                            this.CLASS_DEPENDENT_MAP = config.CLASS_DEPENDENT_MAP || {};
                            this.dynamicBaseRates = config.BASE_RATES || {};
                            
                            if (this.dynamicBaseRates['RODTEP (%)'] !== undefined) {
                                this.globalRodtepPercent = parseFloat(this.dynamicBaseRates['RODTEP (%)']) || 0;
                            }
                            if (this.dynamicBaseRates['Incentive (%)'] !== undefined) {
                                this.globalIncentivePercent = parseFloat(this.dynamicBaseRates['Incentive (%)']) || 0;
                            }
                        } catch (e) {
                            console.error('Error parsing JSON Config', e);
                        }
                    }
                }
            })
            .catch(error => {
                console.error('Error fetching Rate Card Config', error);
            });
    }

    isStandardNASeries(standard) {
        if (!standard) return false;
        return standard.startsWith('ASTM') || standard === 'AS 1163' || standard === 'EN 10219';
    }

    initializePipes() {
        if (this.savedPipes && this.savedPipes.length > 0) {
            
            this.globalCurrencyCode = this.savedPipes[0].currency_code || this.savedPipes[0].currencyCode || 'USD';
            this.globalExchangeRate = this.savedPipes[0].exchange_rate || this.savedPipes[0].exchangeRate || 1.0;
            
            this.pipeCount = this.savedPipes.length;
            this.pipes = this.savedPipes.map((savedPipe, index) => {
                let pipe = this.createEmptyPipe(index);
                
                pipe.steelType = savedPipe.steel_type || savedPipe.steelType || 'Black Steel';
                pipe.designationOptions = this.getDesignationOptions(pipe.steelType);
                
                pipe.designation = savedPipe.pipe_designation || savedPipe.designation || 'MS ERW';
                
                let savedStd = savedPipe.standard || savedPipe.standardSpecGrade || 'ASTM A53';
                if (savedStd === 'AS 1163/EN 10219') savedStd = 'AS 1163'; 
                pipe.standardSpecGrade = savedStd;
                
                pipe.manualStandard = savedPipe.manual_standard || '';
                pipe.grade = savedPipe.grade || 'Grade A';
                pipe.sizeNb = savedPipe.size_nb || savedPipe.sizeNb || '';
                pipe.od = savedPipe.od || 0;
                pipe.customOD = savedPipe.custom_od || savedPipe.customOD || 0;
                pipe.wallThickness = savedPipe.wall_thickness || savedPipe.wallThickness || 0;
                pipe.endFinish = savedPipe.end_finish || savedPipe.endFinish || 'Plain End';
                pipe.pipeLength = savedPipe.pipe_length || savedPipe.pipeLength || 1;
                pipe.totalPieces = savedPipe.total_pieces || savedPipe.totalPieces || 1;
                
                pipe.uom = savedPipe.uom || savedPipe.priceInputType || 'MT';
                
                // Retrieve native INR rate seamlessly (no forced shields, just direct retrieval)
                let savedRate = savedPipe.ratePerKgInr !== undefined ? savedPipe.ratePerKgInr : (savedPipe.price_inr || savedPipe.ratePerKgFc || savedPipe.price_fc || savedPipe.priceFc);
                if (savedRate === undefined || savedRate === null) {
                    savedRate = this.dynamicBaseRates[pipe.steelType] || 0;
                }
                pipe.ratePerKgInr = savedRate;

                // Tolerance respects standard mapping (no forced 0 for MT)
                pipe.maxTolerance = GRADE_TOLERANCE_MAP[pipe.grade] || 10.0;
                pipe.tolerance = savedPipe.tolerance !== undefined ? savedPipe.tolerance : pipe.maxTolerance;
                
                pipe.quotedPriceFc = savedPipe.quotedPriceFc || savedPipe.quoted_price_fc;
                pipe.discountPercent = savedPipe.discountPercent || savedPipe.discount_percent || 0;
                pipe.hasCustomQuotedPrice = !!pipe.quotedPriceFc;

                pipe.pricePerMt = savedPipe.pricePerMt || savedPipe.price_per_mt_fc || 0;
                pipe.costPriceFc = savedPipe.costPriceFc || 0;

                pipe.freightType = savedPipe.freight_type || savedPipe.freightType || 'FOB';
                
                pipe.ihc = savedPipe.ihc || 0;
                pipe.freightFc = savedPipe.freightFc || 0;
                pipe.containerTonnage = savedPipe.containerTonnage || 25; 
                pipe.commissionPercent = savedPipe.commissionPercent || 0;
                pipe.inspectionCharges = savedPipe.inspectionCharges || 0;
                pipe.otherCharges = savedPipe.otherCharges || 0;
                
                pipe.showGrade = (pipe.standardSpecGrade && pipe.standardSpecGrade.startsWith('ASTM'));
                pipe.showManualStandard = ['AS 1074', 'EN 10255', 'BS 1387', 'AS 1163', 'EN 10219', 'ASTM A 135', 'ASTM A 500', 'ASTM A 795', 'EN 39'].includes(pipe.standardSpecGrade);
                
                let isAstm = pipe.standardSpecGrade && pipe.standardSpecGrade.startsWith('ASTM');
                let isNaSeries = this.isStandardNASeries(pipe.standardSpecGrade);
                
                pipe.isAstm = isAstm;
                pipe.seriesShape = isNaSeries ? 'NA' : (savedPipe.shape || savedPipe.seriesShape || 'Manual');
                pipe.isSeriesDisabled = this.isReadOnly || isNaSeries;
                
                if (isNaSeries) {
                    pipe.seriesOptions = [{ label: 'NA', value: 'NA' }];
                } else {
                    pipe.seriesOptions = this.getSeriesOptions(pipe.standardSpecGrade);
                }
                
                if (isAstm) {
                    pipe.scheduleOptions = this.getScheduleOptions(pipe.standardSpecGrade);
                    pipe.schedule = savedPipe.schedule || 'Schedule 40';
                } else {
                    pipe.schedule = savedPipe.schedule || '';
                }
                
                let isSeriesManual = (pipe.seriesShape === 'Manual' || pipe.schedule === 'Manual');
                pipe.isSeriesManual = isSeriesManual;
                pipe.isManualSize = isSeriesManual || (savedPipe.isManualSize === true) || (pipe.sizeNb === 'Manual');
                pipe.isOdReadOnly = !pipe.isManualSize;
                pipe.isThicknessReadOnly = !pipe.isManualSize;
                if (!pipe.isManualSize && !pipe.isAstm && pipe.seriesShape !== 'NA') {
                    pipe.isThicknessReadOnly = true;
                }
                
                pipe.sizeOptions = this.getSizeOptions(pipe.standardSpecGrade, pipe.seriesShape, pipe.schedule);
                
                this.calculatePipe(pipe);
                return pipe;
            });
        } else {
            this.pipes = [];
            for (let i = 0; i < this.pipeCount; i++) {
                let p = this.createEmptyPipe(i);
                this.calculatePipe(p);
                this.pipes.push(p);
            }
        }
    }

    createEmptyPipe(index) {
        const defaultStandard = 'ASTM A53';
        const defaultSchedule = 'Schedule 40';
        const defaultSeriesShape = 'NA';
        const defaultSteelType = 'Black Steel';

        return {
            id: index,
            key: `pipe_${index}_${Date.now()}`,
            
            steelType: defaultSteelType,
            designation: 'MS ERW',
            standardSpecGrade: defaultStandard,
            showManualStandard: false,
            manualStandard: '',
            showGrade: true,
            grade: 'Grade A',
            sizeNb: '',
            od: 0,
            customOD: 0,
            seriesShape: defaultSeriesShape,
            isSeriesDisabled: true,
            isThicknessReadOnly: true,
            isOdReadOnly: true,
            isManualSize: false,
            isSeriesManual: false,
            wallThickness: 0,
            
            isAstm: true,
            scheduleOptions: this.getScheduleOptions(defaultStandard), 
            schedule: defaultSchedule,
            
            endFinish: 'Plain End',
            pipeLength: 1,
            totalPieces: 1,
            kgPerMeter: 0,
            totalMeters: 0,
            totalWeight: 0,
            
            uom: 'MT',
            ratePerKgInr: this.dynamicBaseRates[defaultSteelType] || 0,

            tolerance: GRADE_TOLERANCE_MAP["Grade A"] || 10.0,
            maxTolerance: GRADE_TOLERANCE_MAP["Grade A"],
            costPriceFc: 0,
            cutoffPriceFc: 0,
            quotedPriceFc: 0,
            discountPercent: 0,
            hasCustomQuotedPrice: false,

            pricePerPiece: 0,
            pricePerMt: 0, 
            pricePerMeter: 0,
            totalFobFc: 0,
            totalFobInr: 0,
            freightType: 'FOB',
            
            ihc: 0,
            freightFc: 0,
            containerTonnage: 25, 
            commissionPercent: 0,
            inspectionCharges: 0,
            otherCharges: 0,
            
            rodtepPercent: this.globalRodtepPercent,
            incentivePercent: this.globalIncentivePercent,
            incentiveAddon: 0,
            rodtepAddon: 0,
            netFobInrCalc: 0,
            netFobFcCalc: 0,
            freightCost: 0,
            commissionValue: 0,
            cfr: 0,
            
            steelTypeOptions: STEEL_TYPE_OPTIONS,
            designationOptions: this.getDesignationOptions(defaultSteelType),
            standardOptions: STANDARD_OPTIONS,
            gradeOptions: GRADE_OPTIONS,
            seriesOptions: [{ label: 'NA', value: 'NA' }],
            sizeOptions: this.getSizeOptions(defaultStandard, defaultSeriesShape, defaultSchedule), 
            endFinishOptions: END_FINISH_OPTIONS,
            uomOptions: UOM_OPTIONS,
            freightOptions: FREIGHT_OPTIONS
        };
    }

    normalizeCatalogStandard(s) {
        if (!s) return s;
        const primary = s.split('~')[0].trim();
        if (primary.includes('EN 10255')) return 'EN 10255';
        else if (primary.includes('AS1074') || primary === 'AS 1074') return 'AS 1074';
        else if (primary.includes('BS 1387') || primary.includes('BS1387')) return 'BS 1387';
        else if (primary.includes('ASTM A53') || primary.includes('ASTM A 53') || 
                 primary.includes('ASTM A 135') || primary.includes('ASTM A 500') || primary.includes('ASTM A 795')) return 'ASTM A53';
        else if (primary.includes('ISO 65') || primary.includes('ISO65')) return 'EN 10255';
        else if (primary.includes('AS 1163')) return 'AS 1163';
        else if (primary.includes('EN 10219')) return 'EN 10219';
        return primary;
    }

    normalizeWeightMapStandard(s) {
        if (!s) return null;
        const lower = s.toLowerCase().replace(/\s/g, '');
        if (lower.includes('en10255')) {
            return (keyStd) => keyStd.toLowerCase().replace(/\s/g, '').includes('en10255') ||
                               keyStd.toLowerCase().replace(/\s/g, '').includes('bs1387');
        } else if (lower.includes('as1074') || lower === 'as1074') {
            return (keyStd) => keyStd.toLowerCase().replace(/\s/g, '').includes('as1074');
        } else if (lower.includes('bs1387')) {
            return (keyStd) => keyStd.toLowerCase().replace(/\s/g, '').includes('bs1387') ||
                               keyStd.toLowerCase().replace(/\s/g, '').includes('en10255');
        } else if (lower.includes('astma53') || lower.includes('astm a53') || 
                   lower.includes('astma135') || lower.includes('astma500') || lower.includes('astma795')) {
            return (keyStd) => keyStd.toLowerCase().replace(/\s/g, '').includes('astma53');
        } else if (lower.includes('iso65') || lower.includes('iso 65')) {
            return (keyStd) => {
                const k = keyStd.toLowerCase().replace(/\s/g, '');
                return k.includes('iso65') || k.includes('en10255');
            };
        } else if (lower.includes('as1163') || lower.includes('en10219')) {
            return (keyStd) => keyStd.toLowerCase().replace(/\s/g, '').includes('as1163') || keyStd.toLowerCase().replace(/\s/g, '').includes('en10219');
        }
        return (keyStd) => keyStd.toLowerCase().replace(/\s/g, '') === lower;
    }

    getScheduleOptions(standard) {
        const options = new Set();
        const matcher = this.normalizeWeightMapStandard(standard);
        
        if (matcher) {
            Object.keys(this.WEIGHT_MAP).forEach(k => {
                const parts = k.split('|');
                if (matcher(parts[0])) {
                    if (parts.length >= 3 && parts[2].includes('Schedule')) {
                        options.add(parts[2]);
                    } else if (parts.length >= 2 && parts[1].includes('Schedule')) {
                        options.add(parts[1]);
                    }
                }
            });
        }
        
        Object.keys(CATALOG_MAP).forEach(k => {
            const parts = k.split('|');
            if (parts[0].includes('ASTM') && parts[1].includes('Schedule')) {
                options.add(parts[1]);
            }
        });
        
        const arr = Array.from(options).sort((a, b) => {
            const numA = parseInt(a.replace(/\D/g, '')) || 0;
            const numB = parseInt(b.replace(/\D/g, '')) || 0;
            return numA - numB;
        }).map(s => ({ label: s, value: s }));
        
        arr.push({ label: 'Manual', value: 'Manual' });
        return arr;
    }

    getSeriesOptions(standard) {
        if (standard === 'EN 39') {
            return [
                { label: 'Type-3', value: 'Type-3' },
                { label: 'Type-4', value: 'Type-4' },
                { label: 'Manual', value: 'Manual' }
            ];
        }
        const matcher = this.normalizeWeightMapStandard(standard);
        if (!matcher) return SERIES_OPTIONS;

        const seriesSet = new Set();
        const lowerStd = standard.toLowerCase().replace(/\s/g, '');
        
        Object.keys(this.WEIGHT_MAP).forEach(k => {
            const parts = k.split('|');
            if (parts.length < 4) return;
            if (matcher(parts[0])) {
                if (lowerStd.includes('as1163') || lowerStd.includes('en10219')) {
                    seriesSet.add(parts[2]); 
                } else {
                    seriesSet.add(parts[1]); 
                }
            }
        });

        Object.keys(CATALOG_MAP).forEach(k => {
            const parts = k.split('|');
            if (parts.length < 3) return;
            if (matcher(parts[0])) {
                seriesSet.add(parts[1]);
            }
        });

        if (lowerStd.includes('bs1387') || lowerStd.includes('en10255') || lowerStd.includes('iso65')) {
            seriesSet.delete('L1');
            seriesSet.delete('L2');
            seriesSet.delete('Light 1');
            seriesSet.delete('Light 2');
        } else if (lowerStd.includes('as1074')) {
            seriesSet.delete('L1');
            seriesSet.delete('L2');
            seriesSet.delete('Light 1');
            seriesSet.delete('Light 2');
        }

        if (seriesSet.size === 0) return SERIES_OPTIONS;

        const order = ['Light', 'Light 1', 'Light 2', 'L1', 'L2', 'Medium', 'Heavy', 'Default'];
        const sorted = [];
        order.forEach(s => { if (seriesSet.has(s)) sorted.push(s); });
        seriesSet.forEach(s => { if (!sorted.includes(s)) sorted.push(s); });
        sorted.push('Manual');

        return sorted.map(s => ({ label: s, value: s }));
    }

    getSizeOptions(standard, series, schedule) {
        if (standard === 'EN 39') {
            return [{ label: '48.3', value: '48.3' }, { label: 'Manual', value: 'Manual' }];
        }
        
        if (standard === 'AS 1163' || standard === 'EN 10219') {
            const list = Object.keys(AS1163_OD_MAP).map(v => ({ label: v, value: v }));
            list.push({ label: 'Manual', value: 'Manual' });
            return list;
        }
        
        const matcher = this.normalizeWeightMapStandard(standard);
        if (!matcher) return [];

        const sizes = new Set();
        const lower = standard.toLowerCase().replace(/\s/g, '');
        
        let isAstm = lower.includes('astm');
        let targetFilter = isAstm ? schedule : series;

        Object.keys(this.WEIGHT_MAP).forEach(k => {
            const parts = k.split('|');
            if (parts.length < 4) return;
            if (!matcher(parts[0])) return;
            
            if (targetFilter && targetFilter !== 'Manual' && targetFilter !== 'NA') {
                if (lower.includes('as1163') || lower.includes('en10219')) {
                    if (parts[2] !== targetFilter) return;
                } else {
                    if (parts[1] !== targetFilter) return;
                }
            }
            
            const nbRaw = parts[3] || '';
            const nb = nbRaw.replace(/mm$/i, '').trim();
            if (nb) sizes.add(nb);
        });

        Object.keys(CATALOG_MAP).forEach(k => {
            const parts = k.split('|');
            if (parts.length < 3) return;
            if (!matcher(parts[0])) return;
            
            if (targetFilter && targetFilter !== 'Manual' && targetFilter !== 'NA') {
                if (parts[1] !== targetFilter) {
                    return; 
                }
            }
            
            const nb = parts[2];
            if (nb) sizes.add(nb);
        });

        let arr = Array.from(sizes)
            .map(v => parseFloat(v))
            .filter(v => !isNaN(v))
            .sort((a, b) => a - b)
            .map(v => {
                let labelStr = v + '';
                if (standard === 'EN 10255' && EN_10255_SIZE_MAP[v]) {
                    labelStr = EN_10255_SIZE_MAP[v];
                }
                return { label: labelStr, value: v + '' };
            });

        if (arr.length === 0) {
            arr = [15, 20, 25, 32, 40, 50, 65, 80, 100, 125, 150].map(v => {
                let labelStr = v + '';
                if (standard === 'EN 10255' && EN_10255_SIZE_MAP[v]) {
                    labelStr = EN_10255_SIZE_MAP[v];
                }
                return { label: labelStr, value: v + '' };
            });
        }
        arr.push({ label: 'Manual', value: 'Manual' });
        return arr;
    }

    handleGlobalCurrencyChange(event) {
        this.globalCurrencyCode = event.target.value;
    }

    handleGlobalExchangeRateChange(event) {
        this.globalExchangeRate = parseFloat(event.target.value) || 0;
        this.pipes = this.pipes.map(pipe => {
            this.calculatePipe(pipe);
            return pipe;
        });
    }

    handleApply() {
        const configuredPipes = this.pipes.map(pipe => {
            let unitRate = 0;
            if (pipe.uom === 'MT') {
                unitRate = pipe.pricePerMt;
            } else if (pipe.uom === 'Meters') {
                unitRate = pipe.pricePerMeter;
            } else if (pipe.uom === 'Pieces') {
                unitRate = pipe.pricePerPiece;
            }

            return {
                steelType: pipe.steelType,
                designation: pipe.designation,
                standardSpecGrade: pipe.standardSpecGrade,
                manualStandard: pipe.manualStandard,
                grade: pipe.grade,
                sizeNb: pipe.sizeNb,
                od: pipe.od,
                seriesShape: pipe.seriesShape,
                wallThickness: pipe.wallThickness,
                schedule: pipe.schedule,
                isManualSize: pipe.isManualSize,
                endFinish: pipe.endFinish,
                pipeLength: pipe.pipeLength,
                totalPieces: pipe.totalPieces,
                kgPerMeter: pipe.kgPerMeter,
                totalMeters: pipe.totalMeters,
                totalWeight: pipe.totalWeight,
                
                uom: pipe.uom,
                priceInputType: pipe.uom, 
                
                currencyCode: this.globalCurrencyCode,
                exchangeRate: this.globalExchangeRate,
                
                ratePerKgInr: pipe.ratePerKgInr,
                priceFc: unitRate, 
                
                tolerance: pipe.tolerance,
                costPriceFc: pipe.costPriceFc, 
                cutoffPriceFc: pipe.cutoffPriceFc, 
                quotedPriceFc: pipe.quotedPriceFc, 
                discountPercent: pipe.discountPercent,
                
                pricePerPiece: pipe.pricePerPiece,
                pricePerMt: pipe.pricePerMt,
                pricePerMeter: pipe.pricePerMeter,
                totalFobFc: pipe.totalFobFc,
                totalFobInr: pipe.totalFobInr,
                freightType: pipe.freightType,
                
                ihc: pipe.ihc,
                freightFc: pipe.freightFc,
                containerTonnage: pipe.containerTonnage,
                commissionPercent: pipe.commissionPercent,
                inspectionCharges: pipe.inspectionCharges,
                otherCharges: pipe.otherCharges,
                
                rodtepPercent: pipe.rodtepPercent,
                incentivePercent: pipe.incentivePercent,
                incentiveAddon: pipe.incentiveAddon,
                rodtepAddon: pipe.rodtepAddon,
                netFobInrCalc: pipe.netFobInrCalc,
                netFobFcCalc: pipe.netFobFcCalc,
                freightCost: pipe.freightCost,
                commissionValue: pipe.commissionValue,
                cfr: pipe.cfr
            };
        });

        this.dispatchEvent(new CustomEvent('saveconfig', {
            detail: {
                pipes: configuredPipes
            }
        }));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('closemodal'));
    }

    handlePipeCountChange(event) {
        let val = parseInt(event.target.value, 10);
        if (isNaN(val) || val < 1) val = 1;
        this.pipeCount = val;
        
        if (this.pipes.length < this.pipeCount) {
            for (let i = this.pipes.length; i < this.pipeCount; i++) {
                let p = this.createEmptyPipe(i);
                this.calculatePipe(p);
                this.pipes.push(p);
            }
        } else if (this.pipes.length > this.pipeCount) {
            this.pipes = this.pipes.slice(0, this.pipeCount);
        }
    }

    toggleCalculations() {
        this.showCalculations = !this.showCalculations;
    }

    _activeScroller = null;
    _scrollTimeout = null;

    disconnectedCallback() {
        if (this._scrollTimeout) {
            clearTimeout(this._scrollTimeout);
        }
    }

    _setScroller(scroller) {
        this._activeScroller = scroller;
        if (this._scrollTimeout) {
            clearTimeout(this._scrollTimeout);
        }
        this._scrollTimeout = setTimeout(() => {
            this._activeScroller = null;
        }, 150);
    }

    handleTopPointerDown() {
        this._setScroller('top');
    }

    handleTablePointerDown() {
        this._setScroller('table');
    }

    handleTableWheel() {
        this._setScroller('table');
    }

    handleTopScroll(event) {
        if (this._activeScroller === 'table') {
            return;
        }
        this._setScroller('top');
        const table = this.template.querySelector('.table-scroll');
        if (table && table.scrollLeft !== event.target.scrollLeft) {
            table.scrollLeft = event.target.scrollLeft;
        }
    }

    handleTableScroll(event) {
        if (this._activeScroller === 'top') {
            return;
        }
        this._setScroller('table');
        const topScroll = this.template.querySelector('.top-scrollbar-track');
        if (topScroll && topScroll.scrollLeft !== event.target.scrollLeft) {
            topScroll.scrollLeft = event.target.scrollLeft;
        }
    }

    handleScrollLeft() {
        const table = this.template.querySelector('.table-scroll');
        if (table) {
            this._setScroller('table');
            table.scrollBy({ left: -600, top: 0, behavior: 'smooth' });
        }
    }

    handleScrollRight() {
        const table = this.template.querySelector('.table-scroll');
        if (table) {
            this._setScroller('table');
            table.scrollBy({ left: 600, top: 0, behavior: 'smooth' });
        }
    }

    handleScrollToSection(event) {
        const section = event.currentTarget.dataset.section;
        const table = this.template.querySelector('.table-scroll');
        if (!table) return;

        this._setScroller('table');

        let targetPos = 0;
        if (section === 'specs') {
            targetPos = 0;
        } else if (section === 'cfr') {
            const targetTh = this.template.querySelector('th[data-col-section="cfr"]');
            if (targetTh) {
                const stickyHeader = this.template.querySelector('.table-scroll th:first-child');
                const stickyWidth = stickyHeader ? stickyHeader.offsetWidth : 110;
                const tableRect = table.getBoundingClientRect();
                const thRect = targetTh.getBoundingClientRect();
                targetPos = Math.max(0, thRect.left - tableRect.left + table.scrollLeft - stickyWidth);
            } else {
                targetPos = table.scrollWidth;
            }
        } else {
            const targetTh = this.template.querySelector(`th[data-col-section="${section}"]`);
            if (targetTh) {
                const stickyHeader = this.template.querySelector('.table-scroll th:first-child');
                const stickyWidth = stickyHeader ? stickyHeader.offsetWidth : 110;
                const tableRect = table.getBoundingClientRect();
                const thRect = targetTh.getBoundingClientRect();
                targetPos = Math.max(0, thRect.left - tableRect.left + table.scrollLeft - stickyWidth);
            } else {
                const fallbackMap = {
                    specs: 0,
                    charges: 1900,
                    pricing: this.showCalculations ? 3400 : 2700,
                    cfr: table.scrollWidth
                };
                targetPos = fallbackMap[section] || 0;
            }
        }

        table.scrollTo({
            left: targetPos,
            top: table.scrollTop,
            behavior: 'smooth'
        });
    }

    handleAddRow() {
        this.pipeCount = this.pipes.length + 1;
        let newPipe = this.createEmptyPipe(this.pipes.length);
        this.calculatePipe(newPipe);
        this.pipes.push(newPipe);
        this.pipes = [...this.pipes];
    }

    handleDeleteRow(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (!isNaN(index) && index >= 0 && index < this.pipes.length) {
            if (this.pipes.length === 1) {
                let p = this.createEmptyPipe(0);
                this.calculatePipe(p);
                this.pipes = [p];
            } else {
                this.pipes.splice(index, 1);
                this.pipes = this.pipes.map((pipe, idx) => {
                    pipe.id = idx;
                    pipe.key = `pipe_${idx}_${Date.now()}`;
                    return pipe;
                });
                this.pipeCount = this.pipes.length;
            }
        }
    }

    handleSwitchToSizeDropdown(event) {
        const index = parseInt(event.target.dataset.index, 10);
        let pipe = this.pipes[index];
        if (!pipe) return;
        pipe.isManualSize = false;
        pipe.isOdReadOnly = true;
        pipe.isThicknessReadOnly = true;
        pipe.sizeNb = '';
        pipe.od = 0;
        pipe.wallThickness = 0;
        this.calculatePipe(pipe);
        this.pipes = [...this.pipes];
    }

    handleFieldChange(event) {
        const fieldName = event.target.dataset.field;
        const index = parseInt(event.target.dataset.index, 10);
        const value = event.target.value;

        let pipe = this.pipes[index];
        pipe[fieldName] = value;

        if (['ratePerKgInr', 'tolerance', 'grade', 'pipeLength', 'totalPieces', 'wallThickness', 'od', 'customOD', 'uom'].includes(fieldName)) {
            pipe.hasCustomQuotedPrice = false;
        }

        if (fieldName === 'steelType') {
            pipe.designationOptions = this.getDesignationOptions(value);
            if (!pipe.designationOptions.find(opt => opt.value === pipe.designation)) {
                pipe.designation = pipe.designationOptions.length > 0 ? pipe.designationOptions[0].value : '';
            }
            pipe.ratePerKgInr = this.dynamicBaseRates[value] || 0;
            pipe.hasCustomQuotedPrice = false;
        } 
        else if (fieldName === 'standardSpecGrade') {
            pipe.showGrade = (value && value.startsWith('ASTM'));
            pipe.showManualStandard = ['AS 1074', 'EN 10255', 'BS 1387', 'AS 1163', 'EN 10219', 'ASTM A 135', 'ASTM A 500', 'ASTM A 795', 'EN 39'].includes(value);
            
            let isAstm = value && value.startsWith('ASTM');
            pipe.isAstm = isAstm;
            let isNaSeries = this.isStandardNASeries(value);
            
            if (isNaSeries) {
                pipe.seriesShape = 'NA';
                pipe.seriesOptions = [{ label: 'NA', value: 'NA' }];
                pipe.isSeriesDisabled = this.isReadOnly || true;
            } else {
                pipe.seriesOptions = this.getSeriesOptions(value);
                pipe.seriesShape = pipe.seriesOptions.find(opt => opt.value === 'Medium')?.value || (pipe.seriesOptions.length > 0 ? pipe.seriesOptions[0].value : 'Manual');
                pipe.isSeriesDisabled = this.isReadOnly || false;
            }
            
            if (isAstm) {
                pipe.scheduleOptions = this.getScheduleOptions(value);
                pipe.schedule = pipe.scheduleOptions.some(opt => opt.value === 'Schedule 40') ? 'Schedule 40' : (pipe.scheduleOptions.length > 0 ? pipe.scheduleOptions[0].value : 'Manual');
            } else {
                pipe.schedule = '';
            }
            
            let isSeriesManual = (pipe.seriesShape === 'Manual' || pipe.schedule === 'Manual');
            pipe.isSeriesManual = isSeriesManual;
            pipe.isManualSize = isSeriesManual;
            pipe.isOdReadOnly = !isSeriesManual;
            pipe.isThicknessReadOnly = !isSeriesManual;
            
            pipe.sizeNb = '';
            pipe.od = 0;
            pipe.wallThickness = 0;
            pipe.sizeOptions = this.getSizeOptions(value, pipe.seriesShape, pipe.schedule);
            
        } else if (fieldName === 'seriesShape') {
            let isManual = (value === 'Manual');
            pipe.isSeriesManual = isManual;
            pipe.isManualSize = isManual;
            pipe.isOdReadOnly = !isManual;
            pipe.isThicknessReadOnly = !isManual;
            if (!isManual && value !== 'NA') {
                pipe.isThicknessReadOnly = true;
            }
            pipe.sizeNb = '';
            if (isManual) {
                pipe.od = 0;
                pipe.wallThickness = 0;
            }
            pipe.sizeOptions = this.getSizeOptions(pipe.standardSpecGrade, value, pipe.schedule);
            
        } else if (fieldName === 'schedule') {
            if (pipe.isAstm) {
                let isManual = (value === 'Manual');
                pipe.isSeriesManual = isManual;
                pipe.isManualSize = isManual;
                pipe.isOdReadOnly = !isManual;
                pipe.isThicknessReadOnly = !isManual;
                if (isManual) {
                    pipe.od = 0;
                    pipe.wallThickness = 0;
                }
            }
            pipe.sizeNb = '';
            pipe.sizeOptions = this.getSizeOptions(pipe.standardSpecGrade, pipe.seriesShape, value);
            
        } else if (fieldName === 'sizeNb') {
            if (value === 'Manual') {
                pipe.isManualSize = true;
                pipe.sizeNb = '';
                pipe.isOdReadOnly = false;
                pipe.isThicknessReadOnly = false;
                pipe.od = 0;
                pipe.wallThickness = 0;
            }
        } else if (fieldName === 'grade') {
            pipe.maxTolerance = GRADE_TOLERANCE_MAP[value] || 10.0;
            if (pipe.tolerance > pipe.maxTolerance) {
                pipe.tolerance = pipe.maxTolerance;
            }
        }
        
        if (['standardSpecGrade', 'seriesShape', 'schedule', 'sizeNb'].includes(fieldName)) {
            if (!pipe.isManualSize) {
                let s = this.normalizeCatalogStandard(pipe.standardSpecGrade || '');
                let series = pipe.seriesShape;
                let schedule = pipe.schedule;
                let sizeRaw = pipe.sizeNb ? pipe.sizeNb + '' : '';
                let size = sizeRaw.replace(/mm$/i, '').trim();
                size = size ? parseInt(size, 10) + '' : '';

                if (s === 'EN 39') {
                    pipe.od = 48.3;
                    if (series === 'Type-3') pipe.wallThickness = 3.2;
                    else if (series === 'Type-4') pipe.wallThickness = 4.0;
                } else if (s === 'AS 1163' || s === 'EN 10219') {
                    if (AS1163_OD_MAP[size]) {
                        pipe.od = AS1163_OD_MAP[size].od;
                        if (series !== 'Manual') {
                            pipe.wallThickness = AS1163_OD_MAP[size].wt;
                        }
                    } else {
                        pipe.od = 0;
                        if (series !== 'Manual') {
                            pipe.wallThickness = 0;
                        }
                    }
                } else if (s.includes('ASTM')) {
                    let key = s + '|' + schedule + '|' + size;
                    let fallbackKey = s + '|Schedule 40|' + size; 
                    
                    if (CATALOG_MAP[key]) {
                        pipe.od = CATALOG_MAP[key].od;
                        if (schedule !== 'Manual') pipe.wallThickness = CATALOG_MAP[key].wt;
                    } else if (CATALOG_MAP[fallbackKey]) {
                        pipe.od = CATALOG_MAP[fallbackKey].od;
                        if (schedule !== 'Manual') pipe.wallThickness = 0; 
                    }
                } else {
                    let key = s + '|' + series + '|' + size;
                    if (CATALOG_MAP[key]) {
                        pipe.od = CATALOG_MAP[key].od;
                        if (series !== 'Manual') {
                            pipe.wallThickness = CATALOG_MAP[key].wt;
                        }
                    } else {
                        let fallbackKey = s + '||' + size;
                        if (CATALOG_MAP[fallbackKey]) {
                            pipe.od = CATALOG_MAP[fallbackKey].od;
                            if (series !== 'Manual') {
                                pipe.wallThickness = CATALOG_MAP[fallbackKey].wt;
                            }
                        }
                    }
                }
            }
        }

        if (fieldName === 'tolerance') {
            let val = parseFloat(value) || 0;
            let inputField = event.target;

            // 👉 NEW: Show an error if the value exceeds the maximum allowed
            if (val > pipe.maxTolerance) {
                inputField.setCustomValidity(`Tolerance cannot exceed ${pipe.maxTolerance}%`);
                inputField.reportValidity();
                val = pipe.maxTolerance; // Forces the calculation back down so it won't take the higher value
            } else {
                inputField.setCustomValidity(''); // Clears the error if the value is fixed
                inputField.reportValidity();
            }
            
            pipe.tolerance = val;
        }

        if (fieldName === 'quotedPriceFc') {
            if (value === null || value === '' || value === undefined) {
                pipe.quotedPriceFc = null;
                pipe.hasCustomQuotedPrice = true;
            } else {
                pipe.quotedPriceFc = parseFloat(value) || 0;
                pipe.hasCustomQuotedPrice = true;
            }
        }

        if (['pipeLength', 'totalPieces', 'wallThickness', 'od', 'customOD', 'ratePerKgInr', 'ihc', 'freightFc', 'containerTonnage', 'commissionPercent', 'inspectionCharges', 'otherCharges'].includes(fieldName)) {
            pipe[fieldName] = parseFloat(value) || 0;
        }

       

        this.calculatePipe(pipe);
        this.pipes = [...this.pipes];
    }

    handleQuotedPriceBlur(event) {
        if (this.isReadOnly) { return; }
        const index = parseInt(event.target.dataset.index, 10);
        const pipe = this.pipes[index];
        if (!pipe) { return; }

        if (pipe.quotedPriceFc === null || pipe.quotedPriceFc === undefined || pipe.quotedPriceFc === '') {
            pipe.hasCustomQuotedPrice = false;
        }
        this.calculatePipe(pipe);
        this.pipes = [...this.pipes];
    }

    calculatePipe(pipe) {
        let activeOd = pipe.customOD > 0 ? pipe.customOD : pipe.od;
        let rawKg = (activeOd - pipe.wallThickness) * pipe.wallThickness * 0.0246615;
        if (isNaN(rawKg)) rawKg = 0;
        pipe.kgPerMeter = Number(Math.max(0, rawKg).toFixed(3));
        
        pipe.totalMeters = pipe.pipeLength * pipe.totalPieces;
        pipe.totalWeight = (pipe.totalMeters * pipe.kgPerMeter) / 1000;
        
        // 1. Exchange Rate and Base Rates
        let exRate = this.globalExchangeRate > 0 ? this.globalExchangeRate : 1.0;
        let baseRateKgInr = parseFloat(pipe.ratePerKgInr) || 0;
        let ratePerKgFc = baseRateKgInr / exRate;

        // 2. Freight Distribution
        let freightPerMtFc = (pipe.containerTonnage && pipe.containerTonnage > 0)
            ? ((parseFloat(pipe.freightFc) || 0) / pipe.containerTonnage) 
            : 0;
            
        pipe.freightCost = Number(freightPerMtFc.toFixed(2));
        let freightPerKgFc = freightPerMtFc / 1000;

        // 3. Combined True Cost per KG
        let totalCostPerKgFc = ratePerKgFc + freightPerKgFc;

        // 4. Dynamic UOM Multiplier
        let uomMultiplier = 1000; 
        if (pipe.uom === 'Meters') {
            uomMultiplier = pipe.kgPerMeter;
        } else if (pipe.uom === 'Pieces') {
            uomMultiplier = pipe.kgPerMeter * pipe.pipeLength;
        }

        // 5. Cost Price (FC) - Dynamically scales to UOM
        pipe.costPriceFc = Number((totalCostPerKgFc * uomMultiplier).toFixed(2));

        // 6. Apply Tolerance directly to the UOM Cost Price 
        let tol = parseFloat(pipe.tolerance) || 0;
        pipe.cutoffPriceFc = Number((pipe.costPriceFc * (1 - (tol / 100))).toFixed(2));

        // 7. Quoted Price defaults to Cutoff
        if (!pipe.hasCustomQuotedPrice) {
            pipe.quotedPriceFc = pipe.cutoffPriceFc;
        }

        // 👉 NEW: Auto-calculate Discount % based on the active Quoted Price vs Cost Price
        if (pipe.costPriceFc > 0 && pipe.quotedPriceFc > 0) {
            pipe.discountPercent = Number((((pipe.costPriceFc - pipe.quotedPriceFc) / pipe.costPriceFc) * 100).toFixed(2));
        } else {
            pipe.discountPercent = 0;
        }

        let activePriceFc = pipe.quotedPriceFc || 0; 
        
        // 8. Reverse map active price to other UOM metrics for display
        let activePricePerKgFc = uomMultiplier > 0 ? activePriceFc / uomMultiplier : 0;

        pipe.pricePerMt = Number((activePricePerKgFc * 1000).toFixed(2));
        pipe.pricePerMeter = Number((activePricePerKgFc * pipe.kgPerMeter).toFixed(2));
        pipe.pricePerPiece = (pipe.totalPieces && pipe.totalPieces > 0)
            ? Number(((pipe.pricePerMt * pipe.totalWeight) / pipe.totalPieces).toFixed(2))
            : 0;
        
        // 9. Total Value Calculations
        let totalFobFc = activePricePerKgFc * (pipe.totalWeight * 1000);
        pipe.totalFobFc = Number(totalFobFc.toFixed(2));
        
        pipe.totalFobInr = Number((totalFobFc * exRate).toFixed(2));
        
        pipe.rodtepAddon = Number((pipe.totalFobInr * ((pipe.rodtepPercent || 0) / 100.0)).toFixed(2));
        pipe.incentiveAddon = Number((pipe.totalFobInr * ((pipe.incentivePercent || 0) / 100.0)).toFixed(2));

        pipe.netFobInrCalc = Number((pipe.totalFobInr + pipe.incentiveAddon + pipe.rodtepAddon).toFixed(2));
        pipe.netFobFcCalc = exRate > 0 ? Number((pipe.netFobInrCalc / exRate).toFixed(2)) : 0;

        pipe.commissionValue = Number((pipe.netFobFcCalc * ((pipe.commissionPercent || 0) / 100.0)).toFixed(2));

        let totalFreightFc = freightPerMtFc * pipe.totalWeight;
        let calculatedCfr = pipe.netFobFcCalc + totalFreightFc + pipe.commissionValue + (parseFloat(pipe.inspectionCharges) || 0) + (parseFloat(pipe.otherCharges) || 0);
        
        pipe.cfr = Number(calculatedCfr.toFixed(2));
    }
}