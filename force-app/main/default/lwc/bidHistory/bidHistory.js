import { LightningElement, api, wire } from 'lwc';
import getBidHistory from '@salesforce/apex/BidController.getBidHistory';
import { refreshApex } from '@salesforce/apex';

export default class BidHistory extends LightningElement {
    @api listingId;
    bids = [];
    wiredResult;

    @wire(getBidHistory, { listingId: '$listingId' })
    wiredBids(result) {

        this.wiredResult = result;

        const { data, error } = result;

        if (data) {
            this.bids = data;
        } else if (error) {
            console.error(error);
        }
    }

    @api
    refreshHistory() {
        return refreshApex(this.wiredResult);
    }
}