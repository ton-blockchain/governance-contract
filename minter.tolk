// Extra currency minter contract

// In short, protocol is as following:
// Admin -> Minter -> Config -> Minter -> Echo (in other workchain to wait till next masterchain block) -> Minter -> Admin

// In details
// Minter contract receives requests from ExtraCurrency admins.
// Authorization is done by checking in ExtraCurrencyAuthorizationConfig
// Scheme is as following:
// mint#op_mint queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
// Minter checks that there is enough TON to pay from Config6 + 5 * fwdFee
// Note: no checks that there won't be (VarUint 32) overflow.
// In this case there will be error on Config contract that won't be handled
// After checks, Minter send mint request to Config
// Scheme is as following:
// mint#op_mint queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
// Config checks that request is sent from Minter contract, then unpack 7th config param, and add to
// currencyId requested amountToMint
// Config response to Minter
// Scheme is as following:
// registered#op_mint_registered queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
// At this moment extracurrency is not minted yet, we need to way till next masterchain block. Thus sending message to
// Echo contract
// Scheme is as following:
// echo#op_echo queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
// Echo responses with
// echoed#op_echoed queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
// Upon receiving echoed message Minter checks that it is sent from Echo
// At this moment extracurrency already added to Minter balance
// Minter finds Admin in ExtraCurrencyAuthorizationConfig and send there message with currencyId:amountToMint
// Scheme is as following
// minted#op_minted queryId:uint64 currencyId:int32 amountToMint:(VarUint 32) payload:(Maybe ^Cell) = InMsg;
// All messages are sent with SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE



import "@stdlib/tvm-dicts"
import "@stdlib/gas-payments"
import "constants.tolk"
import "utils.tolk"

fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    if (inMsgBody.getRemainingBitsCount() == 0) { // ignore empty messages
        return;
    }

    var inMsgFullSlice: slice = inMsgFull.beginParse();
    var flags: int = inMsgFullSlice.loadUint(4);

    if (flags & 1) { // ignore bounces
        return;
    }

    var senderAddress: slice = inMsgFullSlice.loadAddress();

    var op: int = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);

    if (op == OP_MINT) {
        var currencyOwners: cell = getBlockchainConfigParam(ExtraCurrencyAuthorizationConfig);

        var currencyId: int = inMsgBody.loadUint(32);
        var amountToMint: int = inMsgBody.loadCurrency();
        var payload: cell = inMsgBody.loadMaybeRef();

        var mintPriceList: cell = getBlockchainConfigParam(6);
        assert(!((mintPriceList == null))) throw ERROR_NO_PARAM_6;

        var ps: slice = mintPriceList.beginParse();
        var mintNewPrice: int = ps.loadCoins();
        var mintAddPrice: int = ps.loadCoins();

        var requiredFee: int = mintNewPrice;

        var fwdFeeFromInMsg: int = inMsgFullSlice.retrieveFwdFee();
        var fwdFee: int = calculateOriginalMessageFee(MY_WORKCHAIN, fwdFeeFromInMsg); // we use message fwd_fee for estimation of forward_payload costs
        
        var (owner, exist) = currencyOwners.uDictGet(32, currencyId);
        assert( exist ) throw ERROR_UNAUTHORIZED_MINT_REQUEST;
        assert( isSliceBitsEqual(senderAddress, owner)) throw ERROR_UNAUTHORIZED_MINT_REQUEST;
        assert(msgValue >= requiredFee + fwdFee * 5) throw ERROR_UNCOVERED_FEE;

        var configAddr: int = getBlockchainConfigParam(ConfigContractConfig).beginParse().preloadUint(256);

        var msgToConfig = beginCell()
          .storeUint(BOUNCEABLE, 6)
          .storeUint(0x4ff, 11) // 10 = address pfx, 0 = no anycast, -1 = int8 workchain_id -> 0b10011111111
          .storeUint(configAddr, 256)
          .storeCoins(0)
          .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
          .storeMessageOp(OP_MINT)
          .storeMessageQueryId(queryId)
          .storeUint(currencyId, 32)
          .storeCurrency(amountToMint)
          .storeMaybeRef(payload)
          .endCell();
        return sendRawMessage(msgToConfig, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
    }
    if(op == OP_MINT_REGISTERED) {
        var configAddr: int = getBlockchainConfigParam(ConfigContractConfig).beginParse().preloadUint(256);
        var (workchain, bareSenderAddress) = parseStandardAddress(senderAddress);
        assert( (workchain == -1) && (bareSenderAddress == configAddr)) throw ERROR_UNAUTHORIZED_MINT_REQUEST;

        var currencyId: int = inMsgBody.loadUint(32);
        var amountToMint: int = inMsgBody.loadCurrency();
        var payload: cell = inMsgBody.loadMaybeRef();
        
        var EchoAddress = getContractData().beginParse().loadAddress();
        
        var msgToEcho = beginCell()
          .storeUint(BOUNCEABLE, 6)
          .storeSlice(EchoAddress)
          .storeCoins(0)
          .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
          .storeMessageOp(OP_ECHO)
          .storeMessageQueryId(queryId)
          .storeUint(currencyId, 32)
          .storeCurrency(amountToMint)
          .storeMaybeRef(payload)
          .endCell();
        return sendRawMessage(msgToEcho, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
    }
    if(op == OP_ECHOED) {
        var EchoAddress = getContractData().beginParse().loadAddress();
        assert( isSliceBitsEqual(senderAddress, EchoAddress)) throw ERROR_UNAUTHORIZED_MINT_REQUEST;

        var currencyId: int = inMsgBody.loadUint(32);
        var amountToMint: int = inMsgBody.loadCurrency();
        var payload: cell = inMsgBody.loadMaybeRef();
        
        var currencyOwners: cell = getBlockchainConfigParam(ExtraCurrencyAuthorizationConfig);
        var (owner, exist) = currencyOwners.uDictGet(32, currencyId);
        assert( exist ) throw ERROR_UNAUTHORIZED_MINT_REQUEST;        

        var currenciesToSend: cell = createEmptyDict();
        currenciesToSend.uDictSetBuilder(32, currencyId, beginCell().storeCurrency(amountToMint));
        
        var msgToOwner = beginCell()
          .storeUint(NON_BOUNCEABLE, 6)
          .storeSlice(owner)
          .storeCoins(0)
          .storeDict(currenciesToSend)
          .storeUint(0, 4 + 4 + 64 + 32 + 1 + 1)
          .storeMessageOp(OP_MINTED)
          .storeMessageQueryId(queryId)
          .storeUint(currencyId, 32)
          .storeCurrency(amountToMint)
          .storeMaybeRef(payload)
          .endCell();
        return sendRawMessage(msgToOwner, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);

    }

    throw ERROR_UNKNOWN_OP;
}
