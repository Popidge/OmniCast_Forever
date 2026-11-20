// Syntax-checks every .lua file in the repo root (the addon) as Lua 5.1 (WoW's dialect) and
// flags accidental global assignments. Usage: node tools/check-lua.mjs
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
// Globals the addon is allowed to define.
const ALLOWED_GLOBALS = new Set([
  "OmniCastForeverDB", "OmniCastForeverLog", "SLASH_OMNICASTFOREVER1", "SLASH_OMNICASTFOREVER2",
]);

let failed = false;
for (const file of readdirSync(root).filter((f) => f.endsWith(".lua"))) {
  const src = readFileSync(join(root, file), "utf8");
  let ast;
  try {
    ast = luaparse.parse(src, { luaVersion: "5.1", scope: true, locations: true });
  } catch (e) {
    console.error(`FAIL ${file}: ${e.message}`);
    failed = true;
    continue;
  }
  const leaks = [];
  const walk = (node) => {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) return node.forEach(walk);
    if (node.type === "AssignmentStatement") {
      for (const v of node.variables) {
        if (v.type === "Identifier" && !v.isLocal && !ALLOWED_GLOBALS.has(v.name)) {
          leaks.push(`${v.name} (line ${v.loc.start.line})`);
        }
      }
    }
    for (const k of Object.keys(node)) if (k !== "loc" && k !== "range") walk(node[k]);
  };
  walk(ast);
  if (leaks.length) {
    console.error(`FAIL ${file}: global assignment: ${leaks.join(", ")}`);
    failed = true;
  } else {
    console.log(`ok   ${file}`);
  }
}
// Cross-file check: every call to a module function (C.X, ns.Mod:X, Mod:X)
// must have a matching definition. Catches deleted/renamed functions, which
// the parser can't see and which only blow up in game.
const files = readdirSync(root).filter((f) => f.endsWith(".lua"));
const defined = new Set();
const aliases = {}; // file -> { localVar: moduleName }
for (const file of files) {
  const src = readFileSync(join(root, file), "utf8");
  const a = (aliases[file] = { C: "Compat" });
  for (const m of src.matchAll(/local (\w+) = ns:NewModule\("(\w+)"\)/g)) a[m[1]] = m[2];
  for (const m of src.matchAll(/^\s*function (\w+)[.:](\w+)\s*\(/gm)) {
    defined.add(`${a[m[1]] ?? m[1]}.${m[2]}`);
  }
  for (const m of src.matchAll(/^\s*(\w+)\.(\w+)\s*=\s*function/gm)) defined.add(`${a[m[1]] ?? m[1]}.${m[2]}`);
}
for (const file of files) {
  const src = readFileSync(join(root, file), "utf8").replace(/--.*$/gm, "");
  const a = aliases[file];
  const missing = new Set();
  const check = (mod, fn) => { if (!defined.has(`${mod}.${fn}`)) missing.add(`${mod}.${fn}`); };
  for (const m of src.matchAll(/\bns\.(\w+)[.:](\w+)\s*\(/g)) {
    if (/^[A-Z]/.test(m[1])) check(m[1], m[2]); // ns.Module only, not ns.db etc.
  }
  for (const [v, mod] of Object.entries(a)) {
    const re = new RegExp(`(?<![\\w.])${v}[.:](\\w+)\\s*\\(`, "g");
    for (const m of src.matchAll(re)) check(mod, m[1]);
  }
  if (missing.size) {
    console.error(`FAIL ${file}: calls undefined module function(s): ${[...missing].join(", ")}`);
    failed = true;
  }
}
process.exit(failed ? 1 : 0);
