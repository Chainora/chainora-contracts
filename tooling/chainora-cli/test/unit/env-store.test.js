// @ts-check

import assert from "node:assert/strict";
import fs from "node:fs/promises";
import test from "node:test";

import { createTempEnv } from "../helpers.js";
import { loadEnvStore } from "../../services/env-store.js";

test("EnvStore sync updates existing values and appends new keys", async () => {
  const { envPath } = await createTempEnv("RPC_URL=http://localhost:8545\nCHAINORA_FACTORY=\n# comment\n");
  const store = await loadEnvStore(envPath);

  await store.sync({
    CHAINORA_FACTORY: "0x1234",
    NEW_KEY: "value"
  });

  const nextText = await fs.readFile(envPath, "utf8");
  assert.match(nextText, /CHAINORA_FACTORY=0x1234/);
  assert.match(nextText, /NEW_KEY=value/);
  assert.equal(store.getNonEmpty("CHAINORA_FACTORY"), "0x1234");
});
