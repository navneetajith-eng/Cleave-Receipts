import { cp, mkdir, rm, writeFile } from "node:fs/promises";

const projectRoot = new URL("../", import.meta.url);
const outputRoot = new URL("../github-pages/", import.meta.url);
const workerUrl = new URL("../dist/server/index.js", import.meta.url);
workerUrl.searchParams.set("static", `${Date.now()}`);
const { default: worker } = await import(workerUrl.href);

const routes = [
  ["/", "index.html"],
  ["/privacy", "privacy/index.html"],
  ["/support", "support/index.html"],
];

await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });

for (const [route, destination] of routes) {
  const response = await worker.fetch(
    new Request(`http://localhost${route}`, { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );

  if (!response.ok) throw new Error(`${route} rendered with ${response.status}`);
  let html = await response.text();
  html = html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<link\b(?=[^>]*rel=["'](?:modulepreload|preload)["'])[^>]*>/gi, "")
    .replaceAll('href="/_next/', 'href="/cleave/_next/')
    .replaceAll('data-rsc-css-href="/_next/', 'data-rsc-css-href="/cleave/_next/')
    .replaceAll('href="/cleave-app-icon.png"', 'href="/cleave/cleave-app-icon.png"')
    .replaceAll('src="/cleave-logo-enhanced.png"', 'src="/cleave/cleave-logo-enhanced.png"')
    .replaceAll('href="/privacy"', 'href="/cleave/privacy/"')
    .replaceAll('href="/support"', 'href="/cleave/support/"')
    .replaceAll('href="/"', 'href="/cleave/"');

  const target = new URL(destination, outputRoot);
  await mkdir(new URL("./", target), { recursive: true });
  await writeFile(target, html);
}

await cp(new URL("../dist/client/_next/static/css/", import.meta.url), new URL("_next/static/css/", outputRoot), { recursive: true });
await cp(new URL("../public/cleave-app-icon.png", import.meta.url), new URL("cleave-app-icon.png", outputRoot));
await cp(new URL("../public/cleave-logo-enhanced.png", import.meta.url), new URL("cleave-logo-enhanced.png", outputRoot));
await writeFile(new URL(".nojekyll", outputRoot), "");
await writeFile(new URL("README.md", outputRoot), "# Cleave Privacy & Support\n\nOfficial public privacy and support pages for Cleave.\n");

console.log(outputRoot.pathname);
