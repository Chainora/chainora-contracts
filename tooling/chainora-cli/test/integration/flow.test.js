// @ts-check

import assert from "node:assert/strict";
import test from "node:test";
import { zeroHash } from "viem";

import { deployChainoraTestUSDWithConfig, deployDeviceAdapterWithConfig, deployFactoryWithConfig, deployPoolImplementationWithConfig, deployRegistryWithConfig, deployTimelockWithConfig } from "../../actions/deploy.js";
import { loadArtifact } from "../../services/artifacts.js";
import { readContract, writeContract } from "../../services/chain.js";
import { createSession } from "../../services/runtime.js";
import { encodeAdminCall, getTimelockAbi, selectExecuteCandidate, selectScheduleCandidate, TIMELOCK_UTILS_ABI } from "../../services/timelock.js";
import { ANVIL_ADDRESS, ANVIL_PRIVATE_KEY, createTempEnv, spawnAnvil } from "../helpers.js";

test("deploy flow wires contracts and timelock admin ops work end-to-end", async () => {
  const anvil = await spawnAnvil({ port: 8547 });
  const { envPath } = await createTempEnv(`RPC_URL=${anvil.rpcUrl}\nPRIVATE_KEY=${ANVIL_PRIVATE_KEY}\n`);
  const session = await createSession({ envPath });

  const timelock = await deployTimelockWithConfig(
    session,
    {
      multisig: ANVIL_ADDRESS,
      delaySeconds: 0n,
      proposers: [ANVIL_ADDRESS],
      executors: [ANVIL_ADDRESS],
      cancellers: [ANVIL_ADDRESS]
    },
    0
  );
  const timelockAddress = timelock.contractAddress;
  assert.ok(timelockAddress);

  const registry = await deployRegistryWithConfig(session, { timelockAddress }, 0);
  const deviceAdapter = await deployDeviceAdapterWithConfig(session, { timelockAddress }, 0);
  const poolImplementation = await deployPoolImplementationWithConfig(session, {}, 0);
  const factory = await deployFactoryWithConfig(
    session,
    {
      timelockAddress,
      registryAddress: registry.contractAddress,
      poolImplementationAddress: poolImplementation.contractAddress
    },
    0
  );

  const registryAbi = (await loadArtifact(session.projectRoot, "ChainoraProtocolRegistry")).abi;
  const factoryAbi = (await loadArtifact(session.projectRoot, "ChainoraRoscaFactory")).abi;
  const timelockAbi = await getTimelockAbi(session);

  assert.equal(String(await readContract(session, registry.contractAddress, registryAbi, "timelock")).toLowerCase(), timelockAddress.toLowerCase());
  assert.equal(String(await readContract(session, factory.contractAddress, factoryAbi, "registry")).toLowerCase(), registry.contractAddress.toLowerCase());
  assert.equal(
    String(await readContract(session, factory.contractAddress, factoryAbi, "poolImplementation")).toLowerCase(),
    poolImplementation.contractAddress.toLowerCase()
  );
  assert.equal(await readContract(session, registry.contractAddress, registryAbi, "deviceAdapter"), ZERO_ADDRESS);

  const stablecoin = await deployChainoraTestUSDWithConfig(session, {
    owner: ANVIL_ADDRESS,
    initialSupply: 1000000000000000000000000n
  });

  const stablecoinData = encodeAdminCall(registryAbi, "setStablecoin", [stablecoin.contractAddress]);
  const stablecoinSchedule = await selectScheduleCandidate(session, {
    timelockAddress,
    target: registry.contractAddress,
    data: stablecoinData,
    predecessor: zeroHash,
    saltLabel: "setStablecoin"
  });

  await writeContract(session, {
    address: timelockAddress,
    abi: timelockAbi,
    functionName: "schedule",
    args: [registry.contractAddress, 0n, stablecoinData, zeroHash, stablecoinSchedule.salt, 0n],
    label: "schedule:setStablecoin"
  });

  const stablecoinExecute = await selectExecuteCandidate(session, {
    timelockAddress,
    target: registry.contractAddress,
    data: stablecoinData,
    predecessor: zeroHash,
    saltLabel: "setStablecoin"
  });

  await writeContract(session, {
    address: timelockAddress,
    abi: timelockAbi,
    functionName: "execute",
    args: [registry.contractAddress, 0n, stablecoinData, zeroHash, stablecoinExecute.salt],
    label: "execute:setStablecoin"
  });

  assert.equal(
    String(await readContract(session, registry.contractAddress, registryAbi, "stablecoin")).toLowerCase(),
    stablecoin.contractAddress.toLowerCase()
  );

  const newPoolImplementation = await deployPoolImplementationWithConfig(session, {}, 0);
  const poolImplData = encodeAdminCall(factoryAbi, "setPoolImplementation", [newPoolImplementation.contractAddress]);
  const poolImplSchedule = await selectScheduleCandidate(session, {
    timelockAddress,
    target: factory.contractAddress,
    data: poolImplData,
    predecessor: zeroHash,
    saltLabel: "setPoolImplementation"
  });

  await writeContract(session, {
    address: timelockAddress,
    abi: timelockAbi,
    functionName: "schedule",
    args: [factory.contractAddress, 0n, poolImplData, zeroHash, poolImplSchedule.salt, 0n],
    label: "schedule:setPoolImplementation"
  });

  await writeContract(session, {
    address: timelockAddress,
    abi: timelockAbi,
    functionName: "execute",
    args: [factory.contractAddress, 0n, poolImplData, zeroHash, poolImplSchedule.salt],
    label: "execute:setPoolImplementation"
  });

  assert.equal(
    String(await readContract(session, factory.contractAddress, factoryAbi, "poolImplementation")).toLowerCase(),
    newPoolImplementation.contractAddress.toLowerCase()
  );

  const secondRegistry = await deployRegistryWithConfig(session, { timelockAddress }, 0);
  const setRegistryData = encodeAdminCall(factoryAbi, "setRegistry", [secondRegistry.contractAddress]);
  const registrySchedule = await selectScheduleCandidate(session, {
    timelockAddress,
    target: factory.contractAddress,
    data: setRegistryData,
    predecessor: zeroHash,
    saltLabel: "setRegistry"
  });

  await writeContract(session, {
    address: timelockAddress,
    abi: timelockAbi,
    functionName: "schedule",
    args: [factory.contractAddress, 0n, setRegistryData, zeroHash, registrySchedule.salt, 0n],
    label: "schedule:setRegistry"
  });

  const operationBeforeCancel = /** @type {[bigint, boolean]} */ (
    await readContract(session, timelockAddress, TIMELOCK_UTILS_ABI, "operations", [registrySchedule.operationId])
  );
  const [readyAtBeforeCancel, executedBeforeCancel] = operationBeforeCancel;
  assert.equal(executedBeforeCancel, false);
  assert.ok(readyAtBeforeCancel > 0n);

  await writeContract(session, {
    address: timelockAddress,
    abi: timelockAbi,
    functionName: "cancel",
    args: [registrySchedule.operationId],
    label: "cancel:setRegistry"
  });

  const operationAfterCancel = /** @type {[bigint, boolean]} */ (
    await readContract(session, timelockAddress, TIMELOCK_UTILS_ABI, "operations", [registrySchedule.operationId])
  );
  const [readyAtAfterCancel, executedAfterCancel] = operationAfterCancel;
  assert.equal(readyAtAfterCancel, 0n);
  assert.equal(executedAfterCancel, false);

  assert.equal(deviceAdapter.contractAddress !== undefined, true);
});

test("deploy factory rejects dependencies without code", async () => {
  const anvil = await spawnAnvil({ port: 8548 });
  const { envPath } = await createTempEnv(`RPC_URL=${anvil.rpcUrl}\nPRIVATE_KEY=${ANVIL_PRIVATE_KEY}\n`);
  const session = await createSession({ envPath });

  const timelock = await deployTimelockWithConfig(
    session,
    {
      multisig: ANVIL_ADDRESS,
      delaySeconds: 0n,
      proposers: [ANVIL_ADDRESS],
      executors: [ANVIL_ADDRESS],
      cancellers: [ANVIL_ADDRESS]
    },
    0
  );

  await assert.rejects(() =>
    deployFactoryWithConfig(
      session,
      {
        timelockAddress: timelock.contractAddress,
        registryAddress: "0x000000000000000000000000000000000000dead",
        poolImplementationAddress: "0x000000000000000000000000000000000000beef"
      },
      0
    )
  );
});

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
