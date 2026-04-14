// @ts-check

import assert from "node:assert/strict";
import test from "node:test";

import { createMockRpcServer, ANVIL_PRIVATE_KEY, ANVIL_ADDRESS, createTempEnv } from "../helpers.js";
import { ensureClients } from "../../services/chain.js";
import { createSession } from "../../services/runtime.js";

test("ensureClients prompts for private key when env is missing", async () => {
  const mockRpc = await createMockRpcServer();
  const { envPath } = await createTempEnv(`RPC_URL=${mockRpc.url}\n`);
  const session = await createSession({
    envPath,
    promptPrivateKey: async () => ANVIL_PRIVATE_KEY
  });

  await ensureClients(session, { requireSigner: true });

  assert.equal(session.account?.address.toLowerCase(), ANVIL_ADDRESS);
});
