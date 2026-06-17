public with sharing class BidController {



    public class BidWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String bidderName { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String listingId { get; set; }
    }


    public class BidHistoryWrapper {
        @AuraEnabled public String bidderName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Datetime bidTime;
        @AuraEnabled public Boolean isHighest;
    }

    @AuraEnabled(cacheable=true)
    public static List<BidHistoryWrapper> getBidHistory(
        String listingId
    ) {
        List<Bid__c> bids = [
            SELECT Id,
                Bidder_Name__c,
                Amount__c,
                CreatedDate
            FROM Bid__c
            WHERE Auction_Listing__c = :listingId
            ORDER BY Amount__c DESC
        ];

        List<BidHistoryWrapper> results =
            new List<BidHistoryWrapper>();

        Boolean first = true;

        for (Bid__c bid : bids) {
            BidHistoryWrapper wrapper =
                new BidHistoryWrapper();

            wrapper.bidderName = bid.Bidder_Name__c;
            wrapper.amount = bid.Amount__c;
            wrapper.bidTime = bid.CreatedDate;
            wrapper.isHighest = first;

            results.add(wrapper);
            first = false;
        }

        return results;
    }

    @AuraEnabled
    public static BidWrapper placeBid(
        String listingId,
        String bidderName,
        Decimal amount
    ) {
        if (String.isBlank(listingId) || String.isBlank(bidderName) || amount == null) {
            throw new AuraHandledException('All fields are required.');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            Auction_Listing__c listing = [
                SELECT Id, Status__c, Current_Bid__c, Starting_Price__c, Title__c
                FROM Auction_Listing__c
                WHERE Id = :listingId
                LIMIT 1
                FOR UPDATE
            ];

            if (listing.Status__c != 'Active') {
                throw new AuraHandledException('This auction is not active.');
            }

            Decimal threshold = listing.Current_Bid__c != null
                ? listing.Current_Bid__c
                : listing.Starting_Price__c;

            if (amount <= threshold) {
                throw new AuraHandledException(
                    'Bid must be greater than the current bid of ' + threshold
                );
            }

            // Create bid history record
            Bid__c bid = new Bid__c(
                Auction_Listing__c = listing.Id,
                Bidder_Name__c = bidderName,
                Amount__c = amount,
                Bid_Time__c = System.now()
            );

            insert bid;


            listing.Current_Bid__c = amount;
            listing.Current_Bidder__c = bidderName;
            update listing;

            Bid_Placed__e evt = new Bid_Placed__e(
                Listing_Id__c = listing.Id,
                Bidder_Name__c = bidderName,
                New_Bid_Amount__c = amount,
                Title__c = listing.Title__c
            );
            EventBus.publish(evt);

            BidWrapper result = new BidWrapper();
            result.id = listing.Id;
            result.bidderName = bidderName;
            result.amount = amount;
            result.listingId = listing.Id;
            return result;

        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Failed to place bid: ' + e.getMessage());
        }
    }
}