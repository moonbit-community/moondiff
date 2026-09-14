import { expect, test } from "../../../playground/node_modules/@playwright/test/index.mjs";
import { resolve } from "node:path";

const github = "https://github.com/acme/widgets";
const githubHTML = "<!doctype html><title>GitHub fixture</title><style>button { background: red !important; color: black !important; }</style><main>GitHub fixture</main>";
const buttonOn = page => page.getByRole("button", {
  name: "Open this change in Moondiff",
  exact: true,
});

async function navigate(page, path) {
  await page.evaluate(nextPath => {
    history.pushState(null, "", nextPath);
    dispatchEvent(new Event("turbo:load"));
    dispatchEvent(new Event("pjax:end"));
    document.body.append(document.createElement("div"));
  }, path);
}

// Run the Firefox source in Firefox's real DOM and trusted input pipeline while
// replacing only the WebExtension messaging boundary.
async function loadContentScript(page, path) {
  await page.route("https://github.com/**", route => route.fulfill({
    contentType: "text/html",
    body: githubHTML,
  }));
  await page.goto(github + path);
  await page.evaluate(() => {
    globalThis.openRequests = [];
    globalThis.browser = {
      runtime: {
        sendMessage(message) {
          openRequests.push(message);
          return new Promise((resolveOpen, rejectOpen) => {
            globalThis.completeOpen = resolveOpen;
            globalThis.failOpen = rejectOpen;
          });
        },
      },
    };
  });
  for (const script of ["target.js", "content-script.js"]) {
    await page.addScriptTag({ path: resolve(import.meta.dirname, "../src", script) });
  }
}

test("Firefox displays one isolated button through SPA navigation and DOM redraws", async ({ page }) => {
  await loadContentScript(page, "");
  const button = buttonOn(page);
  await expect(button).toHaveCount(0);
  for (const path of [
    "/acme/widgets/pull/42",
    "/acme/widgets/pull/42/files",
    "/acme/widgets/pull/42/commits?x=1#comment",
    "/acme/widgets/commit/abcdef1",
  ]) {
    await navigate(page, path);
    await expect(button).toHaveCount(1);
    await expect(button).toBeVisible();
  }
  await expect(button).toHaveText("Open in Moondiff");
  await expect(button).toHaveCSS("background-color", "rgb(23, 23, 23)");
  await expect(button).toHaveCSS("color", "rgb(255, 255, 255)");
  await expect(button).toHaveCSS("position", "fixed");
  await expect(button).toHaveCSS("right", "20px");
  await expect(button).toHaveCSS("bottom", "20px");

  await page.evaluate(() => document.getElementById("moondiff-extension-root").remove());
  await expect(button).toHaveCount(1);
  await expect(button).toBeVisible();
  await page.evaluate(() => {
    history.replaceState(null, "", "/acme/widgets/issues/1");
    dispatchEvent(new PopStateEvent("popstate"));
  });
  await expect(button).toHaveCount(0);
  await page.evaluate(() => history.pushState(null, "", "/acme/widgets/pull/43"));
  await expect(button).toBeVisible();
  await page.evaluate(() => {
    location.hash = "#discussion_r1";
  });
  await expect(button).toHaveCount(1);
  expect(await page.evaluate(() => openRequests)).toEqual([]);
});

test("Firefox requires trusted mouse or keyboard input and allows retry after failure", async ({ page }) => {
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await loadContentScript(page, "/pull/42");
  const button = buttonOn(page);

  await button.evaluate(element => element.click());
  expect(await page.evaluate(() => openRequests)).toEqual([]);

  await button.click();
  await expect(button).toBeDisabled();
  await expect(button).toHaveAttribute("aria-busy", "true");
  const bounds = await button.boundingBox();
  await page.mouse.click(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
  expect(await page.evaluate(() => openRequests.length)).toBe(1);

  await page.evaluate(() => document.getElementById("moondiff-extension-root").remove());
  await expect(button).toHaveCount(1);
  await expect(button).toBeDisabled();
  await page.evaluate(() => failOpen(new Error("Event page unavailable")));
  await expect(button).toBeEnabled();
  await expect(button).not.toHaveAttribute("aria-busy");

  await button.press("Enter");
  await expect(button).toBeDisabled();
  await page.evaluate(() => completeOpen({
    ok: false,
    error: { message: "Cannot open tab" },
  }));
  await expect(button).toBeEnabled();

  await navigate(page, "/Acme/Widgets/pull/43/files?diff=split#comment");
  expect(await page.evaluate(() => openRequests.length)).toBe(2);
  await button.press("Space");
  expect(await page.evaluate(() => openRequests)).toEqual([
    { v: 1, op: "playground.open", args: { route: "/acme/widgets/pull/42" } },
    { v: 1, op: "playground.open", args: { route: "/acme/widgets/pull/42" } },
    { v: 1, op: "playground.open", args: { route: "/acme/widgets/pull/43" } },
  ]);
  await page.evaluate(() => completeOpen({
    ok: true,
    value: { tabId: 1, reused: false },
  }));
  await expect(button).toBeEnabled();
  await expect(button).not.toHaveAttribute("aria-busy");
  expect(errors).toEqual([]);
});
