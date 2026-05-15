import "./style.css";

const root = document.getElementById("root");

let files = [];
let lastPatch = "";
let lastThemeType = "system";
let allCollapsed = false;
let isWrapped = false;
let currentVisiblePath = null;
let scrollFrameRequested = false;
let allowsReviewMarkers = true;
let reviewedFileSignatures = {};
let highlightCorePromise = null;
const languagePromises = new Map();
const loadedLanguages = new Set();
const expandedContextByHunk = new Set();

const languageByExtension = new Map(
  Object.entries({
    bash: "bash",
    c: "c",
    cc: "cpp",
    cpp: "cpp",
    cs: "csharp",
    css: "css",
    cxx: "cpp",
    diff: "diff",
    go: "go",
    h: "cpp",
    hpp: "cpp",
    html: "xml",
    java: "java",
    js: "javascript",
    json: "json",
    jsx: "javascript",
    kt: "kotlin",
    kts: "kotlin",
    m: "objectivec",
    mm: "objectivec",
    md: "markdown",
    php: "php",
    py: "python",
    rb: "ruby",
    rs: "rust",
    sh: "bash",
    sql: "sql",
    swift: "swift",
    toml: "ini",
    ts: "typescript",
    tsx: "typescript",
    xml: "xml",
    yml: "yaml",
    yaml: "yaml",
    zig: "zig",
  })
);

const languageByFilename = new Map(
  Object.entries({
    dockerfile: "dockerfile",
    gemfile: "ruby",
    makefile: "makefile",
    package: "json",
    podfile: "ruby",
    rakefile: "ruby",
  })
);

function post(message) {
  window.webkit?.messageHandlers?.diffRenderer?.postMessage(message);
}

function createElement(tagName, className, text) {
  const element = document.createElement(tagName);
  if (className) element.className = className;
  if (text != null) element.textContent = text;
  return element;
}

function normalizePath(path) {
  return path
    .trim()
    .replace(/^"|"$/g, "")
    .replace(/^[ab]\//, "");
}

function languageForPath(path) {
  const fileName = path.split("/").pop()?.toLowerCase() ?? "";
  if (languageByFilename.has(fileName)) return languageByFilename.get(fileName);

  const parts = fileName.split(".");
  if (parts.length < 2) return null;
  const extension = parts.at(-1);
  return languageByExtension.get(extension) ?? null;
}

function parseDiffHeader(line) {
  const match = line.match(/^diff --git (?:"a\/(.+?)"|a\/(\S+)) (?:"b\/(.+?)"|b\/(\S+))$/);
  if (!match) return { oldPath: null, newPath: null };
  return {
    oldPath: normalizePath(match[1] ?? match[2] ?? ""),
    newPath: normalizePath(match[3] ?? match[4] ?? ""),
  };
}

function splitPatch(patch) {
  const lines = patch.replace(/\r\n/g, "\n").split("\n");
  const chunks = [];
  let current = [];

  for (const line of lines) {
    if (line.startsWith("diff --git ") && current.length > 0) {
      chunks.push(current);
      current = [line];
    } else {
      current.push(line);
    }
  }
  if (current.some((line) => line.trim() !== "")) chunks.push(current);
  return chunks;
}

function parseHunkHeader(line) {
  const match = line.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$/);
  if (!match) return null;
  const oldCount = Number(match[2] ?? "1");
  const newCount = Number(match[4] ?? "1");
  return {
    oldLine: Number(match[1]),
    oldCount,
    newLine: Number(match[3]),
    newCount,
    label: line,
    context: match[5]?.trim() ?? "",
  };
}

function lineRangeText(startLine, count) {
  if (count <= 0) return `line ${startLine}`;
  if (count === 1) return `line ${startLine}`;
  return `lines ${startLine}-${startLine + count - 1}`;
}

function lineCountText(count) {
  if (count <= 1) return "1 line";
  return `${count} lines`;
}

function hunkTitle(hunk) {
  if (hunk.context) return hunk.context;

  if (hunk.oldCount === 0 && hunk.newCount > 0) {
    if (hunk.oldLine === 0 || hunk.newLine <= 1) return `Added ${lineCountText(hunk.newCount)} at file start`;
    return `Added ${lineCountText(hunk.newCount)} at line ${hunk.newLine}`;
  }

  if (hunk.newCount === 0 && hunk.oldCount > 0) {
    return `Removed ${lineCountText(hunk.oldCount)} at line ${hunk.oldLine}`;
  }

  return `Edited around line ${hunk.newLine}`;
}

function hunkSubtitle(hunk) {
  if (hunk.context) return null;
  return null;
}

function hiddenLineTitle(count) {
  return `Show ${count} hidden line${count === 1 ? "" : "s"}`;
}

function parseFileChunk(lines, fileIndex) {
  const firstHeader = parseDiffHeader(lines.find((line) => line.startsWith("diff --git ")) ?? "");
  let oldPath = firstHeader.oldPath;
  let newPath = firstHeader.newPath;
  let status = "modified";
  let additions = 0;
  let deletions = 0;
  let oldLine = 0;
  let newLine = 0;
  let hunkIndex = 0;
  let currentHunkId = null;
  let previousHunkNewEnd = 0;
  const rows = [];
  const metadata = [];

  for (const line of lines) {
    if (line.startsWith("--- ")) {
      const value = normalizePath(line.slice(4));
      if (value !== "/dev/null") oldPath = value;
      continue;
    }
    if (line.startsWith("+++ ")) {
      const value = normalizePath(line.slice(4));
      if (value !== "/dev/null") newPath = value;
      continue;
    }
    if (line.startsWith("new file")) {
      status = "added";
      metadata.push(line);
      continue;
    }
    if (line.startsWith("deleted file")) {
      status = "deleted";
      metadata.push(line);
      continue;
    }
    if (line.startsWith("rename from ")) {
      status = "renamed";
      oldPath = normalizePath(line.slice("rename from ".length));
      metadata.push(line);
      continue;
    }
    if (line.startsWith("rename to ")) {
      status = "renamed";
      newPath = normalizePath(line.slice("rename to ".length));
      metadata.push(line);
      continue;
    }
    if (
      line.startsWith("index ") ||
      line.startsWith("similarity index ") ||
      line.startsWith("dissimilarity index ") ||
      line.startsWith("old mode ") ||
      line.startsWith("new mode ")
    ) {
      metadata.push(line);
      continue;
    }

    const hunk = parseHunkHeader(line);
    if (hunk) {
      const hiddenStartLine = previousHunkNewEnd === 0 ? 1 : previousHunkNewEnd;
      const hiddenEndLine = hunk.newLine - 1;
      const hiddenLineCount = Math.max(0, hiddenEndLine - hiddenStartLine + 1);
      oldLine = hunk.oldLine;
      newLine = hunk.newLine;
      currentHunkId = `file-${fileIndex}-hunk-${hunkIndex++}`;
      previousHunkNewEnd = hunk.newLine + Math.max(0, hunk.newCount);
      if (hiddenLineCount > 0) {
        rows.push({
          type: "hunk",
          title: hiddenLineTitle(hiddenLineCount),
          subtitle: hunkSubtitle(hunk) ?? hunkTitle(hunk),
          rawText: hunk.label,
          lineNumber: "",
          hunkId: currentHunkId,
          filePath: null,
          hiddenStartLine,
          hiddenEndLine,
        });
      }
      continue;
    }

    if (line.startsWith("+") && !line.startsWith("+++")) {
      rows.push({ type: "add", text: line.slice(1), lineNumber: newLine++, hunkId: currentHunkId });
      additions += 1;
      continue;
    }

    if (line.startsWith("-") && !line.startsWith("---")) {
      rows.push({ type: "delete", text: line.slice(1), lineNumber: oldLine++, hunkId: currentHunkId });
      deletions += 1;
      continue;
    }

    if (line.startsWith("\\ No newline at end of file")) {
      rows.push({ type: "notice", text: line, lineNumber: "", hunkId: currentHunkId });
      continue;
    }

    if (line.startsWith(" ") || rows.length > 0) {
      const text = line.startsWith(" ") ? line.slice(1) : line;
      rows.push({ type: "context", text, lineNumber: newLine++, hunkId: currentHunkId });
      oldLine += 1;
    }
  }

  const path = newPath || oldPath || "Unknown file";
  let finalRows = rows;
  for (const row of finalRows) {
    if (row.type === "hunk") row.filePath = path;
  }

  return {
    path,
    oldPath,
    newPath,
    status,
    additions,
    deletions,
    language: languageForPath(path),
    metadata,
    rows: finalRows,
  };
}

function parsePatch(patch) {
  return splitPatch(patch)
    .map((chunk, index) => parseFileChunk(chunk, index))
    .filter((file) => file.rows.length > 0 || file.metadata.length > 0);
}

function createStatus(message) {
  return createElement("div", "status", message);
}

function normalizeReviewedState(state) {
  if (!state || typeof state !== "object") return {};
  const normalized = {};
  for (const [path, signature] of Object.entries(state)) {
    if (typeof path !== "string" || typeof signature !== "string") continue;
    normalized[normalizePath(path)] = signature;
  }
  return normalized;
}

function createStat(className, value) {
  const stat = createElement("span", `stat ${className}`, value);
  return stat;
}

function createFileSignature(file) {
  const parts = [`status:${file.status}`];
  for (const row of file.rows) {
    if (row.type === "hunk") {
      parts.push(`h:${row.rawText ?? ""}`);
      continue;
    }
    parts.push(`${row.type}:${row.lineNumber}:${row.text ?? ""}`);
  }
  return parts.join("\n");
}

function isReviewed(file) {
  return reviewedFileSignatures[file.path] === createFileSignature(file);
}

function postReviewedStateChanged() {
  post({
    type: "reviewedStateChanged",
    reviewedFileSignatures,
    reviewedCount: Object.keys(reviewedFileSignatures).length,
    fileCount: files.length,
  });
}

function renderFileHeader(file) {
  const header = createElement("button", "file-header");
  header.type = "button";
  header.dataset.path = file.path;
  header.setAttribute("aria-expanded", String(!allCollapsed));
  if (isReviewed(file)) header.classList.add("is-reviewed");

  const leading = createElement("span", "file-leading");
  const chevron = createElement("span", "file-chevron", "▾");
  chevron.setAttribute("aria-hidden", "true");
  if (allowsReviewMarkers) {
    const checkbox = createElement("input", "file-review-toggle");
    checkbox.type = "checkbox";
    checkbox.checked = isReviewed(file);
    checkbox.title = "Mark file as reviewed";
    checkbox.setAttribute("aria-label", `Mark ${file.path} as reviewed`);
    checkbox.addEventListener("click", (event) => {
      event.stopPropagation();
    });
    checkbox.addEventListener("change", (event) => {
      event.stopPropagation();
      const section = header.closest(".file");
      if (checkbox.checked) {
        reviewedFileSignatures[file.path] = createFileSignature(file);
        header.classList.add("is-reviewed");
        if (section) {
          section.classList.add("collapsed");
          header.setAttribute("aria-expanded", "false");
        }
      } else {
        delete reviewedFileSignatures[file.path];
        header.classList.remove("is-reviewed");
      }
      postReviewedStateChanged();
    });
    leading.append(checkbox);
  }
  leading.append(chevron);

  const titleWrap = createElement("span", "file-title-wrap");
  const title = createElement("span", "file-title", file.path);
  titleWrap.append(title);
  if (file.status === "renamed" && file.oldPath && file.oldPath !== file.path) {
    titleWrap.append(createElement("span", "file-subtitle", `renamed from ${file.oldPath}`));
  }

  const stats = createElement("span", "file-stats");
  if (file.additions > 0) stats.append(createStat("added", `+${file.additions}`));
  if (file.deletions > 0) stats.append(createStat("deleted", `-${file.deletions}`));
  if (file.additions === 0 && file.deletions === 0) stats.append(createStat("neutral", file.status));

  leading.append(titleWrap);
  header.append(leading, stats);
  header.addEventListener("click", () => {
    const section = header.closest(".file");
    const collapsed = section.classList.toggle("collapsed");
    header.setAttribute("aria-expanded", String(!collapsed));
    chevron.textContent = collapsed ? "▸" : "▾";
  });
  return header;
}

function renderRow(row) {
  if (row.type === "hunk") return renderHunkRow(row);

  const line = createElement("div", `diff-row ${row.type}`);
  if (row.hunkId) line.dataset.hunkId = row.hunkId;
  const lineNo = createElement("span", "line-number", row.lineNumber);
  const marker = createElement("span", "marker", row.type === "add" ? "+" : row.type === "delete" ? "-" : "");
  const code = createElement("code", "code", row.text);
  if (row.language && row.type !== "hunk" && row.type !== "notice") {
    code.dataset.language = row.language;
    code.dataset.raw = row.text;
  }
  line.append(lineNo, marker, code);
  return line;
}

function renderHunkRow(row) {
  const line = createElement("div", "diff-row hunk");
  line.tabIndex = 0;
  line.role = "button";
  line.dataset.hunkId = row.hunkId;
  line.dataset.filePath = row.filePath ?? "";
  line.dataset.startLine = String(row.hiddenStartLine ?? 1);
  line.dataset.endLine = String(row.hiddenEndLine ?? row.hiddenStartLine ?? 1);
  line.setAttribute("aria-expanded", "false");
  line.title = row.rawText ?? "";

  const gutter = createElement("span", "hunk-gutter");
  const chevron = createElement("span", "hunk-chevron", "▸");
  gutter.append(chevron);

  const content = createElement("span", "hunk-content");
  content.append(createElement("span", "hunk-title", row.title));
  if (row.subtitle) content.append(createElement("span", "hunk-subtitle", row.subtitle));
  line.append(gutter, content);
  const requestFromPointer = (event) => {
    if (event instanceof MouseEvent && event.button !== 0) return;
    event.preventDefault();
    const hunkId = line.dataset.hunkId;
    if (!hunkId || expandedContextByHunk.has(hunkId) || line.classList.contains("loading")) return;
    line.classList.add("loading");
    post({
      type: "requestHunkContext",
      hunkId,
      filePath: line.dataset.filePath ?? "",
      startLine: Number(line.dataset.startLine ?? "1"),
      endLine: Number(line.dataset.endLine ?? line.dataset.startLine ?? "1"),
    });
  };
  line.addEventListener("click", requestFromPointer);
  return line;
}

function hunkHeaderFromEvent(event) {
  const target = event.target;
  if (!(target instanceof Element)) return null;
  return target.closest(".diff-row.hunk");
}

root.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" && event.key !== " ") return;
  const header = hunkHeaderFromEvent(event);
  if (!header) return;
  event.preventDefault();
  header.click();
});

function showHunkContext(payload) {
  const hunkId = payload?.hunkId;
  if (!hunkId || expandedContextByHunk.has(hunkId)) return;
  const header = root.querySelector(`.diff-row.hunk[data-hunk-id="${CSS.escape(hunkId)}"]`);
  if (!header) return;
  header.classList.remove("loading");
  header.setAttribute("aria-expanded", "true");

  let lineNo = Number(payload?.startLine ?? 1);
  if (!Number.isFinite(lineNo) || lineNo < 1) lineNo = 1;
  const lines = Array.isArray(payload?.lines) ? payload.lines : [];
  const fragment = document.createDocumentFragment();
  const language = languageForPath(header.dataset.filePath ?? "");
  for (const text of lines) {
    const row = createElement("div", "diff-row context reveal");
    const code = createElement("code", "code", String(text ?? ""));
    if (language) {
      code.dataset.language = language;
      code.dataset.raw = String(text ?? "");
    }
    row.append(
      createElement("span", "line-number", String(lineNo++)),
      createElement("span", "marker", "·"),
      code
    );
    fragment.append(row);
  }
  if (lines.length === 0) {
    const row = createElement("div", "diff-row notice reveal");
    row.append(
      createElement("span", "line-number", ""),
      createElement("span", "marker", ""),
      createElement("code", "code", "No additional context available")
    );
    fragment.append(row);
  }
  expandedContextByHunk.add(hunkId);
  header.replaceWith(fragment);
  applySyntaxHighlighting();
}

function renderFile(file) {
  const section = createElement("section", "file");
  section.dataset.path = file.path;
  if (allCollapsed) section.classList.add("collapsed");
  section.append(renderFileHeader(file));

  const body = createElement("div", "file-body");
  for (const row of file.rows) {
    row.language = file.language;
    body.append(renderRow(row));
  }
  section.append(body);
  return section;
}

function loadHighlightCore() {
  if (!highlightCorePromise) {
    highlightCorePromise = import(/* @vite-ignore */ "https://esm.sh/highlight.js@11.11.1/lib/core").then(
      (module) => module.default
    );
  }
  return highlightCorePromise;
}

function loadLanguage(language) {
  if (loadedLanguages.has(language)) return Promise.resolve();
  if (languagePromises.has(language)) return languagePromises.get(language);

  const promise = Promise.all([
    loadHighlightCore(),
    import(/* @vite-ignore */ `https://esm.sh/highlight.js@11.11.1/lib/languages/${language}`),
  ])
    .then(([hljs, module]) => {
      hljs.registerLanguage(language, module.default);
      loadedLanguages.add(language);
    })
    .catch((error) => {
      console.warn(`Syntax highlighting unavailable for ${language}`, error);
    });

  languagePromises.set(language, promise);
  return promise;
}

function applySyntaxHighlighting() {
  const languages = Array.from(new Set(files.map((file) => file.language).filter(Boolean)));
  if (languages.length === 0) return;

  Promise.all(languages.map(loadLanguage))
    .then(() => loadHighlightCore())
    .then((hljs) => {
      for (const code of root.querySelectorAll("code[data-language]")) {
        const language = code.dataset.language;
        const raw = code.dataset.raw ?? code.textContent ?? "";
        if (!language || !loadedLanguages.has(language)) continue;
        code.innerHTML = hljs.highlight(raw, { language, ignoreIllegals: true }).value;
        code.classList.add("highlighted");
      }
    })
    .catch((error) => {
      console.warn("Syntax highlighting unavailable", error);
    });
}

function renderCurrent() {
  root.replaceChildren();
  currentVisiblePath = null;

  if (!lastPatch.trim()) {
    root.append(createStatus("No files changed"));
    return;
  }

  files = parsePatch(lastPatch);
  if (files.length === 0) {
    root.append(createStatus("No files changed"));
    return;
  }

  // If a previously reviewed file changed, clear review marker and auto-expand it.
  let reviewedStateDidChange = false;
  const changedReviewedPaths = [];
  for (const file of files) {
    const previousSignature = reviewedFileSignatures[file.path];
    if (!previousSignature) continue;
    const currentSignature = createFileSignature(file);
    if (previousSignature !== currentSignature) {
      delete reviewedFileSignatures[file.path];
      reviewedStateDidChange = true;
      changedReviewedPaths.push(file.path);
    }
  }

  const fragment = document.createDocumentFragment();
  for (const file of files) fragment.append(renderFile(file));
  root.append(fragment);
  for (const path of changedReviewedPaths) {
    const section = Array.from(root.querySelectorAll(".file")).find((node) => (node.dataset.path ?? "") === path);
    if (!section) continue;
    section.classList.remove("collapsed");
    section.querySelector(".file-header")?.setAttribute("aria-expanded", "true");
  }
  applySyntaxHighlighting();
  updateVisibleFile();
  if (reviewedStateDidChange) postReviewedStateChanged();
  post({
    type: "rendered",
    fileCount: files.length,
    reviewedCount: Object.keys(reviewedFileSignatures).length,
  });
}

function applyWrapMode() {
  root.classList.toggle("wrapped", isWrapped);
}

function setAllReviewed(checked) {
  if (checked) {
    const next = {};
    for (const file of files) {
      next[file.path] = createFileSignature(file);
    }
    reviewedFileSignatures = next;
  } else {
    reviewedFileSignatures = {};
  }
  renderCurrent();
  postReviewedStateChanged();
}

function scrollToFile(path) {
  const normalized = normalizePath(path);
  const target = Array.from(root.querySelectorAll(".file")).find((node) => {
    const value = node.dataset.path ?? "";
    return value === normalized || value.endsWith(`/${normalized}`);
  });
  if (!target) return;
  target.classList.remove("collapsed");
  target.querySelector(".file-header")?.setAttribute("aria-expanded", "true");
  target.scrollIntoView({ block: "start" });
  updateVisibleFile();
}

function updateVisibleFile() {
  const target = Array.from(root.querySelectorAll(".file")).find((node) => {
    return node.getBoundingClientRect().bottom > 30;
  });
  const path = target?.dataset.path;
  if (path == null || path === currentVisiblePath) return;
  currentVisiblePath = path;
  post({ type: "scrolledToFile", filePath: path });
}

window.addEventListener("scroll", () => {
  if (scrollFrameRequested) return;
  scrollFrameRequested = true;
  window.requestAnimationFrame(() => {
    scrollFrameRequested = false;
    updateVisibleFile();
  });
}, { passive: true });

window.magentDiffRenderer = {
  setDiff(payload) {
    lastPatch = payload.patch ?? "";
    lastThemeType = payload.themeType ?? "system";
    allowsReviewMarkers = payload.allowsReviewMarkers !== false;
    reviewedFileSignatures = normalizeReviewedState(payload.reviewedFileSignatures);
    document.documentElement.dataset.theme = lastThemeType;
    allCollapsed = false;
    expandedContextByHunk.clear();
    renderCurrent();
  },
  setMessage(message) {
    root.replaceChildren(createStatus(message));
    post({ type: "rendered", fileCount: 0 });
  },
  setTheme(themeType) {
    lastThemeType = themeType ?? "system";
    document.documentElement.dataset.theme = lastThemeType;
  },
  setWrapped(wrapped) {
    isWrapped = Boolean(wrapped);
    applyWrapMode();
  },
  setCollapsed(collapsed) {
    allCollapsed = Boolean(collapsed);
    for (const section of root.querySelectorAll(".file")) {
      section.classList.toggle("collapsed", allCollapsed);
      section.querySelector(".file-header")?.setAttribute("aria-expanded", String(!allCollapsed));
    }
  },
  setAllReviewed,
  showHunkContext,
  scrollToFile
};

window.addEventListener("DOMContentLoaded", () => {
  document.documentElement.dataset.theme = lastThemeType;
  applyWrapMode();
  post({ type: "ready" });
});
