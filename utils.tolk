import "@stdlib/tvm-dicts"

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

@pure
fun isStandardAddress(s: slice): (int, int, bool)
    asm "REWRITESTDADDRQ NULLSWAPIFNOT2";

@pure
@inline
fun getRawEc() : cell {
	var [ton , ec] = getMyOriginalBalanceWithExtraCurrencies();
	return ec;
}

@inline
fun getEcAmount(self: cell, id: int) {
	var res: int   = 0;

	var (data, found) = self.uDictGet(32, id);

	if(found) {
		res = data.loadCurrency();
	}

	return res;
}

@inline
fun packEc(mutate self: cell, id: int, amount: int) {
    self.uDictSetBuilder(32, id, beginCell().storeCurrency(amount));
}
