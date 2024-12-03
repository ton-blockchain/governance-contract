// simplest swap
// receives TON without message, deduct 3 * ONE_TON, calc mint amount (1nanoton = 1unit of extra currency)
// request mint, put buyer address to payload.
// on op_minted parse buyer from payload and sends extra_currency

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
        var payload : cell = beginCell().storeSlice(senderAddress).endCell();
        
        var minterAddr: int = getBlockchainConfigParam(MinterAddressConfig).beginParse().preloadUint(256);
        var queryId: int = getLogicalTime();
        
        var msgMint = beginCell()
              .storeUint(0x10, 6)
              .storeUint(0x4ff, 11) // 10 = address pfx, 0 = no anycast, -1 = int8 workchain_id -> 0b10011111111
              .storeUint(minterAddr, 256)
              .storeCoins(0)
              .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
              .storeMessageOp(OP_MINT)
              .storeMessageQueryId(queryId)
              .storeUint(CURRENCY_ID, 32)
              .storeCurrency(msgValue)
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
        
        var destination: slice = payload.beginParse().loadAddress();
        var msgWithdrawal = beginCell()
              .storeUint(NON_BOUNCEABLE, 6)
              .storeSlice(destination)
              .storeCoins(0)
              .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
              .endCell();
        return sendRawMessage(msgWithdrawal, SEND_MODE_CARRY_ALL_BALANCE);
    }
    throw ERROR_UNKNOWN_OP;
}

