// @ts-check

import { promptAddress, promptText } from "../prompts/common.js";
import { assertContractCode, ensureClients, writeContract } from "../services/chain.js";
import { printField, printHeader, printInfo, printSuccess } from "../services/format.js";
import { ensureAddress } from "../services/shared.js";
import { getRoleIds, getTimelockAbi, signerHasRole, TIMELOCK_UTILS_ABI } from "../services/timelock.js";

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function inspectOperation(session) {
  const timelockAddress = ensureAddress(
    await promptAddress({
      message: "Địa chỉ timelock",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_TIMELOCK")
    }),
    "Timelock"
  );
  await assertContractCode(session, "ChainoraProtocolTimelock", timelockAddress);
  const operationId = /** @type {`0x${string}`} */ (
    await promptText({
      message: "Operation ID"
    })
  );

  const { readContract } = await import("../services/chain.js");
  const [readyAt, executed] = /** @type {[bigint, boolean]} */ (
    await readContract(session, timelockAddress, TIMELOCK_UTILS_ABI, "operations", [operationId])
  );

  printHeader("Inspect Operation");
  printField("Timelock", timelockAddress);
  printField("Operation ID", operationId);
  printField("Ready at", readyAt);
  printField("Executed", executed);
}

/**
 * @param {import("../services/runtime.js").CliSession} session
 */
export async function cancelOperation(session) {
  const timelockAddress = ensureAddress(
    await promptAddress({
      message: "Địa chỉ timelock",
      defaultValue: session.envStore.getNonEmpty("CHAINORA_TIMELOCK")
    }),
    "Timelock"
  );
  await assertContractCode(session, "ChainoraProtocolTimelock", timelockAddress);
  const operationId = /** @type {`0x${string}`} */ (
    await promptText({
      message: "Operation ID cần cancel"
    })
  );

  await ensureClients(session, { requireSigner: true });
  if (!session.account) {
    throw new Error("Thiếu signer address.");
  }

  const roles = await getRoleIds(session, timelockAddress);
  const hasRole = await signerHasRole(session, {
    timelockAddress,
    role: roles.cancellerRole,
    accountAddress: session.account.address
  });
  if (!hasRole) {
    throw new Error(`Signer ${session.account.address} không có CANCELLER_ROLE.`);
  }

  const timelockAbi = await getTimelockAbi(session);
  const result = await writeContract(session, {
    address: timelockAddress,
    abi: timelockAbi,
    functionName: "cancel",
    args: [operationId],
    label: "timelock:cancel"
  });

  printHeader("Cancel Operation");
  printField("Operation ID", operationId);

  if (result.dryRun) {
    printInfo(`[dry-run] sẽ cancel operation ${operationId}`);
    return;
  }

  printSuccess("Cancel thành công.");
  printField("Tx hash", result.hash);
}
