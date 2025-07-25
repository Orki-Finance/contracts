import { $, chalk, echo, fs, minimist } from "zx";

const HELP = `
deploy - deploy the Liquity contracts.

Usage:
  ./deploy [NETWORK_PRESET] [OPTIONS]

Arguments:
  NETWORK_PRESET  A network preset, which is a shorthand for setting certain options
                  such as the chain ID and RPC URL. Options take precedence over
                  network presets. Available presets:
                  - local: Deploy to a local network
                  - scroll-mainnet-fork: Deploy to a local fork of scroll's mainnet
                  - scroll-sepolia-fork: Deploy to a local fork of scroll's testnet
                  - scroll-sepolia: Deploy to the Scroll's testnet
                  - mainnet: Deploy to the Ethereum mainnet
                  - subvisual-testnet: Deploy to the Subvisual private testnet
                  - subvisual-scroll-sepolia: Deploy to Subvisual's private fork of Scroll testnet


Options:
                                           possible values: quill, liquity (defaults to quill)
  --chain-id <CHAIN_ID>                    Chain ID to deploy to.
  --debug                                  Show debug output.
  --deployer <DEPLOYER>                    Address or private key to deploy with.
                                           Requires a Ledger if an address is used.
  --resume                                 Resume deployment from a previous
  --ledger-path <LEDGER_PATH>              HD path to use with the Ledger (only used
                                           when DEPLOYER is an address).
  --dry-run                                Don't broadcast transaction, only
                                           simulate execution.
  --etherscan-api-key <ETHERSCAN_API_KEY>  Etherscan API key to verify the contracts
                                           (required when verifying with Etherscan).
  --gas-price <GAS_PRICE>                  Max fee per gas to use in transactions.
  --help, -h                               Show this help message.
  --mode <DEPLOYMENT_MODE>                 Deploy in one of the following modes:
                                           - complete (default),
                                           - bold-only,
                                           - use-existing-bold.
  --open-demo-troves                       Open demo troves after deployment (local
                                           only).
  --rpc-url <RPC_URL>                      RPC URL to use.
  --salt <SALT>                            Use keccak256(bytes(SALT)) as CREATE2
                                           salt instead of block timestamp.
  --slow                                   Only send a transaction after the previous
                                           one has been confirmed.
  --unlocked                               Used when the deployer account is unlocked
                                           in the client (i.e. no private key or
                                           Ledger device needed).
  --use-testnet-pricefeeds                 Use testnet PriceFeeds instead of real
                                           oracles when deploying to mainnet.
  --verify                                 Verify contracts after deployment.
  --verifier <VERIFIER>                    Verification provider to use.
                                           Possible values: etherscan, sourcify.
  --verifier-url <VERIFIER_URL>            The verifier URL, if using a custom
                                           provider.

Note: options can also be set via corresponding environment variables,
e.g. --chain-id can be set via CHAIN_ID instead. Parameters take precedence over variables.
`;

const ANVIL_FIRST_ACCOUNT = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const argv = minimist(process.argv.slice(2), {
  alias: {
    h: "help",
  },
  // We don't explicitly declare any options as boolean, so that we may tell the difference between an option missing
  // or it being explicitly set to false
  string: [
    "debug",
    "resume",
    "help",
    "open-demo-troves",
    "verify",
    "dry-run",
    "slow",
    "unlocked",
    "use-testnet-pricefeeds",
    "chain-id",
    "deployer",
    "etherscan-api-key",
    "ledger-path",
    "mode",
    "salt",
    "rpc-url",
    "verifier",
    "verifier-url",
    "gas-price",
    "priority-gas-price",
  ],
});

export async function main() {
  const { networkPreset, options } = await parseArgs();

  if (options.help) {
    echo`${HELP}`;
    process.exit(0);
  }

  switch (networkPreset) {
    case "local":
      options.chainId ??= 31337;
      options.deployer ??= ANVIL_FIRST_ACCOUNT;
      options.rpcUrl ??= "http://localhost:8545";
      options.script = "script/DeployOrkiLocal.s.sol";
      options.verify = false;
      break;

    case "subvisual-testnet":
      options.chainId ??= 7566690;
      options.rpcUrl ??= "https://testnet.subvisual.co";
      options.verifier ??= "sourcify";
      options.verifierUrl ??= "https://sourcify.testnet.subvisual.co";
      break;

    case "subvisual-scroll-sepolia":
      options.chainId ??= 7566690;
      options.rpcUrl ??= "https://testnet.subvisual.com";
      options.deployer ??= process.env.SCROLL_SEPOLIA_DEPLOYER;
      options.verifier ??= "sourcify";
      options.verifierUrl ??= "https://sourcify.testnet.subvisual.co";
      options.script = "script/DeployQuillScrollSepolia.s.sol";
      options.slow = true;
      break;

    case "scroll-sepolia-fork":
      options.chainId ??= 31337;
      options.deployer ??= ANVIL_FIRST_ACCOUNT;
      options.rpcUrl ??= "http://localhost:8545";
      options.script = "script/DeployQuillScrollSepolia.s.sol";
      break;

    case "scroll-sepolia":
      options.chainId ??= 534351;
      options.deployer ??= process.env.SCROLL_SEPOLIA_DEPLOYER;
      options.rpcUrl ??= "https://sepolia-rpc.scroll.io";
      options.script = "script/DeployQuillScrollSepolia.s.sol";
      options.verify = false;
      break;

    case "scroll-mainnet-fork":
      options.chainId ??= 31337;
      options.deployer ??= ANVIL_FIRST_ACCOUNT;
      options.rpcUrl ??= "http://localhost:8545";
      options.script = "scripts/DeployQuillScrollMainnet.s.sol";
      break;

    case "scroll-mainnet-shadow":
      options.chainId ??= 534352;
      options.deployer ??= process.env.SCROLL_MAINNET_DEPLOYER;
      options.rpcUrl ??= "https://rpc.scroll.io";
      options.script = "scripts/DeployQuillShadow.s.sol";
      options.verify = false;
      break;

    case "scroll-mainnet":
      options.chainId ??= 534352;
      options.deployer ??= process.env.SCROLL_MAINNET_DEPLOYER;
      options.rpcUrl ??= "https://rpc.scroll.io";
      options.script = "scripts/DeployQuillScrollMainnet.s.sol";
      break;

    case "swellchain-testnet":
      options.chainId ??= 1924;
      options.deployer ??= process.env.SWELLCHAIN_TESTNET_DEPLOYER;
      options.rpcUrl ??= "https://swell-testnet.alt.technology";
      options.script = "script/DeployOrkiSwellchainTestnet.s.sol";
      options.verify = false;
      break;

    case "swellchain-testnet-fork":
      options.chainId ??= 31337;
      options.deployer ??= ANVIL_FIRST_ACCOUNT;
      options.rpcUrl ??= "http://localhost:8545";
      options.script = "script/DeployOrkiSwellchainTestnet.s.sol";
      options.verify = false;
      break;

    case "swellchain-mainnet-fork":
      options.chainId ??= 31337;
      options.deployer ??= ANVIL_FIRST_ACCOUNT;
      options.rpcUrl ??= "http://localhost:8545";
      options.script = "script/DeployOrkiSwellchainMainnet.s.sol";
      options.verify = false;
      break;

    case "swellchain-mainnet-subvisual-fork":
      options.chainId ??= 7566690;
      options.deployer ??= ANVIL_FIRST_ACCOUNT;
      options.rpcUrl ??= "https://testnet2.subvisual.com";
      options.script = "script/DeployOrkiSwellchainMainnet.s.sol";
      break;

    case "swellchain-mainnet-shadow":
      options.chainId ??= 1923;
      options.deployer ??= process.env.SWELLCHAIN_MAINNET_DEPLOYER;
      options.rpcUrl ??= "https://swell-mainnet.alt.technology";
      options.script = "script/DeployOrkiShadow.s.sol";
      options.verify = false;
      break;

    case "swellchain-mainnet":
      options.chainId ??= 1923;
      options.deployer ??= process.env.SWELLCHAIN_MAINNET_DEPLOYER;
      options.rpcUrl ??= "https://swell-mainnet.alt.technology";
      options.script = "script/DeployOrkiSwellchainMainnet.s.sol";
      options.verifier = "blockscout";
      options.verifierUrl = "https://explorer.swellnetwork.io";
      options.verify = true;
      options.resume = true;
      break;

    default:
      throw new Error(`Unknown network preset: ${networkPreset}`);
  }

  options.mode ??= "complete";
  options.verifier ??= "etherscan";

  // handle missing options
  if (!options.chainId) {
    throw new Error("--chain-id <CHAIN_ID> is required");
  }
  if (!options.rpcUrl) {
    throw new Error("--rpc-url <RPC_URL> is required");
  }
  if (!options.deployer) {
    throw new Error("--deployer <DEPLOYER> is required");
  }
  if (options.verify && options.verifier === "etherscan" && !options.etherscanApiKey) {
    throw new Error(
      "Verifying with Etherscan requires --etherscan-api-key <ETHERSCAN_API_KEY>",
    );
  }

  const forgeArgs: string[] = [
    "script",
    options.script,
    "--chain-id",
    String(options.chainId),
    "--rpc-url",
    options.rpcUrl,
  ];

  if (!options.dryRun) {
    forgeArgs.push("--broadcast");
  }

  if (options.slow) {
    forgeArgs.push("--slow");
  }

  if (options.gasPrice) {
    forgeArgs.push("--with-gas-price");
    forgeArgs.push(options.gasPrice);
  }

  if (options.priorityGasPrice) {
    forgeArgs.push("--priority-gas-price");
    forgeArgs.push(options.priorityGasPrice);
  }

  // Etherscan API key
  if (options.etherscanApiKey) {
    forgeArgs.push("--etherscan-api-key");
    forgeArgs.push(options.etherscanApiKey);
  }

  // verify
  if (options.verify) {
    forgeArgs.push("--verify");

    // verifier
    if (options.verifier) {
      forgeArgs.push("--verifier");
      forgeArgs.push(options.verifier);
    }

    // verifier URL
    if (options.verifierUrl) {
      forgeArgs.push("--verifier-url");
      forgeArgs.push(options.verifierUrl);
    }
  }

  if (options.resume) {
    forgeArgs.push("--resume");
  }

  // Ledger signing
  if (options.deployer.startsWith("0x") && options.deployer.length === 42) {
    if (options.unlocked) {
      forgeArgs.push("--unlocked");
    } else {
      // Ledger signing
      forgeArgs.push("--ledger");
      if (options.ledgerPath) {
        forgeArgs.push("--hd-paths");
        forgeArgs.push(options.ledgerPath);
      }
    }
  }

  echo`
Deploying Liquity contracts with the following settings:

  CHAIN_ID:               ${options.chainId}
  DEPLOYER:               ${options.deployer}
  LEDGER_PATH:            ${options.ledgerPath}
  ETHERSCAN_API_KEY:      ${options.etherscanApiKey && "(secret)"}
  DEPLOYMENT_MODE:        ${options.mode}
  SALT:                   ${options.salt ? options.salt : chalk.yellow("block.timestamp will be used !!")}
  ETHERSCAN_API_KEY:      ${options.etherscanApiKey && "(secret)"}
  LEDGER_PATH:            ${options.ledgerPath}
  OPEN_DEMO_TROVES:       ${options.openDemoTroves ? "yes" : "no"}
  RPC_URL:                ${options.rpcUrl}
  USE_TESTNET_PRICEFEEDS: ${options.useTestnetPricefeeds ? "yes" : "no"}
  VERIFY:                 ${options.verify ? "yes" : "no"}
  VERIFIER:               ${options.verifier}
  VERIFIER_URL:           ${options.verifierUrl}
  RESUME:                 ${options.resume ? "yes" : "no"}
`;

  process.env.DEPLOYER = options.deployer;
  process.env.DEPLOYMENT_MODE = options.mode;
  process.env.SALT = options.salt;

  if (options.openDemoTroves) {
    process.env.OPEN_DEMO_TROVES = "true";
  }

  if (options.useTestnetPricefeeds) {
    process.env.USE_TESTNET_PRICEFEEDS = "true";
  }

  if ("CI" in process.env) {
    echo("Workaround: deleting variable 'CI' from environment"); // See https://github.com/liquity/bold/pull/113
    delete process.env.CI;
  }

  if (options.debug) {
    $.verbose = true;
  }

  // deploy
  await $(options.debug ? { stdio: "inherit" } : {})`forge ${forgeArgs}`;

  const deploymentManifestJson = fs.readFileSync("deployment-manifest.json", "utf-8");
  const deploymentManifest = JSON.parse(deploymentManifestJson) as {
    boldToken: string;
    branches: Record<string, string>[];
    collateralRegistry: string;
    hintHelpers: string;
    multiTroveGetter: string;
  };

  if (options.mode === "bold-only") {
    echo("BoldToken address:", deploymentManifest.boldToken);
    return;
  }

  const protocolContracts = {
    BoldToken: deploymentManifest.boldToken,
    CollateralRegistry: deploymentManifest.collateralRegistry,
    HintHelpers: deploymentManifest.hintHelpers,
    MultiTroveGetter: deploymentManifest.multiTroveGetter,
    WETHTester: deploymentManifest.branches[0].collToken,
  };

  const collateralContracts = deploymentManifest.branches.map((branch) => ({
    activePool: branch.activePool,
    addressesRegistry: branch.addressesRegistry,
    borrowerOperations: branch.borrowerOperations,
    collSurplusPool: branch.collSurplusPool,
    collToken: branch.collToken,
    defaultPool: branch.defaultPool,
    gasCompZapper: branch.gasCompZapper,
    gasPool: branch.gasPool,
    interestRouter: branch.interestRouter,
    leverageZapper: branch.leverageZapper,
    metadataNFT: branch.metadataNFT,
    priceFeed: branch.priceFeed,
    sortedTroves: branch.sortedTroves,
    stabilityPool: branch.stabilityPool,
    troveManager: branch.troveManager,
    troveNFT: branch.troveNFT,
    wethZapper: branch.wethZapper,
  }));

  // XXX hotfix: we were leaking Github secrets in "deployer"
  // TODO: check if "deployer" is a private key, and calculate its address and use it instead?
  const { deployer, ...safeOptions } = options;

  // write env file
  await fs.writeJson("deployment-context-latest.json", {
    options: safeOptions,
    collateralContracts,
    protocolContracts,
  });

  // format deployed contracts
  const longestContractName = Math.max(
    ...Object.keys(protocolContracts).map((name) => name.length),
    ...collateralContracts.flatMap((contracts) => Object.keys(contracts).map((name) => name.length)),
  );

  const formatContracts = (contracts: Array<string[]>) => (
    contracts.map(([name, address]) => {
      name = name[0].toUpperCase() + name.slice(1);
      return `  ${name.padEnd(longestContractName)}  ${address}`;
    }).join("\n")
  );

  echo("Protocol contracts:");
  echo("");
  echo(formatContracts(Object.entries(protocolContracts)));
  echo("");
  echo(
    collateralContracts.map((collateral, index) => (
      `Collateral ${index + 1} contracts:\n\n${formatContracts(Object.entries(collateral))}`
    )).join("\n\n"),
  );
  echo("");
  echo("Deployment complete.");
  echo("");
}

function safeParseInt(value: string) {
  const parsed = parseInt(value, 10);
  return isNaN(parsed) ? undefined : parsed;
}

function parseBoolValue(value: string): boolean {
  return value !== "false"
    && value !== "no"
    && value !== "0";
}

// Passing an empty string for a bool parameter through the environment should count as not passing the parameter at all
function parseBoolEnv(value: string | undefined): boolean | undefined {
  if (value === undefined || value === "") return undefined;
  return parseBoolValue(value);
}

// Passing a bool option without an explicit value (e.g. `--debug`) should count as true
// In this case, value will be an empty string
function parseBoolOption(value: string | undefined): boolean | undefined {
  if (value == undefined) return undefined;
  return value === "" || parseBoolValue(value);
}

function parseBool(optionValue: string | undefined, envValue?: string | undefined): boolean {
  return parseBoolOption(optionValue)
    ?? parseBoolEnv(envValue)
    ?? false;
}

async function parseArgs() {
  const options = {
    chainId: safeParseInt(argv["chain-id"]),
    debug: argv["debug"],
    resume: argv["resume"],
    deployer: argv["deployer"],
    etherscanApiKey: argv["etherscan-api-key"],
    help: argv["help"],
    ledgerPath: argv["ledger-path"],
    mode: argv["mode"],
    salt: argv["salt"],
    openDemoTroves: argv["open-demo-troves"],
    rpcUrl: argv["rpc-url"],
    dryRun: argv["dry-run"],
    slow: argv["slow"],
    unlocked: argv["unlocked"],
    verify: argv["verify"],
    verifier: argv["verifier"],
    verifierUrl: argv["verifier-url"],
    gasPrice: argv["gas-price"],
    priorityGasPrice: argv["priority-gas-price"],
    script: argv["script"],
    useTestnetPricefeeds: argv["use-testnet-pricefeeds"]
  };

  const [networkPreset] = argv._;

  options.chainId ??= safeParseInt(process.env.CHAIN_ID ?? "");
  options.debug = parseBool(options.debug, process.env.DEBUG);
  options.deployer ??= process.env.DEPLOYER;
  options.dryRun = parseBool(options.dryRun, process.env.DRY_RUN);
  options.etherscanApiKey ??= process.env.ETHERSCAN_API_KEY;
  options.help = parseBool(options.help);
  options.ledgerPath ??= process.env.LEDGER_PATH;
  options.mode ??= process.env.DEPLOYMENT_MODE;
  options.openDemoTroves = parseBool(options.openDemoTroves, process.env.OPEN_DEMO_TROVES);
  options.rpcUrl ??= process.env.RPC_URL;
  options.useTestnetPricefeeds ??= Boolean(
    process.env.USE_TESTNET_PRICEFEEDS && process.env.USE_TESTNET_PRICEFEEDS !== "false",
  );
  options.verify ??= Boolean(
    process.env.VERIFY && process.env.VERIFY !== "false",
  );
  options.salt ??= process.env.SALT;
  options.slow = parseBool(options.slow, process.env.SLOW);
  options.unlocked = parseBool(options.unlocked, process.env.UNLOCKED);
  options.useTestnetPricefeeds = parseBool(options.useTestnetPricefeeds, process.env.USE_TESTNET_PRICEFEEDS);
  options.verify = parseBool(options.verify, process.env.VERIFY);
  options.verifier ??= process.env.VERIFIER;
  options.verifierUrl ??= process.env.VERIFIER_URL;

  return { options, networkPreset };
}
