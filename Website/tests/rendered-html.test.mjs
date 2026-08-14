import assert from "node:assert/strict";
import test from "node:test";

async function render(path = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}-${path}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(new Request(`http://localhost${path}`, { headers: { accept: "text/html" } }), {
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
  }, { waitUntil() {}, passThroughOnException() {} });
}

test("renders the public home page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  assert.equal(response.headers.get("x-frame-options"), "DENY");
  assert.match(response.headers.get("content-security-policy") ?? "", /frame-ancestors 'none'/);
  const html = await response.text();
  assert.match(html, /Split the receipt/);
  assert.match(html, /Privacy policy/);
  assert.match(html, /Support/);
  assert.match(html, /\/og\.png/);
  assert.doesNotMatch(html, /codex-preview/);
});

test("renders a complete privacy policy", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.doesNotMatch(html, /RealTime Networking LLC/);
  assert.match(html, /Google Gemini/);
  assert.match(html, /Delete Account/);
  assert.match(html, /Google Pay UPI/);
  assert.match(html, /payment-status confirmations/);
  assert.match(html, /August 14, 2026/);
  assert.match(html, /cleave\.receipts@gmail\.com/);
});

test("renders support and deletion guidance", async () => {
  const response = await render("/support");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Email support/);
  assert.match(html, /Account deletion/);
  assert.match(html, /What is the difference between my display name and username/);
  assert.match(html, /What if group members use different currencies/);
  assert.match(html, /Is Cleave impossible to hack/);
  assert.match(html, /two business days/);
});

test("redirects the legacy TestFlight privacy URL to GitHub Pages", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}-legacy-redirect`);
  const { default: worker } = await import(workerUrl.href);
  const response = await worker.fetch(
    new Request("https://cleave-privacy-support.ryliemadisono.chatgpt.site/privacy?from=app"),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );

  assert.equal(response.status, 308);
  assert.equal(response.headers.get("location"), "https://navneetajith-eng.github.io/cleave/privacy/?from=app");
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
});
