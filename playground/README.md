# Moondiff playground

## Prerequisites

- MoonBit toolchain
- Node.js 22 and npm

## Setup

From the repository root:

```sh
moon update
cd playground
npm ci
```

Install Chromium once before running the browser tests:

```sh
npx playwright install chromium
```

Use `npx playwright install --with-deps chromium` instead on systems that are
missing Chromium's system dependencies.

## Development

From `playground/`:

```sh
npm run dev
```

The playground is served at `http://127.0.0.1:4173`. Set `HOST` or `PORT` to
override the address. This command builds the frontend once and watches only
`server.mjs`; restart it after changing `main/` or `public/`.

Create a production build in `playground/dist` with:

```sh
npm run build
```

## Checks

Run the following from the repository root:

```sh
moon check playground/main --target js --deny-warn
moon test playground/main --target js
node --test playground/tests/server.test.mjs
npm run test:playground
```
