import { LightningElement, api } from 'lwc';

let groupCounter = 0;

export default class CampaignCheckboxMultiSelect extends LightningElement {
    @api label = '';
    @api options = [];

    _value = [];

    groupName = `campaign-cb-${++groupCounter}`;

    @api
    get value() {
        return this._value;
    }

    set value(next) {
        this._value = Array.isArray(next) ? [...next] : [];
    }

    get optionRows() {
        const selected = new Set(this._value || []);
        return (this.options || []).map((option, index) => ({
            label: option.label,
            value: option.value,
            checked: selected.has(option.value),
            inputId: `${this.groupName}-${index}`
        }));
    }

    get hasOptions() {
        return this.optionRows.length > 0;
    }

    get panelClass() {
        let classes = 'checkbox-filter__panel';
        if (this.optionRows.length > 6) {
            classes += ' checkbox-filter__panel_scrollable';
        }
        return classes;
    }

    get listClass() {
        return this.optionRows.length > 3
            ? 'checkbox-filter__list checkbox-filter__list_grid'
            : 'checkbox-filter__list';
    }

    handleCheckboxChange(event) {
        const optionValue = event.target.value;
        const checked = event.target.checked;
        let next = [...(this._value || [])];

        if (checked && !next.includes(optionValue)) {
            next.push(optionValue);
        } else if (!checked) {
            next = next.filter((item) => item !== optionValue);
        }

        this._value = next;

        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: next },
                bubbles: true,
                composed: true
            })
        );
    }
}