#!/usr/bin/env node
"use strict";

/**
 * Import AbstractFramework's Tabler icon families.
 *
 * Usage:
 *   node .utils/generate_tabler_icons.cjs /path/to/tabler-icons-v3.46.0
 *
 * The checked-in SVGs are the canonical 12.1+ assets. The generated 128px
 * RLE-TGA files keep the same artwork available to Retail 12.0.7 and older
 * clients that cannot load SVG files. Requires sharp 0.34.5.
 */

const fs = require("node:fs");
const path = require("node:path");

let sharp;
try {
    sharp = require("sharp");
} catch {
    throw new Error("The Tabler icon generator requires sharp 0.34.5.");
}

const TABLER_VERSION = "3.46.0";
const OUTPUT_SIZE = 128;
const OUTPUT_DIR = path.resolve(__dirname, "..", "Media", "Icons");

const ICONS = {
    Housing_Accents: "pillow",
    Housing_All: "apps",
    Housing_Beds: "bed",
    Housing_Bushes: "plant-2",
    Housing_CeilingLights: "bulb",
    Housing_Construction: "wall",
    Housing_Doors: "door",
    Housing_Featured: "star",
    Housing_Floor: "grid-pattern",
    Housing_FoodDrink: "tools-kitchen-2",
    Housing_Functional: "settings",
    Housing_Furnishings: "sofa",
    Housing_GroundCover: "clover",
    Housing_LargeFoliage: "tree",
    Housing_LargeLights: "lamp",
    Housing_LargeStructures: "building-estate",
    Housing_Lighting: "brightness-up",
    Housing_Misc: "triangle-square-circle",
    Housing_Nature: "leaf",
    Housing_Ornamental: "flower",
    Housing_PetBeds: "dog-bowl",
    Housing_Rooms: "layout-board",
    Housing_Seating: "armchair",
    Housing_SmallFoliage: "plant",
    Housing_SmallLights: "candle",
    Housing_Storage: "treasure-chest",
    Housing_Structural: "building-arch",
    Housing_Tables: "desk",
    Housing_Utility: "tools",
    Housing_Vines: "twig",
    Housing_WallHangings: "photo",
    Housing_WallLights: "lamp-2",
    Housing_Windows: "window",
    View_Reset: "restore",
    View_RotateLeft: "rotate",
    View_RotateRight: "rotate-clockwise",
    View_ZoomIn: "zoom-in",
    View_ZoomOut: "zoom-out",
};

function getTablerRoot() {
    const sourceRoot = process.argv[2];
    if (!sourceRoot) {
        throw new Error(
            "Pass the path to an unpacked Tabler Icons v3.46.0 checkout.",
        );
    }

    const absoluteRoot = path.resolve(sourceRoot);
    const packagePath = path.join(absoluteRoot, "package.json");
    if (!fs.existsSync(packagePath)) {
        throw new Error(`No package.json found under ${absoluteRoot}.`);
    }

    const packageInfo = JSON.parse(fs.readFileSync(packagePath, "utf8"));
    if (packageInfo.version !== TABLER_VERSION) {
        throw new Error(
            `Expected Tabler Icons ${TABLER_VERSION}, found ${packageInfo.version}.`,
        );
    }

    return absoluteRoot;
}

function normalizeSvg(source, iconName, tablerName) {
    const withoutComments = source.replace(/<!--[\s\S]*?-->/g, "").trim();
    const match = withoutComments.match(/<svg[\s\S]*?>([\s\S]*?)<\/svg>/);
    if (!match) {
        throw new Error(`Could not read ${tablerName}.svg.`);
    }

    const body = match[1]
        .trim()
        .split("\n")
        .map((line) => `  ${line.trim()}`)
        .join("\n");
    if (
        /<(?:filter|image|mask|script|style|text|use)\b/i.test(body) ||
        /\b(?:class|style|transform)=/i.test(body)
    ) {
        throw new Error(`${tablerName}.svg uses unsupported SVG features.`);
    }

    // The expanded viewBox gives every 24-unit Tabler glyph the same optical
    // padding without introducing transforms that WoW's SVG parser must handle.
    return [
        `<!-- ${iconName}: Tabler Icons v${TABLER_VERSION} ${tablerName}; MIT -->`,
        '<svg xmlns="http://www.w3.org/2000/svg"',
        '  width="24"',
        '  height="24"',
        '  viewBox="-2 -2 28 28"',
        '  fill="none"',
        '  stroke="#ffffff"',
        '  stroke-width="2"',
        '  stroke-linecap="round"',
        '  stroke-linejoin="round"',
        ">",
        body,
        "</svg>",
        "",
    ].join("\n");
}

function pixelsEqual(data, leftPixel, rightPixel) {
    const left = leftPixel * 4;
    const right = rightPixel * 4;
    return (
        data[left] === data[right] &&
        data[left + 1] === data[right + 1] &&
        data[left + 2] === data[right + 2] &&
        data[left + 3] === data[right + 3]
    );
}

function getRunLength(data, pixelIndex, pixelLimit) {
    let length = 1;
    while (
        length < 128 &&
        pixelIndex + length < pixelLimit &&
        pixelsEqual(data, pixelIndex, pixelIndex + length)
    ) {
        length += 1;
    }
    return length;
}

function getBgraPixel(data, pixelIndex) {
    const offset = pixelIndex * 4;
    return Buffer.from([
        data[offset + 2],
        data[offset + 1],
        data[offset],
        data[offset + 3],
    ]);
}

function encodeRleTga(data, width, height) {
    const header = Buffer.alloc(18);
    header[2] = 10; // RLE true-color image.
    header.writeUInt16LE(width, 12);
    header.writeUInt16LE(height, 14);
    header[16] = 32;
    header[17] = 0x28; // Eight alpha bits and a top-left image origin.

    const packets = [header];
    // TGA packets must remain inside their scanline for compatibility with
    // older decoders, including the one used by pre-12.1 WoW clients.
    for (let row = 0; row < height; row += 1) {
        let pixelIndex = row * width;
        const rowEnd = pixelIndex + width;

        while (pixelIndex < rowEnd) {
            const runLength = getRunLength(data, pixelIndex, rowEnd);
            if (runLength >= 2) {
                packets.push(
                    Buffer.from([0x80 | (runLength - 1)]),
                    getBgraPixel(data, pixelIndex),
                );
                pixelIndex += runLength;
                continue;
            }

            const rawStart = pixelIndex;
            pixelIndex += 1;
            while (
                pixelIndex < rowEnd &&
                pixelIndex - rawStart < 128 &&
                getRunLength(data, pixelIndex, rowEnd) < 2
            ) {
                pixelIndex += 1;
            }

            const rawLength = pixelIndex - rawStart;
            const rawPacket = Buffer.alloc(1 + rawLength * 4);
            rawPacket[0] = rawLength - 1;
            for (let index = 0; index < rawLength; index += 1) {
                getBgraPixel(data, rawStart + index).copy(
                    rawPacket,
                    1 + index * 4,
                );
            }
            packets.push(rawPacket);
        }
    }

    return Buffer.concat(packets);
}

async function generateIcon(tablerRoot, iconName, tablerName) {
    const sourcePath = path.join(
        tablerRoot,
        "icons",
        "outline",
        `${tablerName}.svg`,
    );
    if (!fs.existsSync(sourcePath)) {
        throw new Error(`Missing Tabler source icon ${sourcePath}.`);
    }

    const svg = normalizeSvg(
        fs.readFileSync(sourcePath, "utf8"),
        iconName,
        tablerName,
    );
    fs.writeFileSync(path.join(OUTPUT_DIR, `${iconName}.svg`), svg);

    const { data, info } = await sharp(Buffer.from(svg))
        .resize(OUTPUT_SIZE, OUTPUT_SIZE, { fit: "fill" })
        .ensureAlpha()
        .raw()
        .toBuffer({ resolveWithObject: true });

    const tga = encodeRleTga(data, info.width, info.height);
    fs.writeFileSync(path.join(OUTPUT_DIR, `${iconName}.tga`), tga);
}

async function main() {
    const tablerRoot = getTablerRoot();
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });

    for (const [iconName, tablerName] of Object.entries(ICONS)) {
        await generateIcon(tablerRoot, iconName, tablerName);
    }
}

main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});
