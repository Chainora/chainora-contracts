// @ts-nocheck

import { choose, promptAddress, promptBoolean, promptPredecessor, promptText } from "../prompts/common.js";
import { loadArtifact } from "../services/artifacts.js";
import { assertContractCode, ensureClients, writeContract } from "../services/chain.js";
import { printField, printHeader, printInfo, printSuccess, printWarning } from "../services/format.js";
import { ZERO_HASH, ensureAddress, ensureOptionalAddress } from "../services/shared.js";
import {
  encodeAdminCall,
  getRoleIds,
  getTimelockAbi,
  selectExecuteCandidate,
  selectScheduleCandidate,
  signerHasRole
} from "../services/timelock.js";

const ZERO = "0x0000000000000000000000000000000000000000";

const GROUPS = {
  registry: {
    label: "Registry",
    artifactName: "ChainoraProtocolRegistry",
    targetEnvKey: "CHAINORA_REGISTRY",
    actions: [
      {
        key: "setStablecoin",
        label: "setStablecoin",
        functionName: "setStablecoin",
        readCurrent: "stablecoin",
        syncEnvKey: null,
        async promptArgs(session, currentValue) {
          return [
            ensureAddress(
              await promptAddress({
                message: "Địa chỉ stablecoin mới",
                defaultValue:
                  session.envStore.getNonEmpty("CHAINORA_TEST_STABLECOIN") ??
                  currentValue
              }),
              "Stablecoin"
            )
          ];
        }
      },
      {
        key: "setDeviceAdapter",
        label: "setDeviceAdapter",
        functionName: "setDeviceAdapter",
        readCurrent: "deviceAdapter",
        syncEnvKey: "CHAINORA_DEVICE_ADAPTER",
        async promptArgs(_session, currentValue) {
          return [
            ensureOptionalAddress(
              await promptAddress({
                message: "Địa chỉ device adapter mới (cho phép zero address)",
                defaultValue: currentValue,
                allowZero: true
              }),
              "Device Adapter"
            ) ?? ZERO
          ];
        }
      },
      {
        key: "setReputationAdapter",
        label: "setReputationAdapter",
        functionName: "setReputationAdapter",
        readCurrent: "reputationAdapter",
        syncEnvKey: null,
        async promptArgs(_session, currentValue) {
          return [
            ensureOptionalAddress(
              await promptAddress({
                message: "Địa chỉ reputation adapter mới (cho phép zero address)",
                defaultValue: currentValue,
                allowZero: true
              }),
              "Reputation Adapter"
            ) ?? ZERO
          ];
        }
      },
      {
        key: "setStakingAdapter",
        label: "setStakingAdapter",
        functionName: "setStakingAdapter",
        readCurrent: "stakingAdapter",
        syncEnvKey: null,
        async promptArgs(_session, currentValue) {
          return [
            ensureOptionalAddress(
              await promptAddress({
                message: "Địa chỉ staking adapter mới (cho phép zero address)",
                defaultValue: currentValue,
                allowZero: true
              }),
              "Staking Adapter"
            ) ?? ZERO
          ];
        }
      }
    ]
  },
  factory: {
    label: "Factory",
    artifactName: "ChainoraRoscaFactory",
    targetEnvKey: "CHAINORA_FACTORY",
    actions: [
      {
        key: "setRegistry",
        label: "setRegistry",
        functionName: "setRegistry",
        readCurrent: "registry",
        syncEnvKey: "CHAINORA_REGISTRY",
        async promptArgs(_session, currentValue) {
          return [
            ensureAddress(
              await promptAddress({
                message: "Địa chỉ Registry mới",
                defaultValue: currentValue
              }),
              "Registry"
            )
          ];
        }
      },
      {
        key: "setPoolImplementation",
        label: "setPoolImplementation",
        functionName: "setPoolImplementation",
        readCurrent: "poolImplementation",
        syncEnvKey: "CHAINORA_POOL_IMPLEMENTATION",
        async promptArgs(_session, currentValue) {
          return [
            ensureAddress(
              await promptAddress({
                message: "Địa chỉ Pool Implementation mới",
                defaultValue: currentValue
              }),
              "Pool Implementation"
            )
          ];
        }
      }
    ]
  },
  deviceAdapter: {
    label: "Device Adapter",
    artifactName: "ChainoraDeviceAdapter",
    targetEnvKey: "CHAINORA_DEVICE_ADAPTER",
    actions: [
      {
        key: "setTrustVerifier",
        label: "setTrustVerifier",
        functionName: "setTrustVerifier",
        syncEnvKey: null,
        async promptArgs() {
          const verifier = ensureAddress(
            await promptAddress({
              message: "Địa chỉ verifier"
            }),
            "Verifier"
          );
          const allowed = await promptBoolean({
            message: "Cho phép verifier này?",
            defaultValue: true
          });
          return [verifier, allowed];
        }
      },
      {
        key: "revokeUser",
        label: "revokeUser",
        functionName: "revokeUser",
        syncEnvKey: null,
        async promptArgs() {
          return [
            ensureAddress(
              await promptAddress({
                message: "Địa chỉ user cần revoke"
              }),
              "User"
            )
          ];
        }
      }
    ]
  }
};

/**
 * @param {import("../services/runtime.js").CliSession} session
 * @param {"registry" | "factory" | "deviceAdapter"} groupKey
 */
export async function runAdminWizard(session, groupKey) {
  const group = GROUPS[groupKey];
  if (!group) {
    throw new Error("Nhóm admin không tồn tại.");
  }

  const actionKey = await choose({
    message: `Chọn action cho ${group.label}`,
    choices: [
      ...group.actions.map((action) => ({ name: action.label, value: action.key })),
      { name: "Quay lại", value: "back" }
    ]
  });
  if (actionKey === "back") return;

  const action = group.actions.find((item) => item.key === actionKey);
  if (!action) {
    throw new Error("Action admin không tồn tại.");
  }

  await ensureClients(session, { requireSigner: true });
  if (!session.account) {
    throw new Error("Thiếu signer account.");
  }

  const abi = (
    await loadArtifact(
      session.projectRoot,
      /** @type {keyof import("../services/artifacts.js").ARTIFACTS} */ (group.artifactName)
    )
  ).abi;
  const targetAddress = ensureAddress(
    await promptAddress({
      message: `Địa chỉ ${group.label}`,
      defaultValue: session.envStore.getNonEmpty(group.targetEnvKey)
    }),
    group.label
  );
  await assertContractCode(
    session,
    /** @type {keyof import("../services/artifacts.js").ARTIFACTS} */ (group.artifactName),
    targetAddress
  );

  let currentValue = "";
  if ("readCurrent" in action && action.readCurrent) {
    const { readContract } = await import("../services/chain.js");
    currentValue = String(await readContract(session, targetAddress, abi, action.readCurrent));
  }

  const args = await action.promptArgs(session, currentValue);
  await validateArguments(session, action.key, args);

  const mode = await choose({
    message: "Chọn mode timelock",
    choices: [
      { name: "schedule", value: "schedule" },
      { name: "execute", value: "execute" }
    ]
  });
  const advanced = await promptBoolean({
    message: "Chỉnh predecessor / salt label nâng cao?",
    defaultValue: false
  });
  const predecessor = /** @type {`0x${string}`} */ (advanced ? await promptPredecessor() : ZERO_HASH);
  const saltLabel = advanced
    ? await promptText({
        message: "Salt label",
        defaultValue: action.key
      })
    : action.key;

  const timelockAddress = ensureAddress(session.envStore.getNonEmpty("CHAINORA_TIMELOCK"), "CHAINORA_TIMELOCK");
  await assertContractCode(session, "ChainoraProtocolTimelock", timelockAddress);

  const data = encodeAdminCall(abi, action.functionName, args);

  printHeader(`${group.label} / ${action.label}`);
  printField("Mode", mode);
  printField("Target", targetAddress);
  printField("Current value", currentValue || "(không áp dụng)");
  printField("Args", JSON.stringify(args));
  printField("Salt label", saltLabel);
  printField("Predecessor", predecessor);

  const roles = await getRoleIds(session, timelockAddress);
  const role = mode === "schedule" ? roles.proposerRole : roles.executorRole;
  const roleName = mode === "schedule" ? "PROPOSER_ROLE" : "EXECUTOR_ROLE";
  const hasRole = await signerHasRole(session, {
    timelockAddress,
    role,
    accountAddress: session.account.address
  });
  if (!hasRole) {
    throw new Error(`Signer ${session.account.address} không có ${roleName}.`);
  }

  if (mode === "schedule") {
    const candidate = await selectScheduleCandidate(session, {
      timelockAddress,
      target: targetAddress,
      data,
      predecessor,
      saltLabel
    });

    printField("Operation ID", candidate.operationId);
    printField("Salt", candidate.salt);
    printField("Candidate index", candidate.index);

    if (candidate.kind === "existingPending") {
      printWarning("Đã có operation pending trùng payload này. CLI sẽ không schedule thêm.");
      return;
    }

    const timelockAbi = await getTimelockAbi(session);
    const { readContract } = await import("../services/chain.js");
    const minDelay = /** @type {bigint} */ (await readContract(session, timelockAddress, timelockAbi, "minDelay"));
    const result = await writeContract(session, {
      address: timelockAddress,
      abi: timelockAbi,
      functionName: "schedule",
      args: [targetAddress, 0n, data, predecessor, candidate.salt, minDelay],
      label: `${group.label}:${action.functionName}:schedule`
    });

    if (result.dryRun) {
      printInfo(`[dry-run] schedule sẽ tạo operation ${candidate.operationId}`);
      return;
    }

    printSuccess("Schedule thành công.");
    printField("Tx hash", result.hash);
    printField("Operation ID", candidate.operationId);
    return;
  }

  const candidate = await selectExecuteCandidate(session, {
    timelockAddress,
    target: targetAddress,
    data,
    predecessor,
    saltLabel
  });

  printField("Operation ID", candidate.operationId);
  printField("Salt", candidate.salt);
  printField("Ready at", candidate.readyAt);

  const timelockAbi = await getTimelockAbi(session);
  const result = await writeContract(session, {
    address: timelockAddress,
    abi: timelockAbi,
    functionName: "execute",
    args: [targetAddress, 0n, data, predecessor, candidate.salt],
    label: `${group.label}:${action.functionName}:execute`
  });

  if (result.dryRun) {
    printInfo(`[dry-run] execute sẽ chạy operation ${candidate.operationId}`);
    return;
  }

  printSuccess("Execute thành công.");
  printField("Tx hash", result.hash);
  printField("Operation ID", candidate.operationId);

  if (action.syncEnvKey) {
    const shouldSync = await promptBoolean({
      message: `Cập nhật ${action.syncEnvKey} vào .env?`,
      defaultValue: true
    });
    if (shouldSync) {
      await session.envStore.sync({
        [action.syncEnvKey]: String(args[0])
      });
      printSuccess(`Đã sync ${action.syncEnvKey} vào .env.`);
    }
  }
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 * @param {readonly unknown[]} args
 */
async function validateArguments(session, actionKey, args) {
  const { publicClient } = await ensureClients(session);

  const shouldHaveCode = new Set([
    "setStablecoin",
    "setDeviceAdapter",
    "setReputationAdapter",
    "setStakingAdapter",
    "setRegistry",
    "setPoolImplementation"
  ]);

  if (!shouldHaveCode.has(actionKey)) {
    return;
  }

  const addressLike = args.filter((arg) => typeof arg === "string" && /^0x[a-fA-F0-9]{40}$/.test(arg) && arg !== ZERO);
  for (const arg of addressLike) {
    const bytecode = await publicClient.getBytecode({ address: /** @type {`0x${string}`} */ (arg) });
    if (!bytecode) {
      throw new Error(`Địa chỉ ${arg} chưa có code trên chain.`);
    }
  }
}
