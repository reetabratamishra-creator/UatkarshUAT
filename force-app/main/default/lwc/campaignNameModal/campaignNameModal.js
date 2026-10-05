import { LightningElement, api } from 'lwc';

export default class CampaignNameModal extends LightningElement {
    @api isOpen = false;
    @api isSending = false;
    @api sendButtonLabel = 'Send';

    campaignName = '';

    get isConfirmDisabled() {
        return this.isSending || !(this.campaignName || '').trim();
    }

    handleCampaignNameChange(event) {
        this.campaignName = event.target.value;
    }

    handleCancel() {
        if (!this.isSending) {
            this.campaignName = '';
            this.dispatchEvent(new CustomEvent('cancel'));
        }
    }

    handleConfirm() {
        const trimmedName = (this.campaignName || '').trim();
        if (!trimmedName || this.isSending) {
            return;
        }

        this.dispatchEvent(
            new CustomEvent('confirm', {
                detail: { campaignName: trimmedName }
            })
        );
    }

    stopModalClick(event) {
        event.stopPropagation();
    }

    @api
    reset() {
        this.campaignName = '';
    }
}