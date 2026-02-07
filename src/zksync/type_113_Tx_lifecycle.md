# zkSync Account Abstraction

## Lifecycle of a Type 113 (0x71) Transaction

### Phase 1: Validation

1. **Submission**: The user sends the Type 113 transaction to a "zkSync API client" (which acts somewhat like a light node).
2. **Nonce Check**: The API client queries the `NonceHolder` system contract to ensure the transaction's nonce is unique for the account.
3. **Account Validation**: The API client calls the `validateTransaction` function on the user's custom account contract. This function **MUST** update the account's nonce within the `NonceHolder` system.
   A critical question arises: who is the _msg.sender_ when `validateTransaction` is invoked? Since it's a state-changing call (updating the nonce), the caller identity matters significantly for security and contract logic. For a TxType 113 transaction, the msg.sender during the validateTransaction call (and other system-initiated calls within this AA flow) is always the **Bootloader system contract**.
4. **Nonce Verification**: The API client verifies that the nonce was indeed updated by the `validateTransaction` call.
5. **Fee Payment Setup**: The API client calls `payForTransaction` if the account is paying its own fees. If a paymaster is involved, it calls `prepareForPaymaster` on the account and then `validateAndPayForPaymasterTransaction` on the paymaster contract.
6. **Bootloader Reimbursement Check**: The API client ensures that the Bootloader, which initially fronts resources for execution, will be properly compensated.

### Phase 2: Execution

7. **Forwarding to Sequencer**: The zkSync API client, having validated the transaction, passes it to the main node/sequencer.
8. **Transaction Execution**: The main node, via the **Bootloader**, calls the `executeTransaction` function on the user's account contract. This is where the actual state changes intended by the transaction (e.g., token transfers, contract calls) occur.
   The msg.sender during the `executeTransaction` call, as for `validateTransaction` and `postTransaction`, is always the **Bootloader system contract**.
9. **Paymaster Post-Action**: If a paymaster was used to sponsor the transaction, its `postTransaction` function is called, allowing for any necessary cleanup or post-execution logic.
