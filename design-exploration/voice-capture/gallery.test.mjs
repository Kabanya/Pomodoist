import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { chromium } from "playwright";

const entry = new URL("./index.html", import.meta.url);
const browsers = {};
const shapes = [
  ".overlay .trail",
  ".orb-btn",
  ".centered .vertical",
  ".inline-panel",
  ".example blockquote",
  ".console .ruler",
  ".steps-page .fold-body",
];

before(async () => {
  browsers.primary = await chromium.launch({
    headless: true,
    executablePath: process.env.CHROMIUM_EXECUTABLE_PATH,
  });
});
after(async () => {
  await browsers.primary?.close();
});

async function open(t, variant, viewport, reducedMotion = "no-preference") {
  const page = await browsers.primary.newPage({ viewport, reducedMotion });
  const errors = [],
    network = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("request", (r) => {
    if (/^https?:/.test(r.url())) network.push(r.url());
  });
  await page.addInitScript(() => {
    navigator.mediaDevices.getUserMedia = async () => {
      throw new Error("Unexpected microphone request");
    };
  });
  t.after(async () => {
    await page.close();
    assert.deepEqual(errors, []);
    assert.deepEqual(network, []);
  });
  await page.clock.install();
  await page.goto(entry.href + "#" + variant);
  return page;
}

const action = (page, name) => page.locator('[data-action="' + name + '"]');
async function phase(page, state) {
  await page.waitForSelector('#screen[data-phase="' + state + '"]');
}
async function assertGeometry(page, selector) {
  const clipped = await page.locator(selector).evaluateAll((elements) =>
    elements
      .filter((e) => {
        const box = e.getBoundingClientRect();
        const frame = document.querySelector(".phone").getBoundingClientRect();
        return (
          box.width &&
          box.height &&
          (box.left < frame.left - 1 ||
            box.right > frame.right + 1 ||
            box.top < frame.top - 1 ||
            box.bottom > frame.bottom + 1)
        );
      })
      .map((e) => e.textContent.trim() || e.getAttribute("aria-label")),
  );
  assert.deepEqual(clipped, []);
}

for (let variant = 1; variant <= 7; variant++) {
  test(
    "Variant " +
      variant +
      " records, minimizes, reviews and saves long dictation",
    async (t) => {
      const page = await open(t, variant, { width: 390, height: 844 });
      assert.equal(await page.locator(shapes[variant - 1]).count(), 1);
      assert.equal(await action(page, "record").count(), 1);
      await page.getByRole("switch").click();
      assert.equal(
        await page.getByRole("switch").getAttribute("aria-checked"),
        "true",
      );
      await action(page, "record").click();
      await phase(page, "recording");
      assert.equal(
        await page
          .locator(".signal i")
          .first()
          .evaluate((e) => getComputedStyle(e).animationName),
        "wave",
      );
      await page.clock.fastForward(2100);
      assert.match(
        await page.locator("[data-clock]").first().innerText(),
        /^00:0[2-4]$/,
      );
      await page.keyboard.press("Escape");
      assert.equal(await page.locator(".capsule").count(), 1);
      await page.clock.fastForward(1100);
      await action(page, "expand").click();
      await phase(page, "recording");
      await action(page, "stop").click();
      await phase(page, "analyzing");
      assert.equal(await page.getByRole("progressbar").count(), 1);
      await page.clock.fastForward(1400);
      await phase(page, "review");
      const drafts = page.locator(".review-row");
      assert.equal(await drafts.count(), 15);
      const footer = await action(page, "save").boundingBox();
      await drafts.last().locator("summary").click();
      const literal = "Проверить <смету> & подписать";
      await drafts.last().locator("input").fill(literal);
      assert.equal(await drafts.last().locator("strong").innerText(), literal);
      await drafts.nth(13).locator("summary").click();
      await drafts.nth(13).locator("input").fill(" ");
      assert.equal(await action(page, "save").innerText(), "Добавить 14 задач");
      assert.deepEqual(await action(page, "save").boundingBox(), footer);
      await action(page, "save").click();
      await phase(page, "saved");
      assert.equal(
        await page.locator(".saved-message").innerText(),
        "Добавлено задач: 14",
      );
      assert.ok(
        (await page.locator(".bg-task").allTextContents()).includes(literal),
      );
      await action(page, "open").click();
      await phase(page, "idle");
      await action(page, "close").click();
      assert.equal(await action(page, "open").count(), 1);
    },
  );

  test(
    "Variant " +
      variant +
      " fits phone and desktop, supports reduced motion and the recording limit",
    async (t) => {
      const page = await open(
        t,
        variant,
        { width: 320, height: 568 },
        "reduce",
      );
      for (const [width, height] of [
        [320, 568],
        [390, 844],
        [768, 900],
        [1440, 900],
      ]) {
        await page.setViewportSize({ width, height });
        assert.equal(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth,
          ),
          true,
        );
        await assertGeometry(page, "#screen button");
      }
      await action(page, "record").click();
      assert.equal(
        await page.evaluate(() => document.getAnimations().length),
        0,
      );
      await action(page, "mini").click();
      await page.clock.fastForward(300000);
      await phase(page, "analyzing");
      await page.clock.fastForward(1400);
      await phase(page, "review");
      assert.equal(await page.locator(".capsule").count(), 1);
      await action(page, "expand").click();
      await action(page, "again").click();
      await phase(page, "idle");
      await action(page, "record").click();
      await action(page, "stop").click();
      await action(page, "close").click();
      await page.clock.fastForward(1800);
      await phase(page, "closed");
    },
  );
}
test("All seven designs are directly addressable and browser history resets pending work", async (t) => {
  const page = await open(t, 1, { width: 1280, height: 900 });
  for (let i = 1; i <= 7; i++) {
    await page
      .locator("nav a")
      .nth(i - 1)
      .click();
    await page.waitForSelector('#screen[data-variant="' + i + '"]');
    assert.equal(await page.locator("nav a[aria-current]").count(), 1);
    assert.equal(await page.locator(shapes[i - 1]).count(), 1);
  }
  await action(page, "record").click();
  await action(page, "stop").click();
  await page.goBack();
  await page.waitForSelector('#screen[data-variant="6"]');
  await page.clock.fastForward(1500);
  await phase(page, "idle");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByLabel("Вариант оформления").selectOption("3");
  await page.waitForSelector('#screen[data-variant="3"]');
  assert.equal(new URL(page.url()).hash, "#3");
});
