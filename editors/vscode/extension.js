const vscode = require("vscode")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { LanguageClient } = require("vscode-languageclient/node")

let client = null
let output = null
let status = null

function setting(key, fallback) {
  return vscode.workspace.getConfiguration("zark").get(key, fallback)
}

function expandHome(p) {
  if (p === "~") return os.homedir()
  if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2))
  return p
}

function absoluteCompiler(p) {
  let v = expandHome(p)
  if (!path.isAbsolute(v)) {
    const root = (vscode.workspace.workspaceFolders || [])[0]
    if (root) v = path.join(root.uri.fsPath, v)
  }
  return v
}

function executable(p) {
  try {
    fs.accessSync(p, fs.constants.X_OK)
    return !fs.statSync(p).isDirectory()
  } catch {
    return false
  }
}

/// Every place a compiler can come from, in priority order. The configured
/// path wins; after that the workspace's own build/ (the common case when the
/// user develops Zark itself), PATH and the usual install locations.
function compilerCandidates() {
  const configured = setting("path", "zark")
  if (configured && configured !== "zark") return [absoluteCompiler(configured)]
  const names = process.platform === "win32" ? ["zark.exe", "zark"] : ["zark"]
  const out = []
  for (const folder of vscode.workspace.workspaceFolders || []) {
    for (const n of names) {
      out.push(path.join(folder.uri.fsPath, "build", n))
      out.push(path.join(folder.uri.fsPath, n))
    }
  }
  for (const dir of (process.env.PATH || "").split(path.delimiter)) {
    if (!dir) continue
    for (const n of names) out.push(path.join(dir, n))
  }
  for (const n of names) {
    out.push(path.join(os.homedir(), ".local", "bin", n))
    out.push(path.join("/usr/local/bin", n))
    out.push(path.join("/usr/bin", n))
  }
  return out
}

function findCompiler() {
  return compilerCandidates().find(executable) || null
}

function serverCwd() {
  const ed = vscode.window.activeTextEditor
  if (ed) {
    const folder = vscode.workspace.getWorkspaceFolder(ed.document.uri)
    if (folder) return folder.uri.fsPath
    if (ed.document.uri.scheme === "file") return path.dirname(ed.document.uri.fsPath)
  }
  const folder = (vscode.workspace.workspaceFolders || [])[0]
  return folder ? folder.uri.fsPath : os.homedir()
}

function setStatus(text, tooltip) {
  if (!status) return
  status.text = text
  status.tooltip = tooltip
  status.show()
}

function missingCompiler() {
  setStatus("$(warning) Zark", "Zark compiler not found. Set zark.path or build build/zark.")
  if (output) {
    output.appendLine("Zark: compiler not found. Tried:")
    for (const p of compilerCandidates().slice(0, 20)) output.appendLine("  " + p)
  }
  vscode.window
    .showErrorMessage(
      "Zark compiler not found. Build it with ./bootstrap.sh, put it on PATH, or set zark.path.",
      "Open Settings",
      "Show Output",
    )
    .then((pick) => {
      if (pick === "Open Settings") vscode.commands.executeCommand("workbench.action.openSettings", "zark.path")
      if (pick === "Show Output") output.show(true)
    })
}

async function start() {
  if (client) return true
  const command = findCompiler()
  if (!command) {
    missingCompiler()
    return false
  }
  if (output) output.appendLine(`Zark: ${command} lsp (cwd ${serverCwd()})`)
  setStatus("$(sync~spin) Zark", `Starting ${command} lsp`)
  const c = new LanguageClient(
    "zark",
    "Zark",
    { command, args: ["lsp"], options: { cwd: serverCwd() } },
    {
      documentSelector: [
        { scheme: "file", language: "zark" },
        { scheme: "untitled", language: "zark" },
      ],
      outputChannel: output,
      traceOutputChannel: output,
    },
  )
  try {
    await c.start()
    client = c
    setStatus("$(zap) Zark", `Zark language server: ${command}`)
    if (output) output.appendLine("Zark: language server started")
    return true
  } catch (e) {
    try { await c.stop() } catch {}
    setStatus("$(warning) Zark", "Zark language server failed to start")
    if (output) output.appendLine("Zark: start failed: " + (e && e.stack ? e.stack : e))
    vscode.window.showErrorMessage("Zark language server failed to start. See the output for details.", "Show Output").then((pick) => {
      if (pick === "Show Output") output.show(true)
    })
    return false
  }
}

async function stop() {
  preludeCache.clear()
  if (!client) return
  const c = client
  client = null
  try {
    await c.stop()
  } catch {}
}

const preludeCache = new Map()

async function providePrelude(uri) {
  const key = uri.toString()
  if (preludeCache.has(key)) return preludeCache.get(key)
  if (!client) throw new Error("the Zark language server is not running")
  const p = uri.path || ""
  const path = p === "/std.zk" || p === "" ? "<std>" : "<std>" + p
  const text = await client.sendRequest("zark/std", { path })
  preludeCache.set(key, text)
  return text
}

function quote(s) {
  if (process.platform === "win32") return '"' + s.replace(/"/g, '\\"') + '"'
  return "'" + s.replace(/'/g, "'\\''") + "'"
}

function terminal() {
  return vscode.window.terminals.find((t) => t.name === "Zark") || vscode.window.createTerminal("Zark")
}

async function activeZark() {
  const ed = vscode.window.activeTextEditor
  if (!ed || ed.document.languageId !== "zark") {
    vscode.window.showWarningMessage("Open a Zark file first.")
    return null
  }
  if (ed.document.isUntitled) {
    vscode.window.showWarningMessage("Save the file first: the compiler needs a path.")
    return null
  }
  await ed.document.save()
  return ed
}

async function run(verb) {
  const ed = await activeZark()
  if (!ed) return
  const compiler = findCompiler()
  if (!compiler) {
    missingCompiler()
    return
  }
  const file = ed.document.uri.fsPath
  let args = " " + quote(file)
  if (verb === "build") {
    const out = file.endsWith(".zk") ? file.slice(0, -3) : file + ".out"
    args = " " + quote(file) + " -o " + quote(out)
  }
  const cd = process.platform === "win32" ? "cd /d " : "cd "
  const t = terminal()
  t.show(true)
  t.sendText(cd + quote(path.dirname(file)) + " && " + quote(compiler) + " " + verb + args, true)
}

async function format() {
  const ed = vscode.window.activeTextEditor
  if (!ed || ed.document.languageId !== "zark") {
    vscode.window.showWarningMessage("Open a Zark file first.")
    return
  }
  try {
    await vscode.commands.executeCommand("editor.action.formatDocument")
  } catch (e) {
    vscode.window.showWarningMessage("Zark format failed: " + (e && e.message ? e.message : e))
  }
}

function provideCodeLenses(doc) {
  const lenses = []
  let hasMain = false
  for (let i = 0; i < doc.lineCount; i++) {
    const text = doc.lineAt(i).text
    const range = new vscode.Range(i, 0, i, 0)
    if (/^\s*test\s+"/.test(text)) {
      lenses.push(new vscode.CodeLens(range, { title: "$(beaker) Run tests", command: "zark.test" }))
    }
    // `void main()`, `!void main()`, `i64 main()`
    if (/^\s*(?!(?:if|else|while|for|return|break|continue|match|defer|errdefer|catch|await)\b)(?:async\s+)?!?[A-Za-z_][A-Za-z0-9_.\[\]<>:, *]*\s+main\s*\(/.test(text)) {
      hasMain = true
      lenses.push(new vscode.CodeLens(range, { title: "$(play) Run", command: "zark.run" }))
    }
  }
  if (hasMain) {
    lenses.push(new vscode.CodeLens(new vscode.Range(0, 0, 0, 0), { title: "$(gear) Build", command: "zark.build" }))
  }
  return lenses
}

async function activate(ctx) {
  output = vscode.window.createOutputChannel("Zark")
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 10)
  setStatus("$(zap) Zark", "Zark language support")
  ctx.subscriptions.push(output, status)

  const register = (name, fn) => ctx.subscriptions.push(vscode.commands.registerCommand(name, fn))
  register("zark.run", () => run("run"))
  register("zark.test", () => run("test"))
  register("zark.build", () => run("build"))
  register("zark.format", format)
  register("zark.showOutput", () => output.show(true))
  register("zark.restartServer", async () => {
    await stop()
    if (await start()) vscode.window.showInformationMessage("Zark language server restarted.")
  })

  ctx.subscriptions.push(
    vscode.languages.registerCodeLensProvider({ language: "zark" }, { provideCodeLenses }),
    vscode.workspace.registerTextDocumentContentProvider("zark-std", { provideTextDocumentContent: providePrelude }),
    vscode.workspace.onDidOpenTextDocument(async (doc) => {
      if (doc.uri.scheme === "zark-std" && doc.languageId !== "zark") {
        try { await vscode.languages.setTextDocumentLanguage(doc, "zark") } catch {}
      }
    }),
    vscode.workspace.onDidChangeConfiguration(async (e) => {
      if (e.affectsConfiguration("zark.path")) {
        await stop()
        await start()
      }
    }),
  )

  await start()
}

async function deactivate() {
  await stop()
}

module.exports = { activate, deactivate }
