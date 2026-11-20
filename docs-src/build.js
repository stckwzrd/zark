const fs = require("fs")
const path = require("path")
const cp = require("child_process")
const crypto = require("crypto")
const { marked } = require("marked")
const { createHighlighter } = require("shiki")

const ROOT = path.resolve(__dirname, "..")
const VIBE = process.env.VIBE || path.join(ROOT, "build", "vibe")
const OUT = process.env.DOCS_OUT || path.join(ROOT, "docs")
const PAGES = path.join(__dirname, "pages")
const TMP = path.join(__dirname, ".tmp-" + process.pid)
const CACHE_FILE = process.env.DOCS_CACHE || path.join(__dirname, ".cache.json")
const ONLY = process.env.DOCS_PAGES ? process.env.DOCS_PAGES.split(",") : null
const cache = fs.existsSync(CACHE_FILE) ? JSON.parse(fs.readFileSync(CACHE_FILE, "utf8")) : {}
const SITE = "Vibe"
const LANGS = [
  { code: "en", pages: "pages", dir: "", up: "", other: "ru", switchTo: "Русский", ui: { out: "Output", errOut: "Compiler output", testOut: "Test output", exit: "exit code", toc: "On this page", prev: "Previous", next: "Next", desc: "A guide to the Vibe programming language", search: "Search the guide (/)", nothing: "Nothing found", copy: "Copy", copied: "Copied", menu: "Menu", theme: "Toggle theme" } },
  { code: "ru", pages: "pages-ru", dir: "ru", up: "../", other: "en", switchTo: "English", ui: { out: "Вывод", errOut: "Вывод компилятора", testOut: "Вывод тестов", exit: "код выхода", toc: "На этой странице", prev: "Назад", next: "Дальше", desc: "Руководство по языку программирования Vibe", search: "Поиск по руководству (/)", nothing: "Ничего не найдено", copy: "Копировать", copied: "Скопировано", menu: "Меню", theme: "Сменить тему" } },
]
const failures = []

function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function slug(s) {
  return s.toLowerCase().replace(/<[^>]+>/g, "").replace(/&[a-z]+;/g, "").replace(/[^a-z0-9а-я]+/g, "-").replace(/^-+|-+$/g, "")
}

function frontMatter(text) {
  const m = /^---\n([\s\S]*?)\n---\n/.exec(text)
  const meta = {}
  if (!m) return { meta, body: text }
  for (const line of m[1].split("\n")) {
    const k = line.indexOf(":")
    if (k > 0) meta[line.slice(0, k).trim()] = line.slice(k + 1).trim().replace(/^"(.*)"$/, "$1")
  }
  return { meta, body: text.slice(m[0].length) }
}

function parseInfo(info) {
  const parts = (info || "").trim().split(/\s+/).filter(Boolean)
  const lang = parts.shift() || ""
  const flags = new Set()
  const opts = {}
  for (const p of parts) {
    const k = p.indexOf("=")
    if (k > 0) opts[p.slice(0, k)] = p.slice(k + 1)
    else flags.add(p)
  }
  return { lang, flags, opts }
}

function runVibe(page, line, code, mode, extra, withArgs) {
  const key = crypto.createHash("sha1").update(VIBE_STAMP + mode + "\0" + code + "\0" + JSON.stringify(extra) + withArgs.join(" ")).digest("hex")
  if (cache[key]) {
    if (mode === "error" && cache[key].code === 0) failures.push(`${page}:${line}: example marked 'error' compiled and ran`)
    return cache[key]
  }
  const dir = path.join(TMP, key.slice(0, 12))
  fs.rmSync(dir, { recursive: true, force: true })
  fs.mkdirSync(dir, { recursive: true })
  fs.writeFileSync(path.join(dir, "main.vibe"), code)
  for (const [name, text] of Object.entries(extra)) {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true })
    fs.writeFileSync(path.join(dir, name), text)
  }
  const verb = mode === "test" ? "test" : "run"
  const args = [verb, "main.vibe", ...withArgs]
  const r = cp.spawnSync(VIBE, args, { cwd: dir, encoding: "utf8", timeout: 60000 })
  let out = (r.stdout || "") + (r.stderr || "")
  out = out.split(dir + "/").join("").split(dir).join(".").replace(/\n+$/, "")
  const res = { out, code: r.status === null ? -1 : r.status }
  if (mode === "error" && res.code === 0) failures.push(`${page}:${line}: example marked 'error' compiled and ran`)
  cache[key] = res
  return res
}

let VIBE_STAMP = ""

async function main() {
  VIBE_STAMP = String(fs.statSync(VIBE).mtimeMs)
  const grammar = JSON.parse(fs.readFileSync(path.join(ROOT, "editors", "vscode", "syntaxes", "vibe.tmLanguage.json"), "utf8"))
  const hl = await createHighlighter({
    themes: ["github-light", "github-dark"],
    langs: [{ ...grammar, name: "vibe" }, "sh", "c", "cpp", "json", "text", "zig", "rust", "go", "python", "javascript"],
  })

  fs.rmSync(OUT, { recursive: true, force: true })
  fs.mkdirSync(path.join(OUT, "assets"), { recursive: true })
  fs.copyFileSync(path.join(__dirname, "style.css"), path.join(OUT, "assets", "style.css"))
  fs.copyFileSync(path.join(__dirname, "site.js"), path.join(OUT, "assets", "site.js"))
  fs.writeFileSync(path.join(OUT, ".nojekyll"), "")
  fs.mkdirSync(TMP, { recursive: true })
  for (const L of LANGS) {
    if (fs.existsSync(path.join(__dirname, L.pages))) await buildSite(hl, L)
  }
  fs.writeFileSync(CACHE_FILE, JSON.stringify(cache))
  fs.rmSync(TMP, { recursive: true, force: true })
  if (failures.length) {
    console.log("PROBLEMS:")
    for (const f of failures) console.log("  " + f)
    process.exitCode = 1
  }
}

async function buildSite(hl, L) {
  const PAGES = path.join(__dirname, L.pages)
  const OUTD = path.join(OUT, L.dir)
  const U = L.ui
  const pages = []
  for (const f of fs.readdirSync(PAGES).filter((n) => n.endsWith(".md")).sort()) {
    const { meta, body } = frontMatter(fs.readFileSync(path.join(PAGES, f), "utf8"))
    pages.push({ file: f, name: f.replace(/\.md$/, ""), meta, body, order: parseFloat(meta.order || "999"), section: meta.section || "" })
  }
  pages.sort((a, b) => a.order - b.order)

  fs.mkdirSync(OUTD, { recursive: true })
  const index = []
  for (const p of pages) {
    const headings = []
    let extraFiles = {}
    let blockNo = 0
    const renderer = new marked.Renderer()
    renderer.heading = (text, level, raw) => {
      const id = slug(raw)
      if (level >= 2 && level <= 3) headings.push({ level, text: text.replace(/<[^>]+>/g, ""), id })
      return `<h${level} id="${id}"><a class="anchor" href="#${id}">#</a>${text}</h${level}>\n`
    }
    renderer.link = (href, title, text) => {
      let h = href
      if (!/^[a-z]+:/.test(h) && !h.startsWith("#")) h = h.replace(/\.md(#|$)/, ".html$1")
      const ext = /^https?:/.test(h) ? ' target="_blank" rel="noopener"' : ""
      return `<a href="${esc(h)}"${title ? ` title="${esc(title)}"` : ""}${ext}>${text}</a>`
    }
    renderer.blockquote = (quote) => {
      const m = /^<p><strong>(Примечание|Важно|Совет|Ловушка|Почему так|Note|Warning|Tip|Gotcha|Why)[:.]?<\/strong>/i.exec(quote)
      const kinds = { "примечание": "note", "важно": "warning", "совет": "tip", "ловушка": "gotcha", "почему так": "why" }
      const kind = m ? kinds[m[1].toLowerCase()] || m[1].toLowerCase() : "plain"
      return `<blockquote class="callout ${kind}">${quote}</blockquote>\n`
    }
    renderer.table = (header, body) => `<div class="table-wrap"><table><thead>${header}</thead><tbody>${body}</tbody></table></div>\n`
    renderer.code = (code, infostring) => {
      blockNo++
      const { lang, flags, opts } = parseInfo(infostring)
      const lineNo = "block " + blockNo
      if (lang === "vibe" || lang === "c" || lang === "cpp") {
        if (opts.file) {
          extraFiles[opts.file] = code
          return codeHtml(hl, code, lang, opts.file)
        }
      }
      if (lang === "vibe" && (flags.has("run") || flags.has("error") || flags.has("test"))) {
        let src = code
        if (flags.has("fragment")) src = "void main() { " + code.replace(/\n$/, "") + "\n}\n"
        const mode = flags.has("error") ? "error" : flags.has("test") ? "test" : "run"
        const withArgs = opts.with ? opts.with.split(",") : []
        const res = runVibe(p.name, lineNo, src, mode, extraFiles, withArgs.filter((x) => x !== "allow-fail"))
        extraFiles = {}
        const label = mode === "error" ? U.errOut : mode === "test" ? U.testOut : U.out
        let tail = ""
        if (res.code !== 0 && mode !== "error" && mode !== "test") tail = `<span class="exit">${U.exit} ${res.code}</span>`
        if (mode === "run" && res.code !== 0 && !flags.has("exit") && !flags.has("panic")) failures.push(`${p.name} ${lineNo}: exit ${res.code}: ${res.out.split("\n")[0]}`)
        if (mode === "test" && res.code !== 0 && !flags.has("fails")) failures.push(`${p.name} ${lineNo}: tests failed`)
        return `<div class="example">${codeHtml(hl, code, "vibe", opts.title || "")}<div class="out ${mode}"><div class="out-head"><span>${label}</span>${tail}</div><pre><code>${esc(res.out)}</code></pre></div></div>\n`
      }
      return codeHtml(hl, code, lang, opts.title || "")
    }
    marked.use({ renderer, gfm: true, breaks: false })
    const html = ONLY && !ONLY.includes(p.name) ? "" : marked.parse(p.body)
    p.html = html
    p.headings = headings
    p.title = p.meta.title || p.name
    const text = html.replace(/<pre[\s\S]*?<\/pre>/g, " ").replace(/<[^>]+>/g, " ").replace(/&[a-z]+;/g, " ").replace(/\s+/g, " ")
    index.push({ title: p.title, url: p.name + ".html", headings: headings.map((h) => ({ text: h.text, id: h.id })), text: text.slice(0, 6000) })
  }

  const sections = []
  for (const p of pages) {
    if (p.name === "index") continue
    let s = sections.find((x) => x.name === p.section)
    if (!s) {
      s = { name: p.section, pages: [] }
      sections.push(s)
    }
    s.pages.push(p)
  }
  const nav = (cur) =>
    `<nav class="side"><a class="brand" href="index.html">${SITE}</a>` +
    sections.map((s) => `<div class="group"><div class="group-title">${esc(s.name)}</div>` + s.pages.map((q) => `<a href="${q.name}.html"${q.name === cur ? ' class="current"' : ""}>${esc(q.title)}</a>`).join("") + "</div>").join("") +
    `</nav>`
  const flat = pages.filter((p) => p.name !== "index")
  for (const p of pages) {
    const i = flat.indexOf(p)
    const prev = i > 0 ? flat[i - 1] : p.name !== "index" ? pages[0] : null
    const next = i >= 0 && i + 1 < flat.length ? flat[i + 1] : p.name === "index" ? flat[0] : null
    const toc = p.headings.length ? `<aside class="toc"><div class="toc-title">${U.toc}</div>` + p.headings.map((h) => `<a class="l${h.level}" href="#${h.id}">${esc(h.text)}</a>`).join("") + `</aside>` : ""
    const pager = `<div class="pager">${prev ? `<a class="prev" href="${prev.name}.html"><small>${U.prev}</small>${esc(prev.title)}</a>` : "<span></span>"}${next ? `<a class="next" href="${next.name}.html"><small>${U.next}</small>${esc(next.title)}</a>` : "<span></span>"}</div>`
    const page = `<!doctype html>
<html lang="${L.code}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(p.title)} · ${SITE}</title>
<meta name="description" content="${esc(p.meta.description || U.desc)}">
<link rel="stylesheet" href="${L.up}assets/style.css">
</head>
<body class="${p.name === "index" ? "home" : ""}">
<header class="top"><button class="menu" aria-label="${U.menu}">☰</button><a class="logo" href="index.html">${SITE}</a><div class="search"><input id="q" type="search" placeholder="${U.search}" autocomplete="off"><div id="results"></div></div><a class="lang" href="${L.other === "ru" ? "ru/" : "../"}${p.name}.html">${L.switchTo}</a><button id="theme" aria-label="${U.theme}">◐</button></header>
<div class="layout">
${nav(p.name)}
<main><article>
${p.name === "index" ? "" : `<h1>${esc(p.title)}</h1>`}
${p.html}
${pager}
</article>${toc}</main>
</div>
<script src="${L.up}assets/site.js"></script>
</body>
</html>
`
    fs.writeFileSync(path.join(OUTD, p.name + ".html"), page)
  }
  fs.writeFileSync(path.join(OUTD, "search-index.json"), JSON.stringify(index))
  console.log(`built ${pages.length} pages (${L.code})`)
}

function codeHtml(hl, code, lang, title) {
  const known = ["vibe", "sh", "c", "cpp", "json", "text", "zig", "rust", "go", "python", "javascript"]
  const l = known.includes(lang) ? lang : "text"
  const body = hl.codeToHtml(code.replace(/\n$/, ""), { lang: l, themes: { light: "github-light", dark: "github-dark" }, defaultColor: false })
  return `<div class="code">${title ? `<div class="code-title">${esc(title)}</div>` : ""}${body}</div>`
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
