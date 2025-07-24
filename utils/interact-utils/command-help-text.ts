
export const SHORT_HELP = `
interact - Interact with Quill contracts in a local setup.

USAGE:
  ./interact <COMMAND> [OPTIONS]

COMMANDS:
  snapshot                Take a snapshot of the local testnet.
  snapshot-diff           Compare two snapshots and highlight the differences.
  setprice                Sets the new price of the collateral.
  movetime                Moves time forward by a specified duration.
  shutdown                Shutdown a branch by its index.
  liquidate               Liquidate a list of troves by their IDs.
  redeem                  Redeem a specified amount of Quill tokens.

Run \`./interact <COMMAND> --help\` for detailed options and examples.

Note: this is probably buggy.
`;

export const SNAPSHOT_HELP = `
[interact] snapshot

      Take a snapshot of the local testnet. Saves the snapshot to 
      'protocolSnapshot.json' by default.

      OPTIONS:
        --markdown                  Also generates the snapshot in markdown format.
        --output <name>             Specify a custom base name for the output files (e.g., 
                                    "snapshot1" -> "snapshot1.json", "snapshot1.md").

      EXAMPLES:
        ./interact snapshot
        ./interact snapshot --markdown
        ./interact snapshot --output customSnapshot
        ./interact snapshot --markdown --output customSnapshot
`;

export const SNAPSHOT_DIFF_HELP = `
[interact] snapshot-diff <OLD> <NEW>

      Compare two snapshots and highlight the differences.

      PARAMETERS:
        <old>                        The older snapshot file (e.g., "snapshot1.json").
        <new>                        The newer snapshot file (e.g., "snapshot2.json").

      EXAMPLES:
        ./interact snapshot-diff snapshot1.json snapshot2.json
`;

export const SETPRICE_HELP = `
[interact] setprice <COLL_INDEX> [OPTIONS | NEW_WEI_VALUE]
      
      Sets the new price of the collateral. 
      
      NOTE: this feature \x1b[1m\x1b[31mwill not work in forked\x1b[39m\x1b[22m environments, since the price is fetched 
      from the Chainlink oracle. 

      PARAMETERS:
        <COLL_INDEX>                Index of the collateral to update.

      OPTIONS:
        --wei <NEW_WEI_VALUE>       Price in wei (default unit).
        --gwei <NEW_GWEI_VALUE>     Price in gwei (1 ether = 10^9 gwei).
        --ether <NEW_ETHER_VALUE>   Price in ether.

      EXAMPLES:
        ./interact setprice 1 150000000000000000000          # Default is wei
        ./interact setprice 1 --wei 150000000000000000000
        ./interact setprice 1 --gwei 1500000000000
        ./interact setprice 1 --ether 15                     # 1 ether = 10^18 wei = 1 USD
`;

export const MOVETIME_HELP = `
[interact] movetime [OPTIONS]

      Moves the time forward by the specified duration (default 1 day). Note that this will 
      only take effect after the next transaction is made

      OPTIONS:
        --sec <SECONDS>             Moves forward by the specified number of seconds.
        --day                       Moves forward by one day.
        --week                      Moves forward by one week.
        --month                     Moves forward by one month (30 days).
        --year                      Moves forward by one year (365 days).
      
      EXAMPLES:
        ./interact movetime --sec 3600
        ./interact movetime --day
`;

export const SHUTDOWN_HELP = `
[interact] shutdown <BRANCH_INDEX>

      Shutdown a branch by its index.

      PARAMETERS:
        <BRANCH_INDEX>              Index of the branch to shutdown.

      EXAMPLES:
        ./interact shutdown 1
`;

export const LIQUIDATE_HELP = `
[interact] liquidate <COLL_INDEX> <TROVE_ID>

      Liquidate a list of troves by their IDs.

      PARAMETERS:
        <COLL_INDEX>                 Index of the collateral to perform liquidations.
        <TROVE_IDS>                  Array of IDs of the troves to liquidate.

      EXAMPLES:
        ./interact liquidate 1 11187606515095629903487489821340171885033495262553632055898216111536384020053
`;

export const REDEEM_HELP = `
[interact] redeem <QUILL_AMOUNT>

      Redeem a specified amount of Quill tokens. Expects one option.

      PARAMETERS:
        <QUILL_AMOUNT>               Amount of Quill tokens to redeem.

      OPTIONS:
        --actor <ACTOR_NAME>         Actor to redeem the Quill tokens from. 
                                     Run './interact actors' to see the list of actors.
        --address <ACTOR_ADDRESS>    Address of the actor to redeem the Quill tokens from.
        --private-key <PRIVATE_KEY>  Private key of the account to redeem the Quill tokens from.
        --wei <WEI_AMOUNT>           Amount in wei (default unit).
        --gwei <GWEI_AMOUNT>         Amount in gwei.
        --ether <ETHER_AMOUNT>       Amount in ether.

      EXAMPLES:
        ./interact redeem --ether 1000 --actor adam
        ./interact redeem --wei 1000 --address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        ./interact redeem --gwei 1000 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
`;
