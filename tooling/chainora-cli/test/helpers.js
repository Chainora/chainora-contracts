// @ts-check

import assert from "node:assert/strict";
import { after } from "node:test";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

export const ANVIL_PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
export const ANVIL_ADDRESS = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";

/**
 * @param {string} contents
 */
export async function createTempEnv(contents) {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "chainora-cli-"));
  const envPath = path.join(tempDir, ".env");
  await fs.writeFile(envPath, contents, "utf8");
  return { tempDir, envPath };
}

/**
 * @param {{ port: number }} options
 */
export async function spawnAnvil(options) {
  const child = spawn(
    "anvil",
    ["--host", "127.0.0.1", "--port", String(options.port), "--chain-id", "31337", "--silent"],
    {
      stdio: "ignore"
    }
  );

  const rpcUrl = `http://127.0.0.1:${options.port}`;
  await waitForRpc(rpcUrl);

  const stop = async () => {
    child.kill("SIGTERM");
    await new Promise((resolve) => child.once("exit", resolve));
  };

  after(async () => {
    if (!child.killed) {
      await stop();
    }
  });

  return { rpcUrl, stop };
}

/**
 * @param {{
 *   chainId?: string,
 *   gasPrice?: string,
 *   baseFeePerGas?: string,
 *   maxPriorityFeePerGas?: string
 * }} [options]
 */
export async function createMockRpcServer(options = {}) {
  const server = http.createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) {
      chunks.push(chunk);
    }

    const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    const method = body.method;
    const params = body.params ?? [];

    /** @type {unknown} */
    let result;
    if (method === "eth_chainId") {
      result = options.chainId ?? "0x7a69";
    } else if (method === "eth_gasPrice") {
      result = options.gasPrice ?? "0x0";
    } else if (method === "eth_maxPriorityFeePerGas") {
      result = options.maxPriorityFeePerGas ?? "0x0";
    } else if (method === "eth_getBlockByNumber") {
      void params;
      result = {
        number: "0x1",
        baseFeePerGas: options.baseFeePerGas ?? "0x0"
      };
    } else {
      result = "0x0";
    }

    response.writeHead(200, { "content-type": "application/json" });
    response.end(
      JSON.stringify({
        id: body.id ?? 1,
        jsonrpc: "2.0",
        result
      })
    );
  });

  await new Promise((resolve) =>
    server.listen(0, "127.0.0.1", () => {
      resolve(undefined);
    })
  );
  const address = server.address();
  assert(address && typeof address === "object");
  const url = `http://127.0.0.1:${address.port}`;

  after(async () => {
    await new Promise((resolve) => server.close(resolve));
  });

  return { url, close: () => new Promise((resolve) => server.close(resolve)) };
}

/**
 * @param {string} rpcUrl
 */
async function waitForRpc(rpcUrl) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      const response = await fetch(rpcUrl, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: 1,
          jsonrpc: "2.0",
          method: "eth_chainId",
          params: []
        })
      });
      if (response.ok) return;
    } catch {
      // retry
    }

    await new Promise((resolve) => setTimeout(resolve, 200));
  }

  throw new Error(`RPC ${rpcUrl} không phản hồi kịp.`);
}
