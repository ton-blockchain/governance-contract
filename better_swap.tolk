// Problem with simplest swap is as follows:
// Each time we mint extracurrency we update global config, thus create keyblock
// Keyblocks are milestones of blockchain used for fast sync and so on
// Frequent keyblocks will make shards slower, lite-client much more slower
// And in case in-contract lite-clients much more expensive.

// Instead lets keep some spare extracurrency and request to mint more when we are close to depletion.

import "@stdlib/tvm-dicts"
import "constants.tolk"
import "utils.tolk"


const CURRENCY_ID = 100;




fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {

    var inMsgFullSlice: slice = inMsgFull.beginParse();
    var flags: int = inMsgFullSlice.loadUint(4);

    if (flags & 1) {
        return;
    }

    var senderAddress: slice = inMsgFullSlice.loadAddress();

    if (inMsgBody.getRemainingBitsCount() == 0) {
        msgValue -= 3 * ONECOIN;
        assert(msgValue > 0) throw ERROR_UNCOVERED_FEE;
        
        var minterAddr: int = getBlockchainConfigParam(MinterAddressConfig).beginParse().preloadUint(256);
        var queryId: int = getLogicalTime();
        
        var [tonBalance, extraCurrencies] = getMyOriginalBalanceWithExtraCurrencies();
        
        var (currencyBalanceSlice, exist) = extraCurrencies.uDictGet(32, CURRENCY_ID);
        var currencyBalance = 0;
        if(exist) {
          currencyBalance = currencyBalanceSlice.loadCurrency();
        }
        
        var reserveAmount = ONECOIN * ONECOIN;
        var tresholdToRequest = reserveAmount / 10;
        var amountToSend = msgValue;
        var amountToRequest = 0;
        var payload: cell = null;
        
        if (currencyBalance >= amountToSend) {
            var currenciesToSend: cell = createEmptyDict();
            currenciesToSend.iDictSetBuilder(32, CURRENCY_ID, beginCell().storeCurrency(amountToSend));
            var msgWithdrawal = beginCell()
                        .storeUint(NON_BOUNCEABLE, 6)
                        .storeSlice(senderAddress)
                        .storeCoins(0)
                        .storeDict(currenciesToSend)
                        .storeUint(0, 4 + 4 + 64 + 32 + 1 + 1)
                        .endCell();
           sendRawMessage(msgWithdrawal, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
           var currencyBalanceAfter = currencyBalance - amountToSend;
           if ( currencyBalanceAfter > tresholdToRequest) {
             return;
           }
           var alreadyRequested = getContractData().beginParse().loadUint(256);
           if(alreadyRequested > 0) {
             return;
           }
           amountToRequest = reserveAmount - currencyBalanceAfter;
        } else {
            var alreadyRequested = getContractData().beginParse().loadUint(256);
            // do not allow more than one request in-fly
            assert ( alreadyRequested == 0) throw 222;
            payload = beginCell().storeUint(amountToSend, 256).storeSlice(senderAddress).endCell();
        }
        
        setContractData(beginCell().storeUint(amountToRequest, 256).endCell());
        
        var msgMint = beginCell()
              .storeUint(0x10, 6)
              .storeUint(0x4ff, 11) // 10 = address pfx, 0 = no anycast, -1 = int8 workchain_id -> 0b10011111111
              .storeUint(minterAddr, 256)
              .storeCoins(ONECOIN)
              .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
              .storeMessageOp(OP_MINT)
              .storeMessageQueryId(queryId)
              .storeUint(CURRENCY_ID, 32)
              .storeCurrency(amountToRequest)
              .storeMaybeRef(payload)
              .endCell();
        return sendRawMessage(msgMint, 0);
    }
    
    var op: int = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);
    
    //minted#op_minted queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
    if( op == OP_MINTED) {
        var minterAddr: int = getBlockchainConfigParam(MinterAddressConfig).beginParse().preloadUint(256);
        var (workchain, bareSenderAddress) = parseStandardAddress(senderAddress);
        assert( (workchain == -1) && (bareSenderAddress == minterAddr)) throw ERROR_UNAUTHORIZED_MINT_REQUEST;
        
        var currencyId: int = inMsgBody.loadUint(32);
        var amountToMint: int = inMsgBody.loadCurrency();
        var payload: cell = inMsgBody.loadMaybeRef();
        
        reserveToncoinsOnBalance(ONECOIN, RESERVE_MODE_EXACT_AMOUNT);

        var blackholeAddr: int = getBlockchainConfigParam(BlackholeAddressConfig).beginParse().preloadUint(256);
        var msgBurn = beginCell()
              .storeUint(BOUNCEABLE, 6)
              .storeUint(0x4ff, 11) // 10 = address pfx, 0 = no anycast, -1 = int8 workchain_id -> 0b10011111111
              .storeUint(blackholeAddr, 256)
              .storeCoins(myBalance - 2 * ONECOIN)
              .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
              .endCell();
        sendRawMessage(msgBurn, SEND_MODE_REGULAR);  

        setContractData(beginCell().storeUint(0, 256).endCell()); // is it safe?
        if(payload == null) {
            return;
        }
        var payloadSlice: slice = payload.beginParse();
        var amountToSend = payloadSlice.loadUint(256);
        var destination = payloadSlice.loadAddress();
        
        var currenciesToSend: cell = createEmptyDict();
        currenciesToSend.iDictSetBuilder(32, CURRENCY_ID, beginCell().storeCurrency(amountToSend));
        
        var msgWithdrawal = beginCell()
                        .storeUint(NON_BOUNCEABLE, 6)
                        .storeSlice(destination)
                        .storeCoins(myBalance - msgValue)
                        .storeDict(currenciesToSend)
                        .storeUint(0, 4 + 4 + 64 + 32 + 1 + 1)
                        .endCell();
        sendRawMessage(msgWithdrawal, SEND_MODE_REGULAR);
    }
    throw ERROR_UNKNOWN_OP;
}

