const vscode = require("vscode")
const cp = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

function vibe() {
  const set = vscode.workspace.getConfiguration("vibe").get("path") || "vibe"
  if (set !== "vibe") return set
  const dirs = (process.env.PATH || "").split(path.delimiter).concat([path.join(os.homedir(), ".local", "bin")])
  const hit = dirs.map((d) => path.join(d, "vibe")).find((f) => fs.existsSync(f))
  return hit || set
}

function quote(s) {
  return "'" + s.replace(/'/g, "'\\''") + "'"
}

function parseErrors(stderr, cwd, root) {
  const found = new Map()
  const lines = stderr.split("\n")
  for (let i = 0; i < lines.length; i++) {
    const m = /^(.*?):(\d+): error: (.*)$/.exec(lines[i])
    if (!m || m[1].startsWith("<")) continue
    const file = path.resolve(cwd, m[1])
    const line = Math.max(parseInt(m[2], 10) - 1, 0)
    let col = 0
    let len = 1
    const code = /^\s*\d+ \| (.*)$/.exec(lines[i + 1] || "")
    const caret = /^ {6}\| (.*)\^\s*$/.exec(lines[i + 2] || "")
    if (code && caret) {
      col = caret[1].length
      const word = /^[A-Za-z0-9_.]+/.exec(code[1].slice(col))
      len = word ? word[0].length : 1
    }
    const d = new vscode.Diagnostic(new vscode.Range(line, col, line, col + len), m[3], vscode.DiagnosticSeverity.Error)
    d.source = "vibe"
    if (!found.has(file)) found.set(file, [])
    found.get(file).push(d)
  }
  if (found.size === 0 && /error:/.test(stderr)) {
    const msg = stderr.split("\n").find((l) => l.includes("error:")) || stderr
    found.set(root, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), msg, vscode.DiagnosticSeverity.Error)])
  }
  return found
}

function activate(ctx) {
  const diags = vscode.languages.createDiagnosticCollection("vibe")
  const owned = new Map()
  ctx.subscriptions.push(diags)

  function check(doc) {
    if (doc.languageId !== "vibe" || doc.isUntitled || doc.uri.scheme !== "file") return
    if (!vscode.workspace.getConfiguration("vibe").get("checkOnSave")) return
    const file = doc.uri.fsPath
    const cwd = path.dirname(file)
    cp.execFile(vibe(), ["ir", file], { cwd, maxBuffer: 1 << 28, timeout: 30000 }, (err, stdout, stderr) => {
      for (const old of owned.get(file) || []) diags.delete(vscode.Uri.file(old))
      const found = err ? parseErrors(stderr || String(err.message), cwd, file) : new Map()
      owned.set(file, [...found.keys()])
      for (const [f, list] of found) diags.set(vscode.Uri.file(f), list)
    })
  }

  function terminal() {
    return vscode.window.terminals.find((t) => t.name === "Vibe") || vscode.window.createTerminal("Vibe")
  }

  async function exec(verb) {
    const ed = vscode.window.activeTextEditor
    if (!ed || ed.document.languageId !== "vibe") return
    await ed.document.save()
    const file = ed.document.uri.fsPath
    const t = terminal()
    t.show(true)
    t.sendText(`cd ${quote(path.dirname(file))} && ${quote(vibe())} ${verb} ${quote(file)}`)
  }

  ctx.subscriptions.push(
    vscode.commands.registerCommand("vibe.run", () => exec("run")),
    vscode.commands.registerCommand("vibe.test", () => exec("test")),
    vscode.commands.registerCommand("vibe.build", () => exec("build")),
    vscode.commands.registerCommand("vibe.check", () => {
      const ed = vscode.window.activeTextEditor
      if (ed) check(ed.document)
    }),
    vscode.workspace.onDidOpenTextDocument(check),
    vscode.workspace.onDidSaveTextDocument(check),
    vscode.window.onDidChangeActiveTextEditor((e) => e && check(e.document)),
  )
  vscode.workspace.textDocuments.forEach(check)

  ctx.subscriptions.push(
    vscode.languages.registerDocumentFormattingEditProvider("vibe", {
      provideDocumentFormattingEdits(doc) {
        return new Promise((resolve) => {
          const tmp = path.join(os.tmpdir(), `vibe-fmt-${process.pid}-${Date.now()}.vibe`)
          fs.writeFileSync(tmp, doc.getText())
          cp.execFile(vibe(), ["fmt", tmp], { timeout: 15000 }, (err) => {
            let edits = []
            if (!err) {
              const out = fs.readFileSync(tmp, "utf8")
              const last = doc.lineAt(doc.lineCount - 1)
              edits = [vscode.TextEdit.replace(new vscode.Range(0, 0, last.lineNumber, last.text.length), out)]
            }
            fs.unlinkSync(tmp)
            resolve(edits)
          })
        })
      },
    }),
  )

  const declRe = /^(\s*)(?:(?:export|extern)\s+)?(fn|struct|union|enum|impl|type|const|var)\s+([A-Za-z_][A-Za-z0-9_]*)/
  const kinds = {
    fn: vscode.SymbolKind.Function,
    struct: vscode.SymbolKind.Struct,
    union: vscode.SymbolKind.Struct,
    enum: vscode.SymbolKind.Enum,
    impl: vscode.SymbolKind.Class,
    type: vscode.SymbolKind.TypeParameter,
    const: vscode.SymbolKind.Constant,
    var: vscode.SymbolKind.Variable,
  }
  ctx.subscriptions.push(
    vscode.languages.registerDocumentSymbolProvider("vibe", {
      provideDocumentSymbols(doc) {
        const out = []
        for (let i = 0; i < doc.lineCount; i++) {
          const text = doc.lineAt(i).text
          const t = /^test\s+"([^"]*)"/.exec(text)
          if (t) {
            out.push(new vscode.SymbolInformation("test " + t[1], vscode.SymbolKind.Event, "", new vscode.Location(doc.uri, new vscode.Position(i, 0))))
            continue
          }
          const m = declRe.exec(text)
          if (!m) continue
          let kind = kinds[m[2]]
          if (m[2] === "fn" && m[1].length > 0) kind = vscode.SymbolKind.Method
          out.push(new vscode.SymbolInformation(m[3], kind, "", new vscode.Location(doc.uri, new vscode.Position(i, m[1].length))))
        }
        return out
      },
    }),
    vscode.languages.registerDefinitionProvider("vibe", {
      async provideDefinition(doc, pos) {
        const range = doc.getWordRangeAtPosition(pos, /[A-Za-z_][A-Za-z0-9_]*/)
        if (!range) return []
        const word = doc.getText(range)
        const re = new RegExp(`^\\s*(?:(?:export|extern)\\s+)?(?:fn|struct|union|enum|type|const|var)\\s+${word}\\b`)
        const files = await vscode.workspace.findFiles("**/*.vibe", "**/{.vibe-cache,node_modules}/**", 500)
        const out = []
        for (const f of files) {
          const text = f.fsPath === doc.uri.fsPath ? doc.getText() : fs.readFileSync(f.fsPath, "utf8")
          text.split("\n").forEach((line, i) => {
            if (re.test(line)) out.push(new vscode.Location(f, new vscode.Position(i, line.indexOf(word))))
          })
        }
        return out
      },
    }),
    vscode.languages.registerCodeLensProvider("vibe", {
      provideCodeLenses(doc) {
        const lenses = []
        for (let i = 0; i < doc.lineCount; i++) {
          const text = doc.lineAt(i).text
          const r = new vscode.Range(i, 0, i, 0)
          if (/^fn\s+main\b/.test(text)) lenses.push(new vscode.CodeLens(r, { title: "$(play) Run", command: "vibe.run" }))
          if (/^test\s+"/.test(text)) lenses.push(new vscode.CodeLens(r, { title: "$(beaker) Run tests", command: "vibe.test" }))
        }
        return lenses
      },
    }),
  )
}

function deactivate() {}

module.exports = { activate, deactivate }
