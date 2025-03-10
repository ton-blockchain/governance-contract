# NFT Minter description

Purpose of NFT minter collection is to replace 
initial idea of extra currency id -> minter admin map

``` TL-B
authorization_config$_ admin_map:(Hashmap 32 MsgAddress) = AuthorizationConfig
```

with NFT collection which items serve as an admin right for the
extra currency id matching items index.

## Authorization config

In order to be able to migrate from one collection version to another,
authorization config now would look like this:

``` TL-B

authorization_record$_
collection_address:MsgAddress
owner_address:MsgAddress // Collection owner
max_items:uint32
item_code:^Cell = AuthorizationRecord;

authorization_config$_ collection_map:(Hashmap 8 AuthorizationRecord) = AuthorizationConfig;
```
Minter collection is added to authorization config by it's 8 bit version number.

Collection authorization record holds enough information to authenticate [item](https://github.com/Trinketer22/governance-contract/blob/nft_minter/minter.tolk#L106-L107) of the
[collection](https://github.com/Trinketer22/governance-contract/blob/nft_minter/minter.tolk#L80-L82)
and also allows to change item limit and collection owner via config update.

On every tx collection [caches](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L60-L62) parameters from [config](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L39) in order to
maintain bounce handling and item search functionality in case of
authorization config becomes malformed or collection removed from it.

In such event, administrative functionality will be [disabled](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L181)
while bounce/refund handling remain functional.

In case of version migration is in order, one could add additional versions to the config, while
previous versions still will be able to authenticate on the minter contract.

**NOTE** that removing collection address from authorization config
does not affect it's items functionality. *Should it?*

## Collection functionality

- New item [mint](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L183)
- [Update](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L211) item content
- [Reset](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L226) item status
- [Withdraw](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L239) excess EC/TON

## Item mint process

New item request is initiated by the [new item message](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tlb#L65-L75)

Collection checks that request came from [owner](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L179)
and collection is [allowed](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L184]) to mint more items.

Also, preliminary  [gas checks](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L181) are performed.

If conditions met, minted items count is increased and [mint_initial](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tlb#L65) message is sent to the new item.

### Item mint initial

Upon [receiving](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L340) mint initial, item:

- Checks that it is not yet [initialized](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L353)
- Performs gas [checks](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L381)
- Saves content and owner to [state](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L383) and sets status to `AWAIT_INIT`

If all conditions met, initiates the [mint protocol](https://github.com/Trinketer22/governance-contract/blob/nft_minter/minter.tolk#L5) by [sending](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L379) mint message to the minter contract deducting 1 TON for storage expenses.

**NOTE** that for simplicity, all of the supply is requested to be minted to item
at once.

#### Minted

In case mint protocol executed successfully, item checks:

- Item [expects](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L395) mint response
- Request came from [minter address](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L393)
- That mint response is intended for it's [index](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L397)
- Incoming EC value [matches](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L400-L401) expected values

In case all conditions are met:

- Status is [set](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L409) to `INITIALIZED`
- TON refund is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L406) to the address from refund payload (if any)

After that, minter holds `maxSupply` and becomes essentially vault for the
extra currency.

Otherwise, status is rolled [back](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L411) and [mint refund](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tlb#L77-L78) message is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L412) to the collection
carrying all of the incoming extra currency and TON.

Collection than [rolls back](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L161) the item counter and [proxies](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L167) the
value to owner.

#### Mint initial failure

In case mint failed on the item part, [mint refund](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tlb#L77-L78) message is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L385) to the collection.

Collection than [rolls back](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L161) the item counter and [proxies](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L167) the
value to owner.
.
Same happens if item [bounced](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L147) prior to the try block.

## Item functionality

- Mint initial (described above)
- [Mint extra](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L442)
- Mint extra in [jetton fashion](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L468)
- [Burn](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L502) extra.
- [Rebalance](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L572)
- [Reset](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L418) item status.
- [Update](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L442) item content
- [Withdraw excess](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L524) extra and TON.
- [Top up](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L436)
- [Get static data](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L592)
- [Get nft data](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L604)
- [Get jetton data](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L610)


**NOTE** that **TRANSFER** is not available. *Should it be?*

### Mint extra

During mint extra operation, owner is allowed
to withdraw extra from the item balance by sending [mint_ec](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L70-L76) message.

Item checks that:

- Message [came](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L490) from the owner.
- Item has [enough](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L253) extra balance 
- Enough value is [attached](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L256), including forwardTonAmount

If all conditions met:
- Remaining balance is [updated](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L259)
- [out_ec](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L99) message is sent to the destination address.

### Mint extra in jetton minter style

This mode is added in order for zero modifications
replacement between jetton minter and extra minter
to be possible.

Item checks the [origin](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L471) of the message, parses the [internal transfer](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L479) payload,
that is a typical part of the jetton mint message,
extracts relevant fields, and passes to same [handler](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L484),
meaning that all subsequent behavior is same to the regular mint extra.

**NOTE** that jetton mint is not really standardized action,
but most of minters are compatible with this schema.

### Burn

Burn, in essence, is and operation of returning
the extra with [burn_ec](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L78-L82) payload to the item balance, that may trigger
[burn notification](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L84-L88) to be sent to the item owner.

Anyone holding extra currency with the id, matching item id, , should be able to trigger
burn action.

Item checks that:

- Message [contains](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L504) enough value to cover for GAS + forwardTon amount.
- Message [contains](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L509) positive amount of extra with matching id
- Item balance will not [exceed](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L512-L513) max supply after this operation. (*Should we remove that?*)

In case conditions are met, balance is [updated](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L514) and burn notification is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L519) to the owner.

Bounce otherwise.

### Rebalance

In order to explain rebalance operation, it is necessary
to explain why the item extra balance is stored in contract data,
rather than using actual account balance.

Thing is that extra balance is a hashmap, thus looking up it's
values consumes non-constant amount of gas.
To ensure balance lookup is constant, we replace
map lookup with reading value from data.

Still it is possible that account balance will hold
more extra, than the value accounted in data.
For example if extra was sent to it without the TON value.

In such case, rebalance operation will lookup the account balance
dictionary and update the balance data.
Anyone should be able to trigger rebalance op,
however incoming extra value (if any) is [deducted](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L573-L574) from the
account balance, to rule out any manipulations.

In case resulting balance is different
from the stored one, stored one is [updated](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L577)

And excess is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L580) back to the sender.

### Reset item status

This functionality is required
for the theoretical case of something breaking down
during the [mint protocol](https://github.com/Trinketer22/governance-contract/blob/nft_minter/minter.tolk#L5) without any message to the item.

In that case, item will be stuck with `AWAIT_INITED` status.

To address this, admin must be able to send [reset_item](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tlb#L87-L89) message to the collection,
triggering [reset](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L48-L50) on the item specified by index. 

Collection should [check](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L179) that message came from collection owner and
[send](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L235) the reset message to the item by the specified index.

Item would check that:

- Reset request is from collection
- Request is addressed to [correct](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L427)  item index
- Item is not yet [initialized](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L426)

In case conditions met, status is [updated](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L428) and excess is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L429) to refund address specified.

Otherwise, [failed](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L102) message, containing relevant error code is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L431) to the refund address specified

### Update item content

Item content update is allowed when no
supply is yet taken from the item.

In order to update item content,
collection owner should send [update item content](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tlb#L82-L85) message
to the collection.

Collection should [check](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L179) that message came from collection owner
and [send](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-collection.tolk#L221) the [update content](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L54-L57) message to the relevant item.

Item should check that:

- Message [came](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L443) from collection
- No extra in [circulation](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L450)
- Message is addressed to the [correct]()https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L451index

In case conditions met, content is [updated](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L453) and excess is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L460) to refund address specified.

Otherwise, [failed](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L102) message, containing relevant error code is [sent](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L462) to the refund address specified

### Withdraw excess

Withdraw excess operation allows to withdraw
excess TON or extra from the item balance.

Operation is triggered by the [withdraw excess](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tlb#L91-L95) message sent from item owner.
Where `specific` flag indicates weather specific extra should be withdrawn, or
otherwise all extra except one with the item index is withdrawn.

Item checks that request [came](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L532) from either owner or collection
address.

Withdraw from balance is [only](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L553-L557) allowed from owner address and storage
reserve is [taken](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L560-L561) into account.
Withdraw destination address [has to](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L566) be standard.

In case conditions are met, specified currencies are [withdrawn](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L568) to the destination
address specified.

**NOTE** That withdrawn item excess from collection is not
yet implemented on the collection side, because it is not
clear if it is really necessary.

### Top up

Top up allows anybody to send value to the contract
[without](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L437) any further processing.

### Get static data

`get_static_data` is a [standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md#2-get_static_data) NFT operation to discover item
address by index

### Get nft data

`get_nft_data` is a [standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md#get-methods) NFT get method. 

### Get jetton data

`get_jetton_data` is a [standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md#get-methods-1) jetton get method.

Worth to note that it is [only](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L613) available when
item is fully initialized and
circulating supply is [deducted](https://github.com/Trinketer22/governance-contract/blob/nft_minter/nft_admin/nft-item.tolk#L615) as `maxSupply - balance`.
