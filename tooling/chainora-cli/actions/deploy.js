// @ts-check

import { chooseDeployMenu } from "../menus/main.js";
import { promptAddress, promptAddressList, promptInteger } from "../prompts/common.js";
import { assertContractCode, deployArtifact, ensureClients } from "../services/chain.js";
import { printField, printHeader, printInfo, printSuccess } from "../services/format.js";
import {
  ensureAddress,
  ensureBigInt,
  parseAddressList,
  stringifyAddressList,
  ZERO_ADDRESS
} from "../services/shared.js";

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function runDeployWizard(session) {
  const choice = await chooseDeployMenu();
  if (choice === "back") return;

  if (choice === "bootstrapCore") return deployBootstrapCore(session);
  if (choice === "deployTimelock") return deployTimelock(session);
  if (choice === "deployRegistry") return deployRegistry(session);
  if (choice === "deployDeviceAdapter") return deployDeviceAdapter(session);
  if (choice === "deployPoolImplementation") return deployPoolImplementation(session);
  if (choice === "deployFactory") return deployFactory(session);
  if (choice === "deployChainoraTestUSD") return deployChainoraTestUSD(session);
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function deployBootstrapCore(session) {
  await ensureClients(session, { requireSigner: true });
  const timelockConfig = await promptTimelockConfig(session);

  const timelockResult = await deployTimelockWithConfig(session, timelockConfig, 0);
  const timelockAddress = getDeployAddress(timelockResult);
  const registryResult = await deployRegistryWithConfig(session, { timelockAddress }, 1);
  const registryAddress = getDeployAddress(registryResult);
  const deviceAdapterResult = await deployDeviceAdapterWithConfig(session, { timelockAddress }, 2);
  const deviceAdapterAddress = getDeployAddress(deviceAdapterResult);
  const poolImplementationResult = await deployPoolImplementationWithConfig(session, {}, 3);
  const poolImplementationAddress = getDeployAddress(poolImplementationResult);
  const factoryResult = await deployFactoryWithConfig(
    session,
    {
      timelockAddress,
      registryAddress,
      poolImplementationAddress
    },
    4
  );
  const factoryAddress = getDeployAddress(factoryResult);

  if (!session.dryRun) {
    await session.envStore.sync({
      CHAINORA_MULTISIG: timelockConfig.multisig,
      CHAINORA_TIMELOCK_DELAY: timelockConfig.delaySeconds.toString(),
      CHAINORA_PROPOSERS: stringifyAddressList(timelockConfig.proposers),
      CHAINORA_EXECUTORS: stringifyAddressList(timelockConfig.executors),
      CHAINORA_CANCELLERS: stringifyAddressList(timelockConfig.cancellers),
      CHAINORA_TIMELOCK: timelockAddress,
      CHAINORA_REGISTRY: registryAddress,
      CHAINORA_DEVICE_ADAPTER: deviceAdapterAddress,
      CHAINORA_POOL_IMPLEMENTATION: poolImplementationAddress,
      CHAINORA_FACTORY: factoryAddress
    });
  }

  printSuccess(session.dryRun ? "Bootstrap core dry-run hoàn tất." : "Bootstrap core thành công.");
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function deployTimelock(session) {
  await ensureClients(session, { requireSigner: true });
  const config = await promptTimelockConfig(session);
  const result = await deployTimelockWithConfig(session, config, 0);

  if (!session.dryRun) {
    await session.envStore.sync({
      CHAINORA_MULTISIG: config.multisig,
      CHAINORA_TIMELOCK_DELAY: config.delaySeconds.toString(),
      CHAINORA_PROPOSERS: stringifyAddressList(config.proposers),
      CHAINORA_EXECUTORS: stringifyAddressList(config.executors),
      CHAINORA_CANCELLERS: stringifyAddressList(config.cancellers),
      CHAINORA_TIMELOCK: getDeployAddress(result)
    });
  }
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function deployRegistry(session) {
  const timelockAddress = ensureAddress(
    await promptAddress({
      message: "Địa chỉ timelock cho Registry",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_TIMELOCK") ?? ZERO_ADDRESS
    }),
    "Timelock"
  );
  const result = await deployRegistryWithConfig(session, { timelockAddress }, 0);

  if (!session.dryRun) {
    await session.envStore.sync({
      CHAINORA_TIMELOCK: timelockAddress,
      CHAINORA_REGISTRY: getDeployAddress(result)
    });
  }
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function deployDeviceAdapter(session) {
  const timelockAddress = ensureAddress(
    await promptAddress({
      message: "Địa chỉ timelock cho Device Adapter",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_TIMELOCK") ?? ZERO_ADDRESS
    }),
    "Timelock"
  );
  const result = await deployDeviceAdapterWithConfig(session, { timelockAddress }, 0);

  if (!session.dryRun) {
    await session.envStore.sync({
      CHAINORA_TIMELOCK: timelockAddress,
      CHAINORA_DEVICE_ADAPTER: getDeployAddress(result)
    });
  }
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function deployPoolImplementation(session) {
  const result = await deployPoolImplementationWithConfig(session, {}, 0);
  if (!session.dryRun) {
    await session.envStore.sync({
      CHAINORA_POOL_IMPLEMENTATION: getDeployAddress(result)
    });
  }
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function deployFactory(session) {
  const timelockAddress = ensureAddress(
    await promptAddress({
      message: "Địa chỉ timelock cho Factory",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_TIMELOCK") ?? ZERO_ADDRESS
    }),
    "Timelock"
  );
  const registryAddress = ensureAddress(
    await promptAddress({
      message: "Địa chỉ Registry cho Factory",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_REGISTRY") ?? ZERO_ADDRESS
    }),
    "Registry"
  );
  const poolImplementationAddress = ensureAddress(
    await promptAddress({
      message: "Địa chỉ Pool Implementation cho Factory",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_POOL_IMPLEMENTATION") ?? ZERO_ADDRESS
    }),
    "Pool Implementation"
  );

  const result = await deployFactoryWithConfig(
    session,
    {
      timelockAddress,
      registryAddress,
      poolImplementationAddress
    },
    0
  );

  if (!session.dryRun) {
    await session.envStore.sync({
      CHAINORA_TIMELOCK: timelockAddress,
      CHAINORA_REGISTRY: registryAddress,
      CHAINORA_POOL_IMPLEMENTATION: poolImplementationAddress,
      CHAINORA_FACTORY: getDeployAddress(result)
    });
  }
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function deployChainoraTestUSD(session) {
  await ensureClients(session, { requireSigner: true });
  const owner = ensureAddress(
    await promptAddress({
      message: "Owner cho ChainoraTestUSD",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_TEST_STABLECOIN_OWNER") ?? session.account?.address
    }),
    "Owner"
  );
  const initialSupply = ensureBigInt(
    await promptInteger({
      message: "Initial supply cho ChainoraTestUSD",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_TEST_STABLECOIN_INITIAL_SUPPLY") ?? "1000000000000000000000000",
      min: 0n
    }),
    "Initial supply"
  );

  const result = await deployChainoraTestUSDWithConfig(session, { owner, initialSupply });

  printDeployResult("ChainoraTestUSD", result);

  if (!session.dryRun) {
    await session.envStore.sync({
      CHAINORA_TEST_STABLECOIN_OWNER: owner,
      CHAINORA_TEST_STABLECOIN_INITIAL_SUPPLY: initialSupply.toString(),
      CHAINORA_TEST_STABLECOIN: getDeployAddress(result)
    });
  }
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 * @param {{ owner: `0x${string}`, initialSupply: bigint }} config
 */
export async function deployChainoraTestUSDWithConfig(session, config) {
  printHeader("Deploy ChainoraTestUSD");
  printField("Owner", config.owner);
  printField("Initial supply", config.initialSupply);

  return deployArtifact(session, {
    artifactName: "ChainoraTestUSD",
    args: [config.owner, config.initialSupply],
    label: "ChainoraTestUSD"
  });
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
async function promptTimelockConfig(session) {
  await ensureClients(session, { requireSigner: true });
  const multisig = ensureAddress(
    await promptAddress({
      message: "Địa chỉ admin/multisig cho Timelock",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_MULTISIG") ?? session.account?.address ?? ZERO_ADDRESS
    }),
    "Multisig"
  );
  const delaySeconds = ensureBigInt(
    await promptInteger({
      message: "Delay (giây) cho Timelock",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_TIMELOCK_DELAY") ?? "0",
      min: 0n
    }),
    "Delay"
  );
  const proposers = parseAddressList(
    await promptAddressList({
      message: "Danh sách proposer (csv)",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_PROPOSERS") ?? multisig
    })
  );
  const executors = parseAddressList(
    await promptAddressList({
      message: "Danh sách executor (csv)",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_EXECUTORS") ?? multisig
    })
  );
  const cancellers = parseAddressList(
    await promptAddressList({
      message: "Danh sách canceller (csv)",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_CANCELLERS") ?? multisig
    })
  );

  return {
    multisig,
    delaySeconds,
    proposers: proposers.length > 0 ? proposers : [multisig],
    executors: executors.length > 0 ? executors : [multisig],
    cancellers: cancellers.length > 0 ? cancellers : [multisig]
  };
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 * @param {{
 *   multisig: `0x${string}`,
 *   delaySeconds: bigint,
 *   proposers: `0x${string}`[],
 *   executors: `0x${string}`[],
 *   cancellers: `0x${string}`[]
 * }} config
 * @param {number} nonceOffset
 */
export async function deployTimelockWithConfig(session, config, nonceOffset) {
  printHeader("Deploy Timelock");
  printField("Multisig", config.multisig);
  printField("Delay", config.delaySeconds);
  printField("Proposers", stringifyAddressList(config.proposers));
  printField("Executors", stringifyAddressList(config.executors));
  printField("Cancellers", stringifyAddressList(config.cancellers));

  const result = await deployArtifact(session, {
    artifactName: "ChainoraProtocolTimelock",
    args: [config.delaySeconds, config.multisig, config.proposers, config.executors, config.cancellers],
    label: "ChainoraProtocolTimelock",
    nonceOffset
  });
  printDeployResult("Timelock", result);
  return result;
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 * @param {{ timelockAddress: `0x${string}` }} config
 * @param {number} nonceOffset
 */
export async function deployRegistryWithConfig(session, config, nonceOffset) {
  await assertContractCode(session, "ChainoraProtocolTimelock", config.timelockAddress);
  printHeader("Deploy Registry");
  printField("Timelock", config.timelockAddress);

  const result = await deployArtifact(session, {
    artifactName: "ChainoraProtocolRegistry",
    args: [config.timelockAddress, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS],
    label: "ChainoraProtocolRegistry",
    nonceOffset
  });
  printDeployResult("Registry", result);
  return result;
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 * @param {{ timelockAddress: `0x${string}` }} config
 * @param {number} nonceOffset
 */
export async function deployDeviceAdapterWithConfig(session, config, nonceOffset) {
  await assertContractCode(session, "ChainoraProtocolTimelock", config.timelockAddress);
  printHeader("Deploy Device Adapter");
  printField("Timelock", config.timelockAddress);

  const result = await deployArtifact(session, {
    artifactName: "ChainoraDeviceAdapter",
    args: [config.timelockAddress],
    label: "ChainoraDeviceAdapter",
    nonceOffset
  });
  printDeployResult("Device Adapter", result);
  return result;
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 * @param {Record<string, never>} config
 * @param {number} nonceOffset
 */
export async function deployPoolImplementationWithConfig(session, config, nonceOffset) {
  void config;
  printHeader("Deploy Pool Implementation");
  const result = await deployArtifact(session, {
    artifactName: "ChainoraRoscaPool",
    args: [],
    label: "ChainoraRoscaPool",
    nonceOffset
  });
  printDeployResult("Pool Implementation", result);
  return result;
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 * @param {{
 *   timelockAddress: `0x${string}`,
 *   registryAddress: `0x${string}`,
 *   poolImplementationAddress: `0x${string}`
 * }} config
 * @param {number} nonceOffset
 */
export async function deployFactoryWithConfig(session, config, nonceOffset) {
  await assertContractCode(session, "ChainoraProtocolTimelock", config.timelockAddress);
  await assertContractCode(session, "ChainoraProtocolRegistry", config.registryAddress);
  await assertContractCode(session, "ChainoraRoscaPool", config.poolImplementationAddress);

  printHeader("Deploy Factory");
  printField("Timelock", config.timelockAddress);
  printField("Registry", config.registryAddress);
  printField("Pool Implementation", config.poolImplementationAddress);

  const result = await deployArtifact(session, {
    artifactName: "ChainoraRoscaFactory",
    args: [config.timelockAddress, config.registryAddress, config.poolImplementationAddress],
    label: "ChainoraRoscaFactory",
    nonceOffset
  });
  printDeployResult("Factory", result);
  return result;
}

/**
 * @param {string} label
 * @param {{
 *   dryRun: boolean,
 *   predictedAddress?: `0x${string}`,
 *   contractAddress?: `0x${string}`,
 *   hash?: `0x${string}`,
 *   estimatedGas?: bigint
 * }} result
 */
function printDeployResult(label, result) {
  if (result.dryRun) {
    printInfo(`[dry-run] ${label} sẽ deploy tại ${result.predictedAddress}`);
    printField("Estimated gas", result.estimatedGas);
    return;
  }

  printSuccess(`${label} deploy thành công.`);
  printField("Contract address", result.contractAddress);
  printField("Tx hash", result.hash);
}

/**
 * @param {{
 *   dryRun: boolean,
 *   predictedAddress?: `0x${string}`,
 *   contractAddress?: `0x${string}`
 * }} result
 */
function getDeployAddress(result) {
  const address = result.contractAddress ?? result.predictedAddress;
  if (!address) {
    throw new Error("Không lấy được địa chỉ contract sau deploy.");
  }
  return address;
}
