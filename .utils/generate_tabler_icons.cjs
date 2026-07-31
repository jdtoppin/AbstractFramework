#!/usr/bin/env node
"use strict";

/**
 * Import AbstractFramework's Tabler icon families.
 *
 * Usage:
 *   node .utils/generate_tabler_icons.cjs /path/to/tabler-icons-v3.46.0
 *
 * The checked-in SVGs are Slug-compatible, filled-path assets for Retail
 * 12.1+. The generated 128px RLE-TGA files keep the same artwork available to
 * Retail 12.0.7 and older clients. Install the pinned .utils dependencies
 * and Potrace 1.16 before regenerating. Run with --check to validate checked-in
 * assets without installing those dependencies.
 */

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const TABLER_VERSION = "3.46.0";
const OUTPUT_SIZE = 128;
const TRACE_RESOLUTION = 4096;
const POTRACE_VERSION = "1.16";
const SVG_SIZE = 28;
const SVG_PADDING = 2;
const OUTPUT_DIR = path.resolve(__dirname, "..", "Media", "Icons");
const CHECK_ONLY = process.argv[2] === "--check";

let sharp;
let svgpath;

if (!CHECK_ONLY) {
    try {
        sharp = require("sharp");
        svgpath = require("svgpath");
    } catch {
        throw new Error(
            "Install the pinned icon generator dependencies with npm install --prefix .utils.",
        );
    }

    const version = spawnSync("potrace", ["--version"], { encoding: "utf8" });
    if (
        version.status !== 0 ||
        !version.stdout.startsWith(`potrace ${POTRACE_VERSION}.`)
    ) {
        throw new Error(`The icon generator requires Potrace ${POTRACE_VERSION}.`);
    }
}

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
    Lock: "lock",
    Unlock: "lock-open",
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

function getSourcePaths(source, tablerName) {
    const withoutComments = source.replace(/<!--[\s\S]*?-->/g, "").trim();
    const match = withoutComments.match(/<svg[\s\S]*?>([\s\S]*?)<\/svg>/);
    if (!match) {
        throw new Error(`Could not read ${tablerName}.svg.`);
    }

    const body = match[1].trim();
    const pathPattern = /<path\b[^>]*\bd="([^"]+)"[^>]*\/?>/gi;
    const paths = [...body.matchAll(pathPattern)].map((pathMatch) => pathMatch[1]);
    const unsupportedBody = body.replace(pathPattern, "").trim();
    if (!paths.length || unsupportedBody) {
        throw new Error(`${tablerName}.svg must contain only path elements.`);
    }

    return paths;
}

function createStrokeSvg(paths) {
    const normalizedPaths = paths.map((pathData) =>
        svgpath(pathData)
            .abs()
            .translate(SVG_PADDING, SVG_PADDING)
            .round(4)
            .toString(),
    );

    return [
        `<svg xmlns="http://www.w3.org/2000/svg" width="${SVG_SIZE}" height="${SVG_SIZE}" viewBox="0 0 ${SVG_SIZE} ${SVG_SIZE}">`,
        ...normalizedPaths.map(
            (pathData) =>
                `  <path fill="none" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="${pathData}"/>`,
        ),
        "</svg>",
        "",
    ].join("\n");
}

function closeFilledSubpaths(pathData) {
    return pathData
        .split(/(?=M)/)
        .map((subpath) => subpath.trim())
        .filter(Boolean)
        .map((subpath) => (subpath.endsWith("Z") ? subpath : subpath + "Z"))
        .join("");
}

async function createPortableBitmap(strokeSvg) {
    const renderedSvg = strokeSvg.replace(
        `width="${SVG_SIZE}" height="${SVG_SIZE}"`,
        `width="${TRACE_RESOLUTION}" height="${TRACE_RESOLUTION}"`,
    );
    const { data, info } = await sharp(Buffer.from(renderedSvg))
        .ensureAlpha()
        .raw()
        .toBuffer({ resolveWithObject: true });
    const rowBytes = Math.ceil(info.width / 8);
    const pixels = Buffer.alloc(rowBytes * info.height);

    for (let y = 0; y < info.height; y += 1) {
        for (let x = 0; x < info.width; x += 1) {
            if (data[(y * info.width + x) * 4 + 3] >= 128) {
                pixels[y * rowBytes + Math.floor(x / 8)] |= 0x80 >> (x % 8);
            }
        }
    }

    return Buffer.concat([
        Buffer.from(`P4\n${info.width} ${info.height}\n`),
        pixels,
    ]);
}

async function createSlugSvg(strokeSvg, iconName) {
    const bitmap = await createPortableBitmap(strokeSvg);
    const traced = spawnSync(
        "potrace",
        [
            "--svg",
            "--flat",
            "--unit", "1",
            "--turdsize", "2",
            "--alphamax", "1",
            "--opttolerance", "0.2",
            "--output", "-",
            "-",
        ],
        {
            input: bitmap,
            encoding: "utf8",
            maxBuffer: 20 * 1024 * 1024,
        },
    );
    if (traced.status !== 0) {
        throw new Error(`${iconName} could not be traced: ${traced.stderr.trim()}`);
    }

    const match = traced.stdout.match(/<path d="([\s\S]+?)"\/>/);
    if (!match || !match[1].trim()) {
        throw new Error(`${iconName} did not produce a filled path.`);
    }

    let pathData = svgpath(match[1])
        .abs()
        .scale(SVG_SIZE / TRACE_RESOLUTION, -SVG_SIZE / TRACE_RESOLUTION)
        .translate(0, SVG_SIZE)
        .unshort()
        .unarc()
        .round(3)
        .toString();
    pathData = closeFilledSubpaths(pathData);
    pathData = svgpath(pathData).abs().unshort().unarc().round(3).toString();

    return [
        `<svg xmlns="http://www.w3.org/2000/svg" width="${SVG_SIZE}" height="${SVG_SIZE}" viewBox="0 0 ${SVG_SIZE} ${SVG_SIZE}">`,
        `  <path fill="#ffffff" d="${pathData}"/>`,
        "</svg>",
        "",
    ].join("\n");
}

function validateSlugSvg(svg, iconName) {
    if (!svg.startsWith("<svg ")) {
        throw new Error(`${iconName}.svg must start with the SVG root element.`);
    }
    if (
        /<!--|\bstroke=|\b(?:class|style|transform)=|<(?:filter|image|mask|script|text|use)\b/i.test(
            svg,
        )
    ) {
        throw new Error(`${iconName}.svg uses unsupported Slug features.`);
    }
    if (!svg.includes(`width="${SVG_SIZE}" height="${SVG_SIZE}" viewBox="0 0 ${SVG_SIZE} ${SVG_SIZE}"`)) {
        throw new Error(`${iconName}.svg must use the normalized ${SVG_SIZE}-unit viewport.`);
    }

    const elements = [...svg.matchAll(/<([A-Za-z][A-Za-z0-9]*)\b/g)].map(
        (match) => match[1].toLowerCase(),
    );
    if (elements.join(",") !== "svg,path") {
        throw new Error(`${iconName}.svg must contain exactly one filled path.`);
    }

    const pathMatch = svg.match(/<path fill="#ffffff" d="([^"]+)"\/>/);
    if (!pathMatch) {
        throw new Error(`${iconName}.svg is missing its normalized filled path.`);
    }

    const commands = pathMatch[1].match(/[A-Za-z]/g) || [];
    if (!commands.length || commands.some((command) => !"MLCQZ".includes(command))) {
        throw new Error(`${iconName}.svg contains an unsupported path command.`);
    }

    const subpaths = pathMatch[1]
        .split(/(?=M)/)
        .map((subpath) => subpath.trim())
        .filter(Boolean);
    if (!subpaths.length || subpaths.some((subpath) => !subpath.endsWith("Z"))) {
        throw new Error(`${iconName}.svg contains an unclosed contour.`);
    }

    const coordinates = pathMatch[1].match(/[-+]?(?:\d*\.)?\d+/g) || [];
    if (
        !coordinates.length ||
        coordinates.some((coordinate) => {
            const value = Number(coordinate);
            return !Number.isFinite(value) || value < 0 || value > SVG_SIZE;
        })
    ) {
        throw new Error(`${iconName}.svg contains an out-of-bounds coordinate.`);
    }
}

function validateTga(tga, iconName) {
    const expectedPixels = OUTPUT_SIZE * OUTPUT_SIZE;
    if (
        tga.length < 18 ||
        tga[0] !== 0 ||
        tga[1] !== 0 ||
        tga[2] !== 10 ||
        tga.readUInt16LE(12) !== OUTPUT_SIZE ||
        tga.readUInt16LE(14) !== OUTPUT_SIZE ||
        tga[16] !== 32 ||
        tga[17] !== 0x28
    ) {
        throw new Error(`${iconName}.tga is not a ${OUTPUT_SIZE}px RGBA RLE-TGA.`);
    }

    let offset = 18;
    let decodedPixels = 0;
    while (decodedPixels < expectedPixels) {
        if (offset >= tga.length) {
            throw new Error(`${iconName}.tga has a truncated RLE payload.`);
        }

        const packet = tga[offset];
        const packetPixels = (packet & 0x7f) + 1;
        const packetBytes = packet & 0x80 ? 4 : packetPixels * 4;
        offset += 1;

        if (
            decodedPixels + packetPixels > expectedPixels ||
            offset + packetBytes > tga.length
        ) {
            throw new Error(`${iconName}.tga has an invalid RLE packet.`);
        }

        decodedPixels += packetPixels;
        offset += packetBytes;
    }

    if (decodedPixels !== expectedPixels || offset !== tga.length) {
        throw new Error(`${iconName}.tga has an unexpected RLE payload length.`);
    }
}

async function validateVisualFidelity(strokeSvg, slugSvg, iconName) {
    const comparisonSize = 1024;
    const atComparisonSize = (svg) =>
        svg.replace(
            `width="${SVG_SIZE}" height="${SVG_SIZE}"`,
            `width="${comparisonSize}" height="${comparisonSize}"`,
        );
    const [source, converted] = await Promise.all([
        sharp(Buffer.from(atComparisonSize(strokeSvg)))
            .ensureAlpha()
            .raw()
            .toBuffer(),
        sharp(Buffer.from(atComparisonSize(slugSvg)))
            .ensureAlpha()
            .raw()
            .toBuffer(),
    ]);

    let alphaError = 0;
    for (let index = 3; index < source.length; index += 4) {
        alphaError += Math.abs(source[index] - converted[index]);
    }
    const meanAlphaError = alphaError / (source.length / 4);
    if (meanAlphaError > 0.5) {
        throw new Error(
            `${iconName}.svg exceeded the visual fidelity limit (${meanAlphaError.toFixed(3)}).`,
        );
    }
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

    const source = fs.readFileSync(sourcePath, "utf8");
    const sourcePaths = getSourcePaths(source, tablerName);
    const strokeSvg = createStrokeSvg(sourcePaths);
    const svg = await createSlugSvg(strokeSvg, iconName);
    validateSlugSvg(svg, iconName);
    await validateVisualFidelity(strokeSvg, svg, iconName);
    fs.writeFileSync(path.join(OUTPUT_DIR, `${iconName}.svg`), svg);

    const { data, info } = await sharp(Buffer.from(svg))
        .resize(OUTPUT_SIZE, OUTPUT_SIZE, { fit: "fill" })
        .ensureAlpha()
        .raw()
        .toBuffer({ resolveWithObject: true });

    const tga = encodeRleTga(data, info.width, info.height);
    validateTga(tga, iconName);
    fs.writeFileSync(path.join(OUTPUT_DIR, `${iconName}.tga`), tga);
}

function checkGeneratedAssets() {
    for (const iconName of Object.keys(ICONS)) {
        const svgPath = path.join(OUTPUT_DIR, `${iconName}.svg`);
        const tgaPath = path.join(OUTPUT_DIR, `${iconName}.tga`);
        if (!fs.existsSync(svgPath) || !fs.existsSync(tgaPath)) {
            throw new Error(`${iconName} is missing an SVG or TGA asset.`);
        }

        validateSlugSvg(fs.readFileSync(svgPath, "utf8"), iconName);
        validateTga(fs.readFileSync(tgaPath), iconName);
    }
}

async function main() {
    if (CHECK_ONLY) {
        checkGeneratedAssets();
        console.log("Tabler icon assets passed Slug and raster validation.");
        return;
    }

    const tablerRoot = getTablerRoot();
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });

    for (const [iconName, tablerName] of Object.entries(ICONS)) {
        await generateIcon(tablerRoot, iconName, tablerName);
    }

    checkGeneratedAssets();
}

main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});
