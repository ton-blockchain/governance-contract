const ONE_TON = 1000000000;
const MSG_INFO_REST_BITS = 1 + 4 + 4 + 64 + 32;

const MSG_WITH_STATE_INIT_AND_BODY_SIZE = `MSG_INFO_REST_BITS` + 1 + 1 + 1;
const MSG_HAVE_STATE_INIT = 4;
const MSG_STATE_INIT_IN_REF = 2;
const MSG_BODY_IN_REF = 1;
const MSG_ONLY_BODY_SIZE = MSG_INFO_REST_BITS + 1 + 1;

// Creates an output action which would reserve exactly x nanograms (if y = 0).
const RESERVE_REGULAR = 0;
// Creates an output action which would reserve at most x nanograms (if y = 2).
// Bit +2 in y means that the external action does not fail if the specified amount cannot be reserved; instead, all remaining balance is reserved.
const RESERVE_AT_MOST = 2;
// In this case all of the previous balance is reserved in addition to the value
const RESERVE_IN_ADDITION = 4;
const RESERVE_EXCEPT = 8;
// in the case of action fail - bounce transaction. No effect if RESERVE_AT_MOST (+2) is used. TVM UPGRADE 2023-07. https://docs.ton.org/learn/tvm-instructions/tvm-upgrade-2023-07#sending-messages
const RESERVE_BOUNCE_ON_ACTION_FAIL = 16;

@pure
@inline
fun addrNone(): slice
    asm "b{00} PUSHSLICE";
@inline
fun storePrefixOnlyBody(b: builder) {
    return b.storeUint(0, MSG_ONLY_BODY_SIZE);
}
@inline
fun storeOnlyBodyRef(b: builder, body: cell) {
    return b
    .storeUint(MSG_BODY_IN_REF, MSG_ONLY_BODY_SIZE)
    .storeRef(body);
}

@inline
fun storeBodyRefWithEc(mutate self: builder, body: cell, ec: cell?) {
    return self.storeDict(ec)
    .storeUint(MSG_BODY_IN_REF, MSG_ONLY_BODY_SIZE - 1)
    .storeRef(body);
}
@inline
fun storeStateinitRefAndBodyRef(b: builder, stateInit: cell, body: cell) {
    return b.storeUint(MSG_HAVE_STATE_INIT + MSG_STATE_INIT_IN_REF + MSG_BODY_IN_REF, MSG_WITH_STATE_INIT_AND_BODY_SIZE)
            .storeRef(stateInit)
            .storeRef(body);
}

@inline
fun storeMsgFlagsAndAddressNone(mutate self: builder, msgFlags: int) {
    return self.storeUint(msgFlags, 6);
}

@inline
fun storeEitherPayload(mutate self: builder, payload: slice): builder {

    if(1023 - self.getBuilderBitsCount() < payload.getRemainingBitsCount()) {
        self.storeUint(1, 1).storeRef(beginCell().storeSlice(payload).endCell());
    }
    else {
        self.storeUint(0, 1).storeSlice(payload);
    }

    return self;
}

fun reserveEc(tonValue: int, ec: cell?, mode: int): void
	asm "RAWRESERVEX";

@inline_ref
fun sendExcess(op: int, tonReserve: int, refund: slice, ecReserve: cell?, queryId: int,flags: int, err: int) {
    var excessMsg = beginCell()
                      .storeUint(NON_BOUNCEABLE, 6)
                      .storeSlice(refund)
                      .storeCoins(0)
                      .storePrefixOnlyBody()
                      .storeMessageOp(op)
                      .storeMessageQueryId(queryId);
    if(err) {
        excessMsg.storeUint(err, 10);
    }
    reserveEc(tonReserve, ecReserve, RESERVE_IN_ADDITION | RESERVE_AT_MOST | flags);
    sendRawMessage(excessMsg.endCell(), SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
}
