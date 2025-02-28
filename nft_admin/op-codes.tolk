const transfer = 0x5fcc3d14;

const ownership_assigned = 0x05138d91;

const excesses = 0xd53276db;

const get_static_data = 0x2fcb26a2;

const report_static_data = 0x8b771735;

const get_royalty_params = 0x693d3950;

const report_royalty_params = 0xa8cb00ad;

const OP_NEW_ITEM = 0x9ab3b012;

const OP_FAILED = 0x023a79ce;
const OP_TOP_UP  = 0xd372158c;
const OP_MINT_INITIAL = 0xa80bbfd7;
const OP_REFUND_MINT  = 0x2231db7d;
const OP_MINT_EC = 0x6760c40b;
const OP_OUT_EC  = 0xbefd2d8f;
const OP_BURN_EC = 0x8129586f;
const OP_BURN_NOTIFICATION = 0x0766ec37;
const OP_REBALANCE = 0xe624f852;
const OP_UPDATE_CONTENT = 0x7980902a;
const OP_RESET = 0x4f225089;
const OP_WITHDRAW_EXCESS = 0x7ad2441e;
const OP_WITHDRAW_EXCESS_COLLECTION = 0x8737c583;


// From jetton
const OP_EXCESS = 0xd53276db;
const OP_MINT_JETTON = 0x642b7d07;
const OP_INTERNAL_TRANSFER = 0x178d4519;

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
