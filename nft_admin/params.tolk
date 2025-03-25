@pure
fun workchain(): int
    asm "0 PUSHINT";

fun forceChain(addr: slice) {
  var (wc: int, _) = parseStandardAddress(addr);
  assert(wc == workchain()) throw 333;
}
