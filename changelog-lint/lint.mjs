import {existsSync, readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

export const TYPES = ['NEW FEATURE', 'ENHANCEMENT', 'BUGFIX', 'SECURITY', 'DEPRECATION', 'BC BREAK', 'CHORE'];
export const MARKERS = ['HIGHLIGHT', 'OPT-IN', 'FOLLOW-UP', 'MIGRATION'];

const TITLE = '# Changelog';
const VERSION = /^## (\d+)\.(\d+)\.(\d+)$/;
const ENTRY = /^- (.*)$/;
const ANNOUNCEMENT = /^ {2}> (.+)$/;
const STEP = /^ {2}(\d+)\. (.+)$/;
const CONTINUATION = /^ {2}(?![-*+] |> |\d+\. )(\S.*)$/;
const TAG = /^\[([A-Z][A-Z /-]*)\] */;

/**
 * Reads a CHANGELOG.md. Every line that does not follow the grammar is reported with its number, and an entry
 * with an error stays out of the result, so nothing downstream reads half of an entry.
 *
 * @param {string} text
 * @returns {{versions: Version[], errors: {line: number, message: string}[]}}
 *
 * @typedef {{version: string, line: number, entries: Entry[]}} Version
 * @typedef {{type: string, markers: string[], text: string, announcement: string | null, steps: string[], line: number}} Entry
 */
export function parseChangelog(text) {

    const lines = text.replace(/\r\n/g, '\n').split('\n');
    const versions = [];
    const errors = [];
    const fail = (line, message) => errors.push({line, message});

    let version = null;
    let entry = null;
    let previous = '';

    const close = () => {
        if (entry !== null && checkEntry(entry, fail)) {
            version.entries.push(toEntry(entry));
        }

        entry = null;
    };

    const firstLine = lines.findIndex(line => line.trim() !== '');

    if (firstLine === -1 || lines[firstLine] !== TITLE) {
        fail(firstLine + 1 || 1, `The file starts with "${TITLE}".`);
    }

    lines.forEach((raw, index) => {
        const number = index + 1;
        const line = raw.trimEnd();
        const directlyBelow = previous !== '';
        previous = line;

        if (index === firstLine || line === '') {
            return;
        }

        const heading = line.match(VERSION);

        if (heading) {
            close();
            version = {version: heading.slice(1).join('.'), numbers: heading.slice(1).map(Number), line: number, entries: []};
            checkOrder(versions.at(-1), version, fail);
            versions.push(version);

            return;
        }

        const item = line.match(ENTRY);

        if (item) {
            close();

            if (version === null) {
                fail(number, 'An entry belongs under a version heading such as "## 1.5.0".');

                return;
            }

            entry = readEntry(item[1], number, fail);

            return;
        }

        const continuation = line.match(CONTINUATION);

        // A long entry, announcement or step may wrap onto the following lines, as Markdown allows.
        if (continuation && entry !== null && directlyBelow) {
            const part = entry.steps.length > 0 ? entry.steps : entry.announcement.length > 0 ? entry.announcement : null;

            if (part === null) {
                entry.text = `${entry.text} ${continuation[1]}`;
            } else {
                part[part.length - 1] = `${part.at(-1)} ${continuation[1]}`;
            }

            return;
        }

        const announcement = line.match(ANNOUNCEMENT);
        const step = line.match(STEP);

        if ((announcement || step) && entry === null) {
            fail(number, 'A line starting with "  >" or a numbered step belongs directly under an entry.');

            return;
        }

        if (announcement) {
            entry.announcement.push(announcement[1]);

            return;
        }

        if (step) {
            if (Number(step[1]) !== entry.steps.length + 1) {
                fail(number, `The steps are numbered 1, 2, 3 in order. This step is ${step[1]}, expected ${entry.steps.length + 1}.`);
                entry.valid = false;
            }

            entry.steps.push(step[2]);

            return;
        }

        fail(number, 'The line is no version heading, no entry, no announcement and no step.');
    });

    close();

    return {
        versions: versions.map(({numbers, ...rest}) => rest),
        errors,
    };
}

function readEntry(content, line, fail) {
    const tags = [];
    let rest = content;
    let tag;

    while ((tag = rest.match(TAG)) !== null) {
        tags.push(tag[1]);
        rest = rest.slice(tag[0].length);
    }

    const [type, ...markers] = tags;
    const entry = {type, markers, text: rest.trim(), announcement: [], steps: [], line, valid: true};

    if (!TYPES.includes(type)) {
        fail(line, type === undefined
            ? `The entry starts with a type: ${TYPES.map(name => `[${name}]`).join(', ')}.`
            : `[${type}] is no type. Use one of ${TYPES.map(name => `[${name}]`).join(', ')}.`);
        entry.valid = false;
    }

    for (const marker of markers) {
        if (!MARKERS.includes(marker)) {
            fail(line, `[${marker}] is no marker. Use ${MARKERS.map(name => `[${name}]`).join(', ')}.`);
            entry.valid = false;
        }
    }

    if (new Set(markers).size !== markers.length) {
        fail(line, 'A marker appears only once per entry.');
        entry.valid = false;
    }

    if (entry.text === '') {
        fail(line, 'The entry has no text.');
        entry.valid = false;
    }

    return entry;
}

function checkEntry(entry, fail) {
    const highlight = entry.markers.includes('HIGHLIGHT');
    const stepsFor = ['OPT-IN', 'FOLLOW-UP'].filter(marker => entry.markers.includes(marker));
    const needsSteps = entry.type === 'BC BREAK' || stepsFor.length > 0;

    if (highlight && entry.announcement.length === 0) {
        fail(entry.line, 'A [HIGHLIGHT] has an announcement under the entry: a line "  > ..." that tells a reader who does not code what the change is good for.');
        entry.valid = false;
    }

    if (!highlight && entry.announcement.length > 0) {
        fail(entry.line, 'Only a [HIGHLIGHT] has an announcement, a line "  > ..." under the entry.');
        entry.valid = false;
    }

    if (needsSteps && entry.steps.length === 0) {
        fail(entry.line, `${entry.type === 'BC BREAK' ? 'A [BC BREAK]' : `${stepsFor[0] === 'OPT-IN' ? 'An' : 'A'} [${stepsFor[0]}]`} has steps: lines "  1. ..." under the entry.`);
        entry.valid = false;
    }

    if (!needsSteps && entry.steps.length > 0) {
        fail(entry.line, 'Only a [BC BREAK], an [OPT-IN] or a [FOLLOW-UP] has steps.');
        entry.valid = false;
    }

    return entry.valid;
}

function toEntry({type, markers, text, announcement, steps, line}) {
    return {type, markers, text, announcement: announcement.length > 0 ? announcement.join(' ') : null, steps, line};
}

function checkOrder(previous, current, fail) {
    if (previous === undefined) {
        return;
    }

    const difference = current.numbers.findIndex((part, index) => part !== previous.numbers[index]);

    if (difference === -1) {
        fail(current.line, `${current.version} appears twice.`);
    } else if (current.numbers[difference] > previous.numbers[difference]) {
        fail(current.line, `The versions go from the newest down. ${current.version} stands below ${previous.version}.`);
    }
}

/**
 * The rules for the version that comes next, the top one on the development branch. A [BC BREAK] belongs to a major
 * release only. The history keeps what it has.
 *
 * @param {Version[]} versions
 * @returns {{line: number, message: string}[]}
 */
export function checkNextVersion(versions) {
    const [next] = versions;

    if (next === undefined || /^\d+\.0\.0$/.test(next.version)) {
        return [];
    }

    return next.entries
        .filter(entry => entry.type === 'BC BREAK')
        .map(entry => ({line: entry.line, message: `${next.version} is no major release. A [BC BREAK] waits for the next major.`}));
}

// Run as a script, it lints the CHANGELOG.md of the working directory: its form, and no [BC BREAK] in a minor or a
// patch release. Whether a pull request touches the changelog at all is the job of dangoslen/changelog-enforcer.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
    const file = 'CHANGELOG.md';

    if (!existsSync(file)) {
        console.log(`::error file=${file},line=1::The repository has no ${file}.`);
        process.exit(1);
    }

    const {versions, errors} = parseChangelog(readFileSync(file, 'utf8'));
    const all = [...errors, ...checkNextVersion(versions)];

    for (const {line, message} of all) {
        console.log(process.env.GITHUB_ACTIONS ? `::error file=${file},line=${line}::${message}` : `${file}:${line}: ${message}`);
    }

    process.exit(all.length === 0 ? 0 : 1);
}
