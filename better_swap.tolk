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
        
        var amountToRequest = ONECOIN * ONECOIN;
        
        if (currencyBalance >= msgValue) {
            var currenciesToSend: cell = createEmptyDict();
            currenciesToSend.iDictSetBuilder(32, CURRENCY_ID, beginCell().storeCurrency(msgValue));
            var msgWithdrawal = beginCell()
                        .storeUint(NON_BOUNCEABLE, 6)
                        .storeSlice(senderAddress)
                        .storeCoins(0)
                        .storeDict(currenciesToSend)
                        .storeUint(0, 4 + 4 + 64 + 32 + 1 + 1)
                        .endCell();
           return sendRawMessage(msgWithdrawal, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
        var alreadyRequested = getContractData().beginParse().loadInt(1);
        // do not allow more than one request in-fly
        assert ( alreadyRequested == 0) throw 222;
        
        setContractData(beginCell().storeInt(true, 1).endCell());
        
        var msgMint = beginCell()
              .storeUint(0x10, 6)
              .storeUint(0x4ff, 11) // 10 = address pfx, 0 = no anycast, -1 = int8 workchain_id -> 0b10011111111
              .storeUint(minterAddr, 256)
              .storeCoins(2 * ONECOIN)
              .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
              .storeMessageOp(OP_MINT)
              .storeMessageQueryId(queryId)
              .storeUint(CURRENCY_ID, 32)
              .storeCurrency(amountToRequest)
              .storeMaybeRef(null)
              .endCell();
        sendRawMessage(msgMint, 0);
        
        // lets return the rest to user
        reserveToncoinsOnBalance(0, RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE);
        var msgWithdrawal = beginCell()
                        .storeUint(NON_BOUNCEABLE, 6)
                        .storeSlice(senderAddress)
                        .storeCoins(0)
                        .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
                        .endCell();
        return sendRawMessage(msgWithdrawal, SEND_MODE_CARRY_ALL_BALANCE);        
    }
    
    var op: int = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);
    
    //minted#op_minted queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
    if( op == OP_MINTED) {
        return setContractData(beginCell().storeInt(false, 1).endCell());
    }
    throw ERROR_UNKNOWN_OP;
}

