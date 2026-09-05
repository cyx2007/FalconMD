import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import sharp from "sharp";

const args = process.argv.slice(2);
if (args.length > 1 || (args.length === 1 && args[0] !== "--check")) {
  throw new Error("Usage: node generate.mjs [--check]");
}
const check = args[0] === "--check";
const root = fileURLToPath(new URL("../../", import.meta.url));
const source = path.join(root, "design/app-icon/falconmd-icon.svg");
const assets = path.join(root, "FalconMD/Assets.xcassets/AppIcon.appiconset");
const svg = await readFile(source);
const sourceMetadata = await sharp(svg).metadata();
if (sourceMetadata.width !== 1024 || sourceMetadata.height !== 1024) {
  throw new Error("The SVG source must have a 1024 × 1024 canvas.");
}

const { data, info } = await sharp(svg).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
for (let index = info.channels - 1; index < data.length; index += info.channels) {
  if (data[index] !== 255) {
    throw new Error("The app icon must have a fully opaque background.");
  }
}

const catalog = JSON.parse(await readFile(path.join(assets, "Contents.json"), "utf8"));
const outputs = new Map();
for (const entry of catalog.images) {
  const [width, height] = entry.size.split("x").map(Number);
  const scale = Number(entry.scale.replace(/x$/, ""));
  const pixels = width * scale;
  if (entry.idiom !== "mac" || width !== height || !Number.isInteger(pixels) || pixels <= 0
      || !/^AppIcon-\d+\.png$/.test(entry.filename)) {
    throw new Error(`Unsupported app icon entry: ${JSON.stringify(entry)}`);
  }
  if (outputs.has(entry.filename) && outputs.get(entry.filename) !== pixels) {
    throw new Error(`Conflicting dimensions for ${entry.filename}`);
  }
  outputs.set(entry.filename, pixels);
}

for (const [filename, pixels] of outputs) {
  const destination = path.join(assets, filename);
  const expected = await sharp(svg).resize(pixels, pixels).removeAlpha().png().toBuffer();
  if (check) {
    const actual = await readFile(destination);
    const metadata = await sharp(actual).metadata();
    const [expectedPixels, actualPixels] = await Promise.all([
      sharp(expected).raw().toBuffer(),
      sharp(actual).raw().toBuffer(),
    ]);
    if (metadata.format !== "png" || metadata.width !== pixels || metadata.height !== pixels
        || metadata.hasAlpha || !actualPixels.equals(expectedPixels)) {
      throw new Error(`${filename} differs from the SVG. Run npm run generate.`);
    }
  } else {
    await writeFile(destination, expected);
  }
}

console.log(`${check ? "Verified" : "Generated"} ${outputs.size} PNG files for ${catalog.images.length} macOS icon entries.`);
