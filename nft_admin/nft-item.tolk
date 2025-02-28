//  TON NFT Item Smart Contract
//

/*

    NOTE that this tokens can be transferred within the same workchain.

    This is suitable for most tokens, if you need tokens transferable between workchains there are two solutions:

    1) use more expensive but universal function to calculate message forward fee for arbitrary destination (see `misc/forward-fee-calc.cs`)

    2) use token holder proxies in target workchain (that way even 'non-universal' token can be used from any workchain)

*/

tolk 0.8

import "@stdlib/gas-payments"
import "@stdlib/tvm-dicts"
import "op-codes.tolk"
import "errors.tolk"
import "nft_helpers.tolk"
import "gas.tolk"
import "../messages.tolk"
import "../constants.tolk"
import "../utils.tolk"

@pure
@inline
fun minTonsForStorage(): int {
    return ONECOIN;
}


const NOT_INITIALIZED = 0;
const AWAIT_INIT  = 1;
const INITIALIZED = 2;

//
//  Storage
//
//  uint64 index
//  MsgAddressInt collection_address
//  MsgAddressInt owner_address
//  cell content
//

@inline
fun loadData(): (int, int, slice, slice, cell, int, int) {
    var ds: slice = getContractData().beginParse();
    var (status, index, collectionAddress) = (ds.loadUint(4), ds.loadUint(32), ds.loadAddress());

    if (status == NOT_INITIALIZED) {
      return (status, index, collectionAddress, null, null, 0, 0); // nft not initialized yet
    } else {
      // Supply data
      var sd = ds.loadRef().beginParse();

      var balance   = sd.loadCurrency();
      var maxSupply = sd.loadCurrency();

      return (status, index, collectionAddress, ds.loadAddress(), ds.loadRef(), balance, maxSupply);
    }
}

@inline
fun updateStatus(status: int) {
    setContractData(
        beginCell()
            .storeUint(status, 4)
            .storeSlice(getContractData().beginParse().skipBits(4))
        .endCell()
    );
}

@inline
fun updateContent(newContent: cell) {
    var ds = getContractData().beginParse();
    var balances = ds.loadRef();
    ds.loadRef(); // drop old content

    setContractData(
        beginCell()
            .storeSlice(ds)
            .storeRef(balances)
            .storeRef(newContent)
        .endCell()
    );
}

@inline
fun storeData(status: int, index: int, collectionAddress: slice, ownerAddress: slice, content: cell, balance: int, maxSupply: int) {

    // Theoretically may not fit in the cell otherwise
    var supplyData = beginCell().storeCurrency(balance).storeCurrency(maxSupply).endCell();

    setContractData(
        beginCell()
            .storeUint(status, 4) // 4
            .storeUint(index, 32) // 32
            .storeSlice(collectionAddress) // 267
            .storeSlice(ownerAddress) // 267
            .storeRef(supplyData)
            .storeRef(content)
       .endCell()
    );
}

@inline
fun updateBalance(balance: int) {
    var ds = getContractData().beginParse();

    var sd = ds.loadRef().beginParse();
    var curBalance  = sd.loadCurrency();

    setContractData(
        beginCell()
            .storeRef(beginCell().storeCurrency(balance).storeSlice(sd).endCell())
            .storeSlice(ds)
        .endCell()
    );
}

@inline
fun sendMsg(toAddress: slice, amount: int, op: int, queryId: int, payload: builder, sendMode: int) {
  var msg = beginCell()
    .storeUint(0x10, 6) // nobounce - int_msg_info$0 ihr_disabled:Bool bounce:Bool bounced:Bool src:MsgAddress -> 010000
    .storeSlice(toAddress)
    .storeCoins(amount)
    .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
    .storeUint(op, 32)
    .storeUint(queryId, 64)
    .storeBuilder(payload);

  sendRawMessage(msg.endCell(), sendMode);
}

/*
@inline
fun transferOwnership(myBalance: int, index: int, collectionAddress: slice, ownerAddress: slice, content: cell, senderAddress: slice, queryId: int, inMsgBody: slice, fwdFees: int) {
    assert(isSliceBitsEqual(senderAddress, ownerAddress)) throw 401;

    var newOwnerAddress: slice = inMsgBody.loadAddress();
    // forceChain(newOwnerAddress);
    var responseDestination: slice = inMsgBody.loadAddress();
    inMsgBody.loadInt(1); // this nft don't use custom_payload
    var forwardAmount: int = inMsgBody.loadCoins();
    assert(getRemainingBitsCount(inMsgBody) >= 1) throw 708;

    var restAmount: int = myBalance - minTonsForStorage();
    if (forwardAmount) {
      restAmount -= (forwardAmount + fwdFees);
    }
    var needResponse: bool = responseDestination.preloadUint(2) != 0; // if NOT addr_none: 00
    if (needResponse) {
      restAmount -= fwdFees;
    }

    assert(restAmount >= 0) throw 402; // base nft spends fixed amount of gas, will not check for response

    if (forwardAmount) {
      sendMsg(newOwnerAddress, forwardAmount, ownership_assigned, queryId, beginCell().storeSlice(ownerAddress).storeSlice(inMsgBody), 1);  // paying fees, revert on errors
    }
    if (needResponse) {
      // forceChain(responseDestination);
      sendMsg(responseDestination, restAmount, excesses, queryId, null, 1); // paying fees, revert on errors
    }

    storeData(index, collectionAddress, newOwnerAddress, content);
}
*/

@inline
fun sendMintExtra(index: int, version: int, amount: int,  reserve: int, minterAddr: int, refundPayload: cell, queryId: int) {

    var msgBody = beginCell()
                    .storeMessageOp(OP_MINT)
                    .storeMessageQueryId(queryId)
                    .storeUint(version, 8)
                    .storeUint(index, 32)
                    .storeCurrency(amount)
                    .storeMaybeRef(refundPayload)
                  .endCell();

    var msgMint = beginCell()
          .storeUint(BOUNCEABLE, 6)
          .storeUint(0x4ff, 11) // 10 = address pfx, 0 = no anycast, -1 = int8 workchain_id -> 0b10011111111
          .storeUint(minterAddr, 256)
          .storeCoins(0)
          .storeOnlyBodyRef(msgBody)
          .endCell();

    reserveEc(reserve, null, RESERVE_IN_ADDITION | RESERVE_AT_MOST);
    sendRawMessage(msgMint, SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}



@inline_ref
fun refundMint(refund: slice, index: int, errCode: int, queryId: int) {
    var refundMsg = beginCell()
                      .storeUint(NON_BOUNCEABLE, 6)
                      .storeSlice(refund)
                      .storeCoins(0)
                      .storePrefixOnlyBody()
                      .storeMessageOp(OP_REFUND_MINT)
                      .storeMessageQueryId(queryId)
                      .storeUint(index, 32)
                      .storeUint(errCode, 10)
                    .endCell();
    sendRawMessage(refundMsg, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
}

@inline
fun sendBurnNotification(to: slice, from: slice, refund: slice, amount: int, forwardTon: int, payload: cell, queryId: int) {

    var msgBody = beginCell()
                    .storeMessageOp(OP_BURN_NOTIFICATION)
                    .storeMessageQueryId(queryId)
                    .storeCurrency(amount)
                    .storeSlice(from)
                    .storeSlice(refund)
                    .storeMaybeRef(payload)
                 .endCell();
    var burnMsg = beginCell()
                    .storeUint(BOUNCEABLE, 6)
                    .storeSlice(to)
                    .storeCoins(forwardTon)
                    .storeOnlyBodyRef(msgBody)
                  .endCell();
    sendRawMessage(burnMsg, SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

@inline_ref
fun processTransfer(body: slice, to: slice, refund: slice, index: int, transferAmount: int, balance: int, fwdFee: int, msgValue: int, queryId: int) {
    balance -= transferAmount;
    assert(balance >= 0, NOT_ENOUGH_EC);
    var forwardTon = body.loadCoins();
    // 3/2 because of EC dictionary being added
    assert(msgValue >= mulDivFloor(fwdFee, 3, 2) + forwardTon + calculateGasFee(NFT_WORKCHAIN, MINT_GAS), NOT_ENOUGH_GAS);
    var forwardPayload = body.checkEitherForwardPayload();
    sendEc(to, refund, index, transferAmount, forwardTon, forwardPayload, queryId);
    updateBalance(balance);
}

@inline
fun sendEc(to: slice, refund: slice, index: int, amount: int, tonAmount: int, payload: slice, queryId: int) {
    var currenciesToSend: cell = createEmptyDict();
    currenciesToSend.uDictSetBuilder(32, index, beginCell().storeCurrency(amount));

    var body  = beginCell().storeMessageOp(OP_OUT_EC)
                           .storeMessageQueryId(queryId)
                           .storeSlice(payload)
                .endCell();

    var ecMsg = beginCell()
                 .storeUint(BOUNCEABLE, 6)
                 .storeSlice(to)
                 .storeCoins(tonAmount)
                 .storeBodyRefWithEc(body, currenciesToSend);


    var (wc, hash, isStandard) = refund.isStandardAddress();

    var sendMode: int = isStandard ? SEND_MODE_PAY_FEES_SEPARATELY : SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE;

    sendRawMessage(ecMsg.endCell(), sendMode | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

    if(isStandard) {
        sendExcess(OP_EXCESS, 0, refund, currenciesToSend, queryId, RESERVE_EXCEPT, 0);
    }
}

fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {

    if (inMsgBody.isEndOfSlice()) { // ignore empty messages
        return;
    }

    var cs: slice = inMsgFull.beginParse();
    var flags: int = cs.loadUint(4);

    var senderAddress: slice = cs.loadAddress();

    cs.loadAddress(); // skip dst
    cs.loadCoins(); // skip value

    var minterAddr: int = getBlockchainConfigParam(MinterAddressConfig).beginParse().preloadUint(256);

    var (status: int, index: int, collectionAddress: slice, ownerAddress: slice, content: cell, balance: int, maxSupply: int) = loadData();

    if (flags & 1) {
        // If bounce is from minter
        var (workchain, bareSender) = parseStandardAddress(senderAddress);
        assert((workchain == -1) && (bareSender == minterAddr), INVALID_SENDER);
        // Should not be possible, but just in case
        assert(status != INITIALIZED, ALREADY_INITED);

        inMsgBody.skipBouncedPrefix();
        var op = inMsgBody.loadUint(32);

        assert(op == OP_MINT, 0xffff);

        updateStatus(NOT_INITIALIZED);

        refundMint(collectionAddress, index, 0, 0);
        return;
    }

    var extraIn = cs.loadDict(); // Load extra currency if any

    cs.loadCoins(); // skip ihr_fee
    var fwdFee: int = calculateOriginalMessageFee(MY_WORKCHAIN, cs.loadCoins());

    var op: int = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);

    if(op == OP_MINT_INITIAL) {
      assert(isSliceBitsEqual(collectionAddress, senderAddress), INVALID_SENDER);

      var collectionVersion = inMsgBody.loadUint(8);
      var owner: slice    = inMsgBody.loadAddress();
      var mintAmount: int = inMsgBody.loadCurrency();
      var refundAddress = inMsgBody.loadAddress();
      content = inMsgBody.loadRef();


      var (wc, hash, isStandardRefund) = refundAddress.isStandardAddress();

      try {
        assert(status == NOT_INITIALIZED, ALREADY_INITED);
        var refundPayload: builder = beginCell();
        var balanceBefore: int  = myBalance - msgValue;
        var mintPriceList: cell = getBlockchainConfigParam(6);
        assert(mintPriceList != null, ERROR_NO_PARAM_6);

        var ps: slice = mintPriceList.beginParse();
        // Pick maximum possible fee from config
        msgValue -= max(ps.loadCoins(), ps.loadCoins());

        // No need for 3/2 because of we have StateInit incomming at this point.
        msgValue -= fwdFee * 6;

        // Account for storage fee
        var reserveTon: int = getMyStorageDuePayment() + abs(min(0, balanceBefore - minTonsForStorage()));

        msgValue -= reserveTon;

        msgValue -= calculateGasFee(NFT_WORKCHAIN, MINT_INITIAL_GAS) +
                    calculateGasFee(NFT_WORKCHAIN, ITEM_MINTED_GAS);

        assert(msgValue > 0, ERROR_UNCOVERED_FEE);

        if(isStandardRefund) {
            refundPayload.storeUint(1, 1).storeSlice(refundAddress);
        } else {
            refundPayload.storeUint(0, 1);
        }

        sendMintExtra(index, collectionVersion, mintAmount, reserveTon, minterAddr, refundPayload.endCell(), queryId);

        storeData(AWAIT_INIT, index, collectionAddress, owner, content, mintAmount, mintAmount);
      } catch (errCode) {
          refundMint(collectionAddress, index, errCode, queryId);
      }

      return;
    }

    if(op == OP_MINTED) {
      var (workchain, bareSender) = parseStandardAddress(senderAddress);
      assert((workchain == -1) && (bareSender == minterAddr), INVALID_SENDER);
      try {
          assert(status == AWAIT_INIT, NOT_INITED);

          assert(index == inMsgBody.loadUint(32), INVALID_INDEX);
          var mintAmount = inMsgBody.loadCurrency();

          assert(mintAmount == maxSupply, INVALID_SUPPLY);
          assert(mintAmount == extraIn.getEcAmount(index), NOT_ENOUGH_EC);

          var ps = inMsgBody.loadRef().beginParse();

          if(ps.loadUint(1)) {
              sendExcess(OP_EXCESS, 0, ps.loadAddress(), extraIn, queryId, 0, 0);
          }

          updateStatus(INITIALIZED);
      } catch (errCode) {
          updateStatus(NOT_INITIALIZED);
          refundMint(collectionAddress, index, errCode, queryId);
      }

      return;
    }

    if(op == OP_RESET) {
      assert(isSliceBitsEqual(collectionAddress, senderAddress), INVALID_SENDER);

      var resetIdx = inMsgBody.loadUint(32);
      var refundAddress = inMsgBody.loadAddress();

      try {
          // Allow only when not fully initialized
          assert(status != INITIALIZED, ALREADY_INITED);
          assert(index == resetIdx, INVALID_INDEX);
          updateStatus(NOT_INITIALIZED);
          sendExcess(OP_EXCESS, 0, refundAddress, null, queryId, 0, 0);
      } catch (errCode) {
          sendExcess(OP_FAILED, 0, refundAddress, extraIn, queryId, 0, errCode);
      }
      return;
    }

    if (op == OP_TOP_UP) {
        return;
    }

    assert(status == INITIALIZED, NOT_INITED);

    if (op == OP_UPDATE_CONTENT) {
        assert(isSliceBitsEqual(collectionAddress, senderAddress), INVALID_SENDER);

        var content = inMsgBody.loadRef();
        var updateIdx = inMsgBody.loadUint(32);
        var refund  = inMsgBody.loadAddress();

        try {
            assert(balance == maxSupply, ALREADY_MINTED);
            assert(index == updateIdx, INVALID_INDEX);

            updateContent(content);

            var (wc, hash, standard) = refund.isStandardAddress();
            if(!standard) {
                refund = senderAddress;
            }

            sendExcess(OP_EXCESS, 0, refund, extraIn, queryId, 0, 0);
        } catch(errCode) {
            sendExcess(OP_FAILED, 0, refund, extraIn, queryId, 0, errCode);
        }
        return;
    }

    // In order to be pluggable in place of common jetton minter
    if (op == OP_MINT_JETTON) {
        // Mimic common jetton mint payload

        assert(isSliceBitsEqual(ownerAddress, senderAddress), INVALID_SENDER);
        var toAddress: slice = inMsgBody.loadAddress();
        var tonAmount = inMsgBody.loadCoins();
        var masterMsg = inMsgBody.loadRef();
        inMsgBody.assertEndOfSlice();

        // see internal_transfer TL-B layout in jetton.tlb
        var masterMsgSlice: slice = masterMsg.beginParse();
        assert(masterMsgSlice.loadMessageOp() == OP_INTERNAL_TRANSFER, INVALID_MESSAGE);
        masterMsgSlice.skipMessageQueryId();
        var transferAmount = masterMsgSlice.loadCoins();
        masterMsgSlice.loadAddress(); // Skip from
        var refund = masterMsgSlice.loadAddress();
        processTransfer(masterMsgSlice, toAddress, refund, index, transferAmount, balance, fwdFee, msgValue, queryId);

        return;
    }
    // In order to retain compatibility gonna have to carry the jetton scheme
    if (op == OP_MINT_EC) {
        assert(isSliceBitsEqual(ownerAddress, senderAddress), INVALID_SENDER);
        var transferAmount = inMsgBody.loadCurrency();

        var to = inMsgBody.loadAddress();
        var refund = inMsgBody.loadAddress();

        inMsgBody.skipMaybeRef(); // Skip custom

        processTransfer(inMsgBody, to, refund, index, transferAmount, balance, fwdFee, msgValue, queryId);
        return;
    }

    if(op == OP_BURN_EC) {
        var forwardTon = inMsgBody.loadCoins();
        assert(msgValue >= forwardTon + fwdFee + calculateGasFee(NFT_WORKCHAIN, BURN_GAS), NOT_ENOUGH_GAS);

        // Extra cell has more than one element
        assert(extraIn.getCellDepth() == 0, INVALID_EC);

        var burnAmount = getEcAmount(extraIn, index);
        assert(burnAmount > 0, NOT_ENOUGH_EC);

        balance += burnAmount;
        assert(balance <= maxSupply, INVALID_SUPPLY);
        updateBalance(balance);

        var refund  = inMsgBody.loadAddress();
        var payload = inMsgBody.loadMaybeRef();

        sendBurnNotification(ownerAddress, senderAddress, refund, burnAmount, forwardTon, payload, queryId);

        var (wc, hash, isStandard) = refund.isStandardAddress();

        if(isStandard) {
            sendExcess(OP_EXCESS, 0, refund, extraIn, queryId, 0, 0);
        }

        return;
    }

    if(op == OP_WITHDRAW_EXCESS) {
        var isOwner: bool = isSliceBitsEqual(ownerAddress, senderAddress);
        var isCollection: bool = false;

        if(!isOwner) {
            isCollection = isSliceBitsEqual(collectionAddress, senderAddress);
        }

        assert(isOwner || isCollection, INVALID_SENDER);
        var ecBalance: int = 0;
        var reserveEc:cell = createEmptyDict();

        if(inMsgBody.loadUint(1)) {
        	var withdrawCur = inMsgBody.loadUint(32);
        	/*
        	* Fool proof. Not alowing to ocasionally withdraw current EC.
        	* Should use regular transfer instread
        	*/
        	assert(withdrawCur != index, INVALID_EC);
        	ecBalance = getEcAmount(getRawEc(), withdrawCur);
        	assert(ecBalance > 0, NOT_ENOUGH_EC);
                reserveEc.packEc(withdrawCur, ecBalance);
        } else {
        	reserveEc = getRawEc();
        	// Removing current EC from reserve dictionary, allowing to withdraw everything else
        	reserveEc.uDictDelete(32, index);
        }

        var to = inMsgBody.loadAddress();
        // Allow withdraw TON balance only from owner
        var fromBalance: int = 0;

        if(isOwner) {
            fromBalance = inMsgBody.loadCoins();

            if(fromBalance > 0) {
                    fromBalance = min(fromBalance, myBalance - msgValue - minTonsForStorage());
                    assert(fromBalance > 0, BALANCE_BELOW_STORAGE);
            }
        }

        var (wc, hash, isStd) = isStandardAddress(to);
        assert(isStd, INVALID_ADDRESS);

        sendExcess(OP_EXCESS, fromBalance, to, reserveEc, queryId, RESERVE_EXCEPT, 0);
        // sendExcess(fromBalance, RESERVE_MODE | RESERVE_EXCEPT, reserveEc, excesses, queryId, 0, to);
        return;
    }
    if(op == OP_REBALANCE) {
        var inAmount = getEcAmount(extraIn, index);
        var actualBalance = getEcAmount(getRawEc(), index) - inAmount;

        if(actualBalance != balance) {
            updateBalance(actualBalance);
        }

        sendExcess(OP_EXCESS, 0, senderAddress, null, queryId, 0, 0);

        return;
    }

    /*
    if (op == transfer) {
      transferOwnership(myBalance, index, collectionAddress, ownerAddress, content, senderAddress, queryId, inMsgBody, fwdFee);
      return;
    }
    */

    if (op == get_static_data) {
      sendMsg(senderAddress, 0, report_static_data, queryId, beginCell().storeUint(index, 256).storeSlice(collectionAddress), 64);  // carry all the remaining value of the inbound message
      return;
    }

    throw 0xffff;
}

//
//  GET Methods
//

get get_nft_data(): (bool, int, slice, slice, cell) {
  var (status: int, index: int, collectionAddress: slice, ownerAddress: slice, content: cell, _, _) = loadData();

  return (status == INITIALIZED, index, collectionAddress, ownerAddress, content);
}

get get_jetton_data(): (int, bool, slice, cell, cell) {
  var (status: int, index: int, collectionAddress: slice, ownerAddress: slice, content: cell, balance, maxSupply) = loadData();

  assert(status == INITIALIZED, NOT_INITED);

  return (maxSupply - balance, true, ownerAddress, content, null);
}

get get_extended_data() {
    return loadData();
}
