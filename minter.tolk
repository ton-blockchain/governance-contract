/* 
 * Extra Currency Minter Contract
 *
 * Protocol Overview:
 * Admin -> Minter -> Config -> Minter -> Echo (in other workchain to wait until the next masterchain block) -> Minter -> Admin
 *
 * Detailed Explanation:
 * - The Minter contract receives minting requests from ExtraCurrency administrators.
 * - Authorization is performed by checking the ExtraCurrencyAuthorizationConfig.
 *
 * Message Scheme:
 * mint query_id:uint64 currency_id:int32 amount_to_mint:(VarUInteger 32) payload:(Maybe ^Cell) = InternalMsgBody;
 *
 * - The Minter checks that there are sufficient TON funds to pay from Config6 plus 5 times the forwarding fee.
 *   Note: There are no checks for (VarUint 32) overflow.
 *   In such cases, an error will occur on the Config contract that won't be handled.
 *
 * - After validation, the Minter sends a mint request to the Config contract.
 *
 * Message Scheme:
 * mint query_id:uint64 currency_id:int32 amount_to_mint:(VarUInteger 32) payload:(Maybe ^Cell) = InternalMsgBody;
 *
 * - The Config contract verifies that the request originates from the Minter contract, unpacks the 7th config parameter, and adds the requested amountToMint to the currencyId.
 * - The Config contract responds to the Minter.
 *
 * Message Scheme:
 * registered query_id:uint64 currency_id:int32 amount_to_mint:(VarUInteger 32) payload:(Maybe ^Cell) = InternalMsgBody;
 *
 * - At this point, the extra currency is not minted yet. We need to wait until the next masterchain block by sending a message to the Echo contract.
 *
 * Message Scheme:
 * echo query_id:uint64 currency_id:int32 amount_to_mint:(VarUInteger 32) payload:(Maybe ^Cell) = InternalMsgBody;
 *
 * - The Echo contract responds with:
 *
 * Message Scheme:
 * echoed query_id:uint64 currency_id:int32 amount_to_mint:(VarUInteger 32) payload:(Maybe ^Cell) = InternalMsgBody;
 *
 * - Upon receiving the echoed message, the Minter verifies that it was sent from the Echo contract.
 * - At this moment, the extra currency has been added to the Minter's balance.
 * - The Minter retrieves the Admin from the ExtraCurrencyAuthorizationConfig and sends a message containing currencyId and amountToMint.
 *
 * Message Scheme:
 * minted query_id:uint64 currency_id:int32 amount_to_mint:(VarUInteger 32) payload:(Maybe ^Cell) = InternalMsgBody;
 *
 * - All messages are sent with SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE.
 */



import "@stdlib/tvm-dicts"
import "@stdlib/gas-payments"
import "constants.tolk"
import "utils.tolk"
import "nft_admin/nft_helpers.tolk"

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
        var authConfig: cell = getBlockchainConfigParam(ExtraCurrencyAuthorizationConfig);
        assert(authConfig != null, ERROR_NO_AUTH_CONFIG);

        var collectionVersion: int = inMsgBody.loadUint(8);

        var (cs, found) = authConfig.uDictGet(8, collectionVersion);

        assert(found, ERROR_UNAUTHORIZED_MINT_REQUEST);

        var collectionAddress = cs.loadAddress();

        var (workchain, _) = parseStandardAddress(senderAddress);

        var itemCode: cell = cs.loadRef();
        var currencyId: int = inMsgBody.loadUint(32);

        var amountToMint: int = inMsgBody.loadCurrency();
        var payload: cell = inMsgBody.loadMaybeRef();

        var mintPriceList: cell = getBlockchainConfigParam(6);
        assert(mintPriceList != null, ERROR_NO_PARAM_6);

        var ps: slice = mintPriceList.beginParse();
        var mintNewPrice: int = ps.loadCoins();
        var mintAddPrice: int = ps.loadCoins();

        var requiredFee: int = mintNewPrice;

        var fwdFeeFromInMsg: int = inMsgFullSlice.retrieveFwdFee();
        var fwdFee: int = calculateOriginalMessageFee(MY_WORKCHAIN, fwdFeeFromInMsg); // we use message fwd_fee for estimation of forward_payload costs
        
        var stateInit: cell = calculateNftItemStateInit(currencyId, itemCode, collectionAddress);
        assert(isSliceBitsEqual(senderAddress, calculateNftItemAddress(workchain, stateInit)), ERROR_UNAUTHORIZED_MINT_REQUEST);

        assert(msgValue >= requiredFee + fwdFee * 5) throw ERROR_UNCOVERED_FEE;

        var configAddr: int = getBlockchainConfigParam(ConfigAddressConfig).beginParse().preloadUint(256);

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
          .storeSlice(senderAddress) // So in the end of the chain minter would know where to send the EC.
          .storeMaybeRef(payload)
          .endCell();
        return sendRawMessage(msgToConfig, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
    }
    if(op == OP_MINT_REGISTERED) {
        var configAddr: int = getBlockchainConfigParam(ConfigAddressConfig).beginParse().preloadUint(256);
        var (workchain, bareSenderAddress) = parseStandardAddress(senderAddress);
        assert( (workchain == -1) && (bareSenderAddress == configAddr)) throw ERROR_UNAUTHORIZED_MINT_REQUEST;

        var currencyId: int = inMsgBody.loadUint(32);
        var amountToMint: int = inMsgBody.loadCurrency();
        var from: slice = inMsgBody.loadAddress();
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
          .storeSlice(from)
          .storeMaybeRef(payload)
          .endCell();
        return sendRawMessage(msgToEcho, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
    }
    if(op == OP_ECHOED) {
        var EchoAddress = getContractData().beginParse().loadAddress();
        assert( isSliceBitsEqual(senderAddress, EchoAddress)) throw ERROR_UNAUTHORIZED_MINT_REQUEST;

        var currencyId: int = inMsgBody.loadUint(32);
        var amountToMint: int = inMsgBody.loadCurrency();
        var owner: slice  = inMsgBody.loadAddress();
        var payload: cell = inMsgBody.loadMaybeRef();
        
        // var currencyOwners: cell = getBlockchainConfigParam(ExtraCurrencyAuthorizationConfig);
        // var (owner, exist) = currencyOwners.uDictGet(32, currencyId);
        // assert( exist ) throw ERROR_UNAUTHORIZED_MINT_REQUEST;        

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
