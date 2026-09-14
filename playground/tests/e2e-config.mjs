const e2eHost = "127.0.0.1";

export function readE2EConfig(env = process.env) {
  const port = Number(env.PORT || 4173);
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error(`Invalid Playground E2E port: ${env.PORT}`);
  }
  return { port, origin: new URL(`http://${e2eHost}:${port}`).origin };
}

const e2eConfig = readE2EConfig();
export const e2ePort = e2eConfig.port;
export const e2eOrigin = e2eConfig.origin;
