import "./style.css";

const root = document.getElementById("root");

let files = [];
let lastPatch = "";
let lastThemeType = "system";
let allCollapsed = false;
let currentVisiblePath = null;
let scrollFrameRequested = false;
let highlightCorePromise = null;
const languagePromises = new Map();
const loadedLanguages = new Set();

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
  return {
    oldLine: Number(match[1]),
    newLine: Number(match[3]),
    label: line,
    context: match[5]?.trim() ?? "",
  };
}

function parseFileChunk(lines) {
  const firstHeader = parseDiffHeader(lines.find((line) => line.startsWith("diff --git ")) ?? "");
  let oldPath = firstHeader.oldPath;
  let newPath = firstHeader.newPath;
  let status = "modified";
  let additions = 0;
  let deletions = 0;
  let oldLine = 0;
  let newLine = 0;
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
      oldLine = hunk.oldLine;
      newLine = hunk.newLine;
      rows.push({ type: "hunk", text: hunk.label, lineNumber: "" });
      continue;
    }

    if (line.startsWith("+") && !line.startsWith("+++")) {
      rows.push({ type: "add", text: line.slice(1), lineNumber: newLine++ });
      additions += 1;
      continue;
    }

    if (line.startsWith("-") && !line.startsWith("---")) {
      rows.push({ type: "delete", text: line.slice(1), lineNumber: oldLine++ });
      deletions += 1;
      continue;
    }

    if (line.startsWith("\\ No newline at end of file")) {
      rows.push({ type: "notice", text: line, lineNumber: "" });
      continue;
    }

    if (line.startsWith(" ") || rows.length > 0) {
      const text = line.startsWith(" ") ? line.slice(1) : line;
      rows.push({ type: "context", text, lineNumber: newLine++ });
      oldLine += 1;
    }
  }

  const path = newPath || oldPath || "Unknown file";
  return {
    path,
    oldPath,
    newPath,
    status,
    additions,
    deletions,
    language: languageForPath(path),
    metadata,
    rows,
  };
}

function parsePatch(patch) {
  return splitPatch(patch)
    .map(parseFileChunk)
    .filter((file) => file.rows.length > 0 || file.metadata.length > 0);
}

function createStatus(message) {
  return createElement("div", "status", message);
}

function createStat(className, value) {
  const stat = createElement("span", `stat ${className}`, value);
  return stat;
}

function renderFileHeader(file) {
  const header = createElement("button", "file-header");
  header.type = "button";
  header.dataset.path = file.path;
  header.setAttribute("aria-expanded", String(!allCollapsed));

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

  header.append(titleWrap, stats);
  header.addEventListener("click", () => {
    const section = header.closest(".file");
    const collapsed = section.classList.toggle("collapsed");
    header.setAttribute("aria-expanded", String(!collapsed));
  });
  return header;
}

function renderRow(row) {
  const line = createElement("div", `diff-row ${row.type}`);
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

  const fragment = document.createDocumentFragment();
  for (const file of files) fragment.append(renderFile(file));
  root.append(fragment);
  applySyntaxHighlighting();
  updateVisibleFile();
  post({ type: "rendered", fileCount: files.length });
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
    document.documentElement.dataset.theme = lastThemeType;
    allCollapsed = false;
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
  setCollapsed(collapsed) {
    allCollapsed = Boolean(collapsed);
    for (const section of root.querySelectorAll(".file")) {
      section.classList.toggle("collapsed", allCollapsed);
      section.querySelector(".file-header")?.setAttribute("aria-expanded", String(!allCollapsed));
    }
  },
  scrollToFile
};

window.addEventListener("DOMContentLoaded", () => {
  document.documentElement.dataset.theme = lastThemeType;
  post({ type: "ready" });
});
