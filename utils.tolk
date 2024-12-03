

@inline
fun retrieveFwdFee(inMsgFull: slice) {

    inMsgFull.loadAddress();
    inMsgFull.loadCoins();
    inMsgFull.skipDict();
    inMsgFull.loadCoins();
    return inMsgFull.loadCoins();
}


@pure
fun loadCurrency(mutate self: slice): int
    asm( -> 1 0) "LDVARUINT32";

@pure
fun storeCurrency(b: builder, x: int): builder
    asm "STVARUINT32";

@inline
fun skipBounceFlag(mutate self: slice): void {
    self.skipBits(32); // 0xFFFFFFFF
    return;
}
