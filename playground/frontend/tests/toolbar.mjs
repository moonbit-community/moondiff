import { expect } from "@playwright/test";

export async function checkToolbar(page) {
  const hero = page.locator(".hero-workspace");
  await expect(hero.locator("input:not([type=checkbox]), form, a, .submit-arrow, .copy-button, .view-toggle")).toHaveCount(0);
  const url = hero.locator(".workspace-url");
  await expect(url).toBeVisible();
  await expect(url).toHaveAttribute("title", await url.textContent());
  await expect(hero.locator(".workspace-actions button:not(.file-tree-trigger)")).toHaveText([
    "Token", "Tree", "Split", "Unified",
  ]);
  await expect(hero.locator(".toolbar-filter")).toHaveText(["Ignore comments", "Ignore tests"]);
  for (const name of ["Ignore comments", "Ignore tests"]) {
    await expect(hero.getByRole("checkbox", { name, exact: true })).toBeChecked();
  }
  for (const mode of ["Split", "Unified", "Unified", "Split", "Split"]) {
    await page.getByRole("button", { name: mode, exact: true }).click();
    await expect(page.getByRole("button", { name: mode, exact: true })).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("button", { name: mode === "Split" ? "Unified" : "Split", exact: true })).toHaveAttribute("aria-pressed", "false");
    await expect(page.locator(`table.${mode.toLowerCase()}`).first()).toBeVisible();
  }
  for (const colorScheme of ["light", "dark"]) {
    await page.emulateMedia({ colorScheme });
    for (const width of [320, 360, 460, 540, 680, 681, 768, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      const metrics = await hero.evaluate(el => {
        const groups = [...el.querySelectorAll(".segmented-control")].map(node => node.getBoundingClientRect());
        const buttons = [...el.querySelectorAll(".segmented-option")].map(node => {
          const style = getComputedStyle(node);
          return [style.height, style.padding, style.borderRadius];
        });
        return {
          overflow: document.documentElement.scrollWidth > innerWidth,
          toolbarOverflow: el.scrollWidth > el.clientWidth,
          adjacent: groups[0].y === groups[1].y && groups[0].right < groups[1].left,
          buttons,
          height: el.getBoundingClientRect().height,
          offset: parseFloat(getComputedStyle(document.querySelector(".file-heading")).top),
          selectable: getComputedStyle(el.querySelector(".workspace-url")).userSelect,
        };
      });
      expect(metrics.overflow, `${colorScheme} ${width}px page`).toBe(false);
      expect(metrics.toolbarOverflow, `${colorScheme} ${width}px toolbar`).toBe(false);
      expect(metrics.adjacent).toBe(true);
      expect(metrics.buttons.every(value => JSON.stringify(value) === JSON.stringify(metrics.buttons[0]))).toBe(true);
      expect(Math.abs(metrics.height - metrics.offset), `${colorScheme} ${width}px sticky offset`).toBeLessThanOrEqual(2);
      expect(metrics.selectable).toBe("text");
    }
  }
}
