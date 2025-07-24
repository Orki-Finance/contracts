import { $, echo, fs, minimist } from "zx";
import { generateDiffMarkdownFromFiles, generateMarkdownFromFile } from "./interact-utils/snapshot-markdown";
import { generateAnsiFromFile, generateAnsiDiffFromFiles } from "./interact-utils/snapshot-ansi";
import {
  SHORT_HELP,
  SNAPSHOT_HELP,
  SNAPSHOT_DIFF_HELP,
  SETPRICE_HELP,
  MOVETIME_HELP,
  SHUTDOWN_HELP,
  LIQUIDATE_HELP,
  REDEEM_HELP
} from "./interact-utils/command-help-text";
import { ACTORS_LIST } from "./interact-utils/actors";
import { 
  liquidateTroves,
  shutdownBranch,
  getStateSnapshotLocal,
  redeemCollateralLocal,
  setPrice
} from "./interact-utils/forge-commands";

const argv = minimist(process.argv.slice(2), {
  alias: {
    h: "help",
  },
  boolean: ["help", "debug", "markdown", "day", "week", "month", "year"],
  string: ["sec", "actor", "address", "private-key", "output", "wei", "gwei", "ether"],
});

function safeParseInt(value) {
  try {
    return BigInt(value);
  } catch (e) {
    echo("Error: Could not parse value. Ensure the value is a valid integer.");
    process.exit(1);
  }
}

async function parseArgs() {
  const [command, ...args] = argv._;

  if (!command) {
    echo(SHORT_HELP);
    process.exit(0);
  }

  switch (command) {
    case "snapshot":
      if (argv.help) {
        echo(SNAPSHOT_HELP);
        process.exit(0);
      }
      await handleSnapshot();
      break;
    case "snapshot-diff":
      if (argv.help) {
        echo(SNAPSHOT_DIFF_HELP);
        process.exit(0);
      }
      await handleSnapshotDiff();
      break;
    case "setprice":
      if (argv.help) {
        echo(SETPRICE_HELP);
        process.exit(0);
      }
      await handleSetPrice(args);
      break;
    case "movetime":
      if (argv.help) {
        echo(MOVETIME_HELP);
        process.exit(0);
      }
      await handleMoveTime();
      break;
    case "shutdown":
      if (argv.help) {
        echo(SHUTDOWN_HELP);
        process.exit(0);
      }
      await handleShutdownBranch(args);
      break;
    case "liquidate":
      if (argv.help) {
        echo(LIQUIDATE_HELP);
        process.exit(0);
      }
      await handleLiquidate(args);
      break;
    case "redeem":
      if (argv.help) {
        echo(REDEEM_HELP);
        process.exit(0);
      }
      await handleRedeem(args);
      break;
    default:
      echo(`Unknown command: ${command}`);
      echo(SHORT_HELP);
      process.exit(1);
  }
}

async function handleLiquidate(args) {
  const index = safeParseInt(args[0]);
  // minimalist automatically parses values, so we need to get them as strings
  const values = process.argv.slice(4);

  if (index === undefined || values.length < 1) {
    echo("Error: You must specify the collateral index and at least one liquidation value.");
    echo(LIQUIDATE_HELP);
    process.exit(1);
  }

  //error parsing values, let's keep them as strings
  echo(`Running liquidation for index ${index} with values: ${values.join(", ")}`);

  const formattedValues = `[${values.join(", ")}]`;

  await liquidateTroves(index, formattedValues);

  echo("Liquidation executed successfully.");
}

async function handleShutdownBranch(args) {
  const branchIndex = safeParseInt(args[0]);

  if (branchIndex === undefined) {
    echo("Error: BRANCH_INDEX must be provided as an integer.");
    echo(SHUTDOWN_HELP);
    process.exit(1);
  }

  echo(`Shutting down branch with index ${branchIndex}...`);

  await shutdownBranch(branchIndex);

  echo("Branch shutdown successfully.");
}

async function handleSnapshot() {
  echo("Taking a snapshot of the local testnet...");
  const defaultOutput = "protocolSnapshot.json";

  await getStateSnapshotLocal();

  const baseName = argv.output || "protocolSnapshot";
  const jsonOutput = `${baseName}.json`;
  const markdownOutput = `${baseName}.md`;

  if (argv.output) {
    await fs.rename(defaultOutput, jsonOutput);
    echo(`Snapshot saved to ${jsonOutput}`);
  } else {
    echo(`Snapshot saved to ${defaultOutput}`);
  }

  if (argv.markdown) {
    generateMarkdownFromFile(jsonOutput, markdownOutput);
    echo(`Markdown snapshot generated at ${markdownOutput}`);
  }

  if (!argv.markdown) {
    generateAnsiFromFile(jsonOutput);
  }
}

async function handleSnapshotDiff() {
  if (argv._.length < 3) {
    echo("Error: Missing arguments. Usage: snapshot-diff <old> <new>");
    return;
  }

  const oldFile = argv._[1];
  const newFile = argv._[2];

  if (!await fs.exists(oldFile)) {
    echo(`Error: File not found: ${oldFile}`);
    return;
  }
  if (!await fs.exists(newFile)) {
    echo(`Error: File not found: ${newFile}`);
    return;
  }

  // const diffFileName = `${newFile.replace(".json", "")}-${oldFile.replace(".json", "")}-diff-report.md`;
  // generateDiffMarkdownFromFiles(oldFile, newFile, diffFileName);

  // echo(`Diff report generated at ${diffFileName}`);
  generateAnsiDiffFromFiles(oldFile, newFile);
}

async function handleSetPrice(args) {
  const collIndex = safeParseInt(args[0]);

  if (collIndex === undefined) {
    echo("Error: COLL_INDEX must be provided as an integer.");
    echo(SETPRICE_HELP);
    process.exit(1);
  }

  let newWeiValue;

  if (argv.wei !== undefined) {
    newWeiValue = safeParseInt(argv.wei);
  } else if (argv.gwei !== undefined) {
    const gweiValue = safeParseInt(argv.gwei);
    if (gweiValue !== undefined) {
      newWeiValue = gweiValue * BigInt(1e9);
    }
  } else if (argv.ether !== undefined) {
    const etherValue = safeParseInt(argv.ether);
    if (etherValue !== undefined) {
      newWeiValue = etherValue * BigInt(1e18);
    }
  } else {
    newWeiValue = safeParseInt(args[1]);
  }

  if (newWeiValue === undefined || typeof newWeiValue !== 'bigint') {
    echo("Error: Invalid price value. Ensure the value is a valid integer.");
    process.exit(1);
  }

  echo(`Setting price for collateral index ${collIndex} to ${newWeiValue} wei...`);

  await setPrice(collIndex, newWeiValue);

  echo("Price set successfully.");
}

async function handleMoveTime() {
  // Default to 1 day if no specific option is provided
  let seconds: bigint | undefined = BigInt(24 * 60 * 60);

  if (argv.sec !== undefined) {
    seconds = safeParseInt(argv.sec);
    if (seconds === undefined) {
      echo("Error: Invalid value for --sec. Please provide a valid integer.");
      process.exit(1);
    }
  } else if (argv.day) {
    seconds = BigInt(24 * 60 * 60); // One day
  } else if (argv.week) {
    seconds = BigInt(7 * 24 * 60 * 60); // One week
  } else if (argv.month) {
    seconds = BigInt(30 * 24 * 60 * 60); // One month
  } else if (argv.year) {
    seconds = BigInt(365 * 24 * 60 * 60); // One year
  }

  echo(`Moving time forward by ${seconds} seconds...`);
  
  try {
    const requestId = Date.now();
    await $`curl -H "Content-Type: application/json" -X POST --data '{"jsonrpc":"2.0","method":"evm_increaseTime","params":[${seconds}],"id":${requestId} }' 127.0.0.1:8545`;
    echo("Time moved successfully.");
  } catch (error) {
    echo("Error: Failed to move time. Ensure the Anvil is running and accessible.");
    process.exit(1);
  }
}

async function handleRedeem(args) {
  const actor = argv.actor;
  const address = argv.address;
  let privateKey = argv["private-key"];

  if (!(actor || address || privateKey)) {
    echo("Error: One of --actor, --address, or --private-key must be provided.");
    echo(REDEEM_HELP);
    process.exit(1);
  }

  if (actor) {
    const actorData = ACTORS_LIST.find((a) => a.name === actor);
    if (actorData) {
      privateKey = actorData.privateKey;
    }
  }

  if (address) {
    const actorData = ACTORS_LIST.find((a) => a.address === address);
    if (actorData) {
      privateKey = actorData.privateKey;
    }
  }

  if (!privateKey) {
    echo("Error: Private key not found. Ensure the actor or address is correct.");
    process.exit(1);
  }

  let amount;

  if (argv.wei !== undefined) {
    amount = argv.wei;
  } else if (argv.gwei !== undefined) {
    amount = safeParseInt(argv.gwei) * BigInt(1e9);
  } else if (argv.ether !== undefined) {
    amount = safeParseInt(argv.ether) * BigInt(1e18);
  }
  
  if (amount === undefined || typeof amount !== 'bigint') {
    echo("Error: Invalid Quill amount. Ensure the value is a valid integer.");
    process.exit(1);
  }

  echo(`Redeeming amount ${amount}...`);

  await redeemCollateralLocal(privateKey, amount);

  echo("Trove redeemed successfully.");
}

export async function main() {
  await parseArgs();
  echo("");
}
