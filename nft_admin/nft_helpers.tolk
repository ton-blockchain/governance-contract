import "errors.tolk";

@inline
fun calculateNftItemStateInit(itemIndex: int, nftItemCode: cell, collectionAddress: slice): cell {
  var data: cell = beginCell().storeUint(0, 4).storeUint(itemIndex, 32).storeSlice(collectionAddress).endCell();
  return beginCell().storeUint(0, 2).storeDict(nftItemCode).storeDict(data).storeUint(0, 1).endCell();
}

@inline
fun calculateNftItemAddress(wc: int, stateInit: cell): slice {
  return beginCell().storeUint(4, 3)
                     .storeInt(wc, 8)
                     .storeUint(cellHash(stateInit), 256)
                     .endCell()
                     .beginParse();
}

@inline
fun checkEitherForwardPayload(self: slice) {
    if (self.preloadUint(1)) {
        // forward_payload in ref
        var (remainBits: int, remainRefs: int) = getRemainingBitsAndRefsCount(self);
        assert((remainRefs == 1) & (remainBits == 1), INVALID_MESSAGE); // we check that there is no excess in the slice
    }
    // else forward_payload in slice - arbitrary bits and refs
    return self;
}
