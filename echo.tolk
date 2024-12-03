// simplest swap
// receives TON without message, deduct 3 * ONE_TON, calc mint amount (1nanoton = 1unit of extra currency)
// request mint, put buyer address to payload.
// on op_minted parse buyer from payload and sends extra_currency

import "@stdlib/tvm-dicts"
import "constants.tolk"
import "utils.tolk"


fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {

    var inMsgFullSlice: slice = inMsgFull.beginParse();
    var flags: int = inMsgFullSlice.loadUint(4);

    if (flags & 1) {
        return;
    }

    var senderAddress: slice = inMsgFullSlice.loadAddress();

    var op: int = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);
    
    // echo#op_echo queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
    if( op == OP_ECHO) {
        var msgEcho = beginCell()
              .storeUint(NON_BOUNCEABLE, 6)
              .storeSlice(senderAddress)
              .storeCoins(0)
              .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
              .storeMessageOp(OP_ECHOED)
              .storeMessageQueryId(queryId)
              .storeSlice(inMsgBody)
              .endCell();
        return sendRawMessage(msgEcho, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);  
    }
    throw ERROR_UNKNOWN_OP;
}

