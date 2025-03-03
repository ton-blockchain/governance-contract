tolk 0.8

import "@stdlib/tvm-dicts"
import "@stdlib/gas-payments"
import "params.tolk"
import "op-codes.tolk"
import "errors.tolk"
import "config.tolk"
import "nft_helpers.tolk"
import "gas.tolk"
import "../constants.tolk"
import "../messages.tolk"
import "../utils.tolk"
// NFT collection smart contract

// storage scheme
// default#_ royalty_factor:uint16 royalty_base:uint16 royalty_address:MsgAddress = RoyaltyParams;
// storage#_ owner_address:MsgAddress 
//           nft_item_code:^Cell
//           royalty_params:^RoyaltyParams
//           = Storage;

global loadStatus: int;

@inline
fun loadData(): (slice, int, int, cell, cell) {

  loadStatus = LOAD_SUCCESSFUL;

  try {
      var config = getBlockchainConfigParam(ExtraCurrencyAuthorizationConfig);
      var (cs, found) = config.uDictGet(8, COLLECTION_VERSION);

      assert(found, COLLECTION_NOT_IN_CONFIG);
      assert(isSliceBitsEqual(cs.loadAddress(), getMyAddress()), COLLECTION_ADDRESS_MISMATCH);

      var ds = getContractData().beginParse();
      return 
        (cs.loadAddress(), // owner_address from config
         ds.loadUint(32), // itemCount
         cs.loadUint(32), // Max item count from config
         ds.loadRef(), // collection content
         cs.loadRef() // item code from config
         );
  } catch (errCode) {
    loadStatus = errCode;

    var ds = getContractData().beginParse();
    // In case something is off in loading procedure
    // retain enough data for getMethods to work properly
    var (itemCount, owner, content, code) = (ds.loadUint(32), ds.loadAddress(), ds.loadRef(), ds.loadRef());
    return (owner, itemCount, 0, content, code);
  }
}

@inline
fun saveData(itemCount: int, content: cell, owner: slice, itemCode: cell) {
  setContractData(beginCell()
    .storeUint(itemCount, 32)
    .storeSlice(owner) // backup owner in case of misconfig
    .storeRef(content)
    .storeRef(itemCode) // backup item code
    .endCell());
}

@inline
fun calculateNftAddressByIndex(index: int, nftItemCode: cell) {
    var stateInit: cell = calculateNftItemStateInit(index, nftItemCode, getMyAddress());
    return (calculateNftItemAddress(workchain(), stateInit), stateInit);
}

@inline
fun deployNftItem(itemIndex: int, nftItemCode: cell, amount: int, nftContent: cell) {
  var (nftAddress, stateInit) = calculateNftAddressByIndex(itemIndex, nftItemCode);

  var msg = beginCell()
            .storeUint(BOUNCEABLE, 6)
            .storeSlice(nftAddress)
            .storeCoins(amount)
            .storeUint(4 + 2 + 1, 1 + 4 + 4 + 64 + 32 + 1 + 1 + 1)
            .storeRef(stateInit)
            .storeRef(nftContent);
  return sendMessage(msg.endCell(), SEND_MODE_PAY_FEES_SEPARATELY); // pay transfer fees separately, revert on errors
}

@inline
fun proxyValueTo(to: slice, op: int, queryId: int) {
    var (wc, hash, isStandard) = to.isStandardAddress();

    if(isStandard) {
        var msg = beginCell()
                    .storeUint(NON_BOUNCEABLE, 6)
                    .storeSlice(to)
                    .storeCoins(0)
                    .storePrefixOnlyBody()
                    .storeMessageOp(op)
                    .storeMessageQueryId(queryId);

        sendRawMessage(msg.endCell(), SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
    }
}

@inline
fun updateItemContent(itemIdx: int, refund: slice, nftItemCode: cell, nftContent: cell, queryId: int) {
    var (nftAddress, stateInit) = calculateNftAddressByIndex(itemIdx, nftItemCode);
    var msg = beginCell()
                .storeUint(BOUNCEABLE, 6)
                .storeSlice(nftAddress)
                .storeCoins(0)
                .storePrefixOnlyBody()
                .storeMessageOp(OP_UPDATE_CONTENT)
                .storeMessageQueryId(queryId)
                .storeUint(itemIdx, 32)
                .storeSlice(refund)
                .storeRef(nftContent);

    sendRawMessage(msg.endCell(), SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun resetItem(itemIdx: int, refund: slice, nftItemCode: cell, queryId: int) {
    var (nftAddress, stateInit) = calculateNftAddressByIndex(itemIdx, nftItemCode);
    var msg = beginCell()
                .storeUint(BOUNCEABLE, 6)
                .storeSlice(nftAddress)
                .storeCoins(0)
                .storePrefixOnlyBody()
                .storeMessageOp(OP_RESET)
                .storeMessageQueryId(queryId)
                .storeUint(itemIdx, 32)
                .storeSlice(refund);

    sendRawMessage(msg.endCell(), SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    if (inMsgBody.isEndOfSlice()) { // ignore empty messages
        return;
    }
    var cs: slice = inMsgFull.beginParse();
    var flags: int = cs.loadUint(4);
    
    var (ownerAddress, curCount, maxCount, content, nftItemCode) = loadData();

    if (flags & 1) { // ignore all bounced messages
        inMsgBody.skipBouncedPrefix();
        var op = inMsgBody.loadUint(32);
        if(op == OP_NEW_ITEM) {
            // We won't going to know what item it was, but have to roll back regardless
            assert(curCount > 0, NO_ITEMS);
            saveData(curCount - 1, content, ownerAddress, nftItemCode);
            proxyValueTo(ownerAddress, op, 0);
        }
        return;
    }
    var senderAddress: slice = cs.loadAddress();

    var op: int = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);


    if (op == OP_REFUND_MINT) {
        var index = inMsgBody.loadUint(32);
        var (nftAddress, stateInit) = calculateNftAddressByIndex(index, nftItemCode);

        assert(isSliceBitsEqual(senderAddress, nftAddress), NOT_AN_ITEM);
        assert(curCount > 0, NO_ITEMS);
        proxyValueTo(ownerAddress, op, queryId);
        // Rolling back the item count
        saveData(curCount - 1, content, ownerAddress, nftItemCode);
        return;
    }

    if(op == OP_EXCESS) {
        // return all the incomming excesses to owner
        proxyValueTo(ownerAddress, op, queryId);
        return;
    }

    assert(isSliceBitsEqual(senderAddress, ownerAddress), NOT_COLLECTION_OWNER);
    // Indicate what went wrong
    assert(loadStatus == LOAD_SUCCESSFUL, COLLECTION_MISCONFIG + loadStatus);
    
    if (op == OP_NEW_ITEM) { // deploy new nft
      assert(curCount < maxCount, TOO_MANY_ITEMS);
      var itemIndex: int = inMsgBody.loadUint(32);
      var content = inMsgBody.loadRef();
      var ds = content.beginParse();
      assert(ds.loadMessageOp() == OP_MINT_INITIAL, INVALID_MESSAGE);
      ds.skipBits(64);

      assert(COLLECTION_VERSION == ds.preloadUint(8), INVALID_COLLECTION_VERSION);

      // Duplicating check is implemented in item, but no harm if we can termitate earlier
      var mintPriceList: cell = getBlockchainConfigParam(6);
      assert(mintPriceList != null, ERROR_NO_PARAM_6);

      var tonAmount  = inMsgBody.loadCoins();

      var forwardFee = deployNftItem(itemIndex, nftItemCode, tonAmount, content);
      // Forward fee is for basechain (likely) and most of the forwards are in master, but at least it has enough to bounce.
      var ps: slice = mintPriceList.beginParse();
      assert(tonAmount > max(ps.loadCoins(), ps.loadCoins()) + forwardFee * 6, NOT_ENOUGH_GAS);

      // Paying fees separately, so one forward amount goes here
      var gasRequired = tonAmount + forwardFee + calculateGasFee(NFT_WORKCHAIN, getGasConsumedAtTheMoment() * 2);
      assert(msgValue >= gasRequired, NOT_ENOUGH_GAS);
      saveData(curCount + 1, content, ownerAddress, nftItemCode);
      return;
    }

    if (op == OP_UPDATE_CONTENT) {
        var itemIdx: int = inMsgBody.loadUint(32);
        var refund: slice = inMsgBody.loadAddress();

        var (wc, hash, standard) = isStandardAddress(refund);

        if(!standard) {
            refund = ownerAddress;
        }

        updateItemContent(itemIdx, refund, nftItemCode, inMsgBody.loadRef(), queryId);

        return;
    }

    if (op == OP_RESET) {
        var itemIdx: int = inMsgBody.loadUint(32);
        var refund: slice = inMsgBody.loadAddress();
        var (wc, hash, standard) = isStandardAddress(refund);

        if(!standard) {
            refund = ownerAddress;
        }
        
        resetItem(itemIdx, refund, nftItemCode, queryId);
        return;
    }

    if(op == OP_WITHDRAW_EXCESS_COLLECTION) {
        var ecBalance: int = 0;
        var reserveEc:cell = createEmptyDict();

        if(inMsgBody.loadUint(1)) {
        	var withdrawCur = inMsgBody.loadUint(32);
        	ecBalance = getEcAmount(getRawEc(), withdrawCur);
        	assert(ecBalance > 0, NOT_ENOUGH_EC);
                reserveEc.packEc(withdrawCur, ecBalance);
        } else {
        	reserveEc = getRawEc();
        }

        var to = inMsgBody.loadAddress();
        // Allow withdraw TON balance only from owner

        var fromBalance = inMsgBody.loadCoins();
        if(fromBalance > 0) {
                fromBalance = min(fromBalance, myBalance - msgValue - ONECOIN);
                assert(fromBalance > 0, BALANCE_BELOW_STORAGE);
        }

        var (wc, hash, isStd) = isStandardAddress(to);
        assert(isStd, INVALID_ADDRESS);

        sendExcess(OP_EXCESS, fromBalance, to, reserveEc, queryId, RESERVE_EXCEPT, 0);
        // sendExcess(fromBalance, RESERVE_MODE | RESERVE_EXCEPT, reserveEc, excesses, queryId, 0, to);
        return;
    }

    throw 0xffff;
}

// Get methods

get get_collection_data(): (int, cell, slice) {
  var (ownerAddress, curCount, maxCount, content, nftItemCode) = loadData();
  // var cs: slice = content.beginParse();
  return (-1, content, ownerAddress);
}

get get_collection_data_extended() {
    return (COLLECTION_VERSION, loadData());
}

get get_nft_address_by_index(index: int): slice {
    var (ownerAddress, curCount, maxCount, content, nftItemCode) = loadData();
    var ( address, stateInit ) = calculateNftAddressByIndex(index, nftItemCode);
    return address;
}

get get_nft_content(index: int, individualNftContent: cell): cell {
  /*
  var (_, _, content, _, _) = loadData();
  var cs: slice = content.beginParse();
  cs.loadRef();
  var commonContent: slice = cs.loadRef().beginParse();
  return (beginCell()
                      .storeUint(1, 8) // offchain tag
                      .storeSlice(commonContent)
                      .storeRef(individualNftContent)
          .endCell());
    */
    return individualNftContent;
}
