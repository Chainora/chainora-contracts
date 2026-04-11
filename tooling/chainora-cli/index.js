#!/usr/bin/env node
// @ts-nocheck

import { parseArgs } from "node:util";

import { runAdminWizard } from "./actions/admin.js";
import { runDeployWizard } from "./actions/deploy.js";
import { cancelOperation, inspectOperation } from "./actions/timelock.js";
import { chooseAdminGroup, chooseMainMenu, chooseTimelockMenu } from "./menus/main.js";
import { promptPrivateKey as promptHiddenPrivateKey } from "./prompts/common.js";
import { createSession } from "./services/runtime.js";

async function main() {
  const args = parseArgs({
    allowPositionals: false,
    options: {
      "rpc-url": {
        type: "string"
      },
      "dry-run": {
        type: "boolean"
      }
    }
  });

  const session = await createSession({
    rpcUrlOverride: args.values["rpc-url"],
    dryRun: args.values["dry-run"] ?? false,
    promptPrivateKey: () => promptHiddenPrivateKey("Nhập PRIVATE_KEY (ẩn ký tự)")
  });

  while (true) {
    const mainChoice = await chooseMainMenu();
    if (mainChoice === "exit") break;

    if (mainChoice === "deploy") {
      await runDeployWizard(session);
      continue;
    }

    if (mainChoice === "admin") {
      const group = await chooseAdminGroup();
      if (group !== "back") {
        await runAdminWizard(session, group);
      }
      continue;
    }

    const timelockChoice = await chooseTimelockMenu();
    if (timelockChoice === "inspect") {
      await inspectOperation(session);
    } else if (timelockChoice === "cancel") {
      await cancelOperation(session);
    }
  }
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exitCode = 1;
});
