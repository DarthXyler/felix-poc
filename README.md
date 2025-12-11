# Felix Oracle Failure Shutdown PoC

This repository contains a single PoC test demonstrating the issue where
the Felix protocol enters **temporary shutdown due to oracle failure**, and then
continues using a **frozen price** indefinitely, allowing operations that should
not be permitted during shutdown.

This repo does not contain the Felix codebase.  
It does not interact with mainnet, or any external oracle.  
Reviewers must run the PoC inside the official Felix repository.

## 1. Clone the Official Felix Contracts Repo
``` 
git clone https://github.com/felixprotocol/felix-contracts.git
cd felix-contracts
``` 

## 2. Fetch This PoC Test File into the Felix Repo
``` 
curl -o test/ShutdownOracleFailureBypass.t.sol \
  https://raw.githubusercontent.com/DarthXyler/felix-poc/main/test/ShutdownOracleFailureBypass.t.sol
``` 
This will place the PoC test inside the Felix test suite.

## 3. Install Dependencies
``` 
forge install
``` 
Foundry will pull all required libraries used by Felix.

## 4. Run the PoC Test
``` 
forge test -vv --match-contract ShutdownOracleFailureBypassTest
``` 

If vulnerable, you will see all three tests passing, demonstrating:
- Oracle failure causes shutdown activation
- Price freezes at last known value
- Operations continue using frozen price, bypassing expected invariant checks

## 5. Expected Output (If Issue Exists)
_3 tests passed; 0 failed_

This confirms:
- Shutdown is triggered
- Frozen price persists
- Protocol allows unsafe operations while in inconsistent state

### Notes
- This repo only hosts the PoC test file and README.
- All contract logic, interfaces, and deployment scripts reside in the official Felix repo.
- The PoC must be executed inside the Felix repository for imports to resolve correctly.
