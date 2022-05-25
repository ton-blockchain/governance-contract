# FunC
Contracts are expected to be build using latest version of FunC from https://github.com/SpyCheese/ton/tree/func-inline-return

# Phase 1
| Name | Agree?  | Fixed?  | Comment   |
|------|----|----|---------------------------------------|
|CKP-01| ✔️  |  ✔️ |   |
|CKP-02| ✔️  |  ✔️ | In the longterm we propose to entirely discard voting based on signatures and replace it with make it with voting authorized by wallet-addresses (checked on elector-contract). So the whole system will be as follows: validator sends voting message to elector, elector checks the sender address and for authorized requests sends voting message to config. For transition period we propose to allow both ways of voting.  |
|CKP-03| ✔️  |  ✔️ |  We decided to perform check of one key or multikeys (if set) by challenging signing of predefined number. |
|CKP-04| ✔️  |  ✔️ |   |
|CKP-05| ✔️  |  ✔️ |   |
|CKP-06| ✔️  |  ✔️ |   |
|CKP-07| ✔️  |  ❌ | It is low priority thing and we will probably stick with current Config11 layout  |
|CKP-08| ✔️  |  ✔️ |   |
|CKP-09| ✔️  |  ✔️ |   |
|CKP-10| ✔️  |  ✔️ |   |
|ELE-01| ❌  |  ❌ |  Since actual parameter of min_validators is set by Config 16, exact value of lower bound set in code doesn’t matter: Config16.min_validators gave the same protection as elector_code (both can be changed by votings). Environments where this may matter are private blockchains for testing, where it can be convenient to be able to run a network with a single validator. |
|ELE-02| ✔️  |  ✔️ |   |
|ELE-03| ✔️  |  ✔️ |   |
|ELE-04| ✔️  |  ✔️ |   |
|ELE-05| ✔️  |  ✔️ |   |
|ELE-06| ✔️  |  ✔️ |   |
|ELE-07| ✔️  |  ❌ | Cannot be fixed  |
|ELE-08| ✔️  |  ✔️ |   |
|ELE-09| ❌  |  ❌ |  Current validation model heavily depends on ConfigParam 34 not being null at all times: without that nodes do not know who should validate the network. Besides, in the case config_param(34) is null, update_active_vset_id will fail is well at config_param(34).cell_hash() step. |
|ELE-10| ✔️  |  ✔️ |   |
|ELE-11| ✔️  |  ✔️ |   |
|ELE-12| ✔️ |  ✔️ |   |
|ELE-13| ✔️  |  ✔️ |   |
|ELE-14| ✔️  |  ✔️ |   |
|ELE-15| ✔️  |  ✔️ |   |
|ELE-16| ✔️  |  ✔️ |   |
|SMA-01| ✔️  |  ✔️ | Partially solved by multisignature scheme. There also could be time-lock and/or time-lock which can be opened immediately by majority of validators signature  |
|SMA-01| ✔️  |  ✔️ |   |
|SMA-02| ✔️  |  〰️ |  The proper fix will require addition of `global_id` to TVM context, then it can be used for cross-chain replay protection. We will neglect absence of cross-chain protection for now. Cross-round replay attack will be eliminated when the only option to vote will be voting-through-internal-message-to-elector |
|SMA-03| ✔️  |  ✔️ |   |
|SMA-04| ✔️  |  ✔️ |   |
|SMA-05| ✔️  |  ✔️ |   |
|SMA-06| ✔️  |  ✔️ |   |
|SMA-07| ✔️  |  ✔️ |   |
|SMA-08| ✔️  |  ✔️ |   |
|SMA-09| ✔️  |  ✔️ |   |

# Phase 2
| Name | Agree?  | Fixed?  | Comment   |
|------|----|----|---------------------------------------|
|CKP-01| ✔️  |  ✔️ |   |
|CKP-02| ✔️  |  ✔️ |   |
|CKP-03| ✔️  |  ✔️ |   |
|CKP-04| ✔️  |  ✔️ |   |
