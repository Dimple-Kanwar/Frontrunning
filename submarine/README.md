# Generate Submarine Commitment

This library generates a `TXunlock` transaction and Address `B` for use with libsubmarine.


```
     TXcommit (1)

A +-------------------> B

+                       +
|                       | TXunlock (3)
|                       v
|
+---------------------> C

    TXreveal (2)
```

Party `A` (e.g. end-user Alice) chooses a (e.g. 256-bit) witness `w` value uniformly at random and computes
`commit = Keccak256(addr(A) | addr(C) | $value | d | w | gasPrice | gasLimit)`.

This `commit` is used as a `sessionId` in `LibSubmarine.sol`

Party `A` then generates a transaction `TXunlock` committing to data `d` and sending money to contract C:

Note: In our LibSubmarine implementation, `unlockFunctionSelector = decode_hex("ec9b5b3a")` is added to the final value of `d` to call the `unlock(bytes32 _sessionId)` function in `C` (where C is LibSubmarine.sol)

```javascript
to: C
value: $value
nonce: 0
data: 0xec9b5b3a + commit
gasPrice: $gp
gasLimit: gl
r: Keccak256(commit | 0)
s: Keccak256(commit | 1)
v: 27 // This makes TXunlock replayable across chains (i.e. compatible to be used on ropsten and mainnet and rinkeby etc)
```

## Python Implementation
The python implementation can be found in the file generate_submarine_commit.py. 
This can be run as a standalone program on the command line. See the `-h` parameter for help options.

### Generate Commit Address
You can import this function in python to generate commit addresses in your own code.
```python
def generateCommitAddress(fromAddress, toAddress, sendAmount, dappData, gasPrice, gasLimit):
```
#### Parameters
- **bytes fromAddress**: User controlled address from which submarine workflow starts, i.e. your address.
- **bytes toAddress**: Target end address that the submarine commitment will send money to. Usually the LibSubmarine Contract address.
- **int sendAmount**: Amount of money in Wei to send through the submarine commitment.
- **bytes dappData**: Any additional data to send in the function call peformed by the commitment. Usually this should be set to any empty bytes object e.g. b""
- **int gasPrice**: The gas price to use for the TXUnlock transaction from the commit address to the target.
- **int gasLimit**:The gas limit to use for the TXUnlock transaction from the commit address to the target.

#### Return Values
- **tuple (addressB, commit, witness, tx_hex)**
    - **str addressB**: The commit address hext string that is the Ethereum address that will lock up the submarine commitment. You send money to this address.
    - **str commit**: This is the calculated hex string `commit = Keccak256(addr(A) | addr(C) | $value | d | w | gasPrice | gasLimit)` as discussed above.
    - **str witness**: Random witness hex string. We use Linux URandom for this.
    - **str tx_hex**: Hex string representation of the unlock transaction. This can be broadcast directly to the network, and will perform TxUnlock.


### Example
```javascript
AddressB: 0x5338d846d05448d44138cd19982bf3cb0c87a756
commit: 79ae69adf744d9ccc88d487d7bb7be0f948c2902b016abb5b34bec2b554c4561
witness (w): f84bbef61a49dc60088b877a64e8fc7b6e62a787a745563d07849461db4bd9ea
Reveal Transaction (hex): f88f80850ba43b74008338a58a947aeb1fd3a42731c4ae80870044c992eb689fb2fe866fde2b4eb000a4ec9b5b3a79ae69adf744d9ccc88d487d7bb7be0f948c2902b016abb5b34bec2b554c45611ba0a70e779dca3a47d95401253d02a82ced651a1b934ec88e5c8736f7dd6ee4e374a015aa9000feec7034f94ad3bba2234310015a82e6d11acf1a0f900129a001e5b4
```
Sample Commit Transaction on Ropsten: [0x8345f014dc005a207f0eece7246d83b10b4cabe1f63cfe8dde3d5e82a21fd290](https://ropsten.etherscan.io/tx/0x8345f014dc005a207f0eece7246d83b10b4cabe1f63cfe8dde3d5e82a21fd290)

