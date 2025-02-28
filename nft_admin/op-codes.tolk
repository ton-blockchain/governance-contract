const transfer = 0x5fcc3d14;

const ownership_assigned = 0x05138d91;

const excesses = 0xd53276db;

const get_static_data = 0x2fcb26a2;

const report_static_data = 0x8b771735;

const get_royalty_params = 0x693d3950;

const report_royalty_params = 0xa8cb00ad;

const OP_FAILED = 42;
const OP_TOP_UP  = 43;
const OP_MINT_INITIAL = 44;
const OP_REFUND_MINT = 45;
const OP_TRANSFER_EC = 46;
const OP_OUT_EC  = 146;
const OP_BURN_EC = 47;
const OP_BURN_NOTIFICATION = 48;
const OP_REBALANCE = 49;
const OP_UPDATE_CONTENT = 50;
const OP_RESET = 51;
const OP_WITHDRAW_EXTRA = 52;
const OP_WITHDRAW_EXTRA_COLLECTION = 62;

const OP_EXCESS = 0xd53276db;

// From jetton
const OP_MINT_JETTON = 0x642b7d07;
const INTERNAL_TRANSFER = 0x178d4519;

// NFTEditable
@pure
fun `op::edit_content`(): int
    asm "0x1a0b9d51 PUSHINT";
@pure
fun `op::transfer_editorship`(): int
    asm "0x1c04412a PUSHINT";
@pure
fun `op::editorship_assigned`(): int
    asm "0x511a4463 PUSHINT";
