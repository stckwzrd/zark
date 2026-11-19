const vscode = require("vscode")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { LanguageClient } = require("vscode-languageclient/node")

let client = null

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

async function start() {
  const command = vibe()
  client = new LanguageClient(
    "vibe",
    "Vibe",
    { command, args: ["lsp"], options: { cwd: (vscode.workspace.workspaceFolders || [{ uri: { fsPath: os.homedir() } }])[0].uri.fsPath } },
    { documentSelector: [{ scheme: "file", language: "vibe" }] },
  )
  await client.start()
}

async function stop() {
  if (client) {
    const c = client
    client = null
    await c.stop()
  }
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

async function activate(ctx) {
  ctx.subscriptions.push(
    vscode.commands.registerCommand("vibe.run", () => exec("run")),
    vscode.commands.registerCommand("vibe.test", () => exec("test")),
    vscode.commands.registerCommand("vibe.build", () => exec("build")),
    vscode.commands.registerCommand("vibe.restartServer", async () => {
      await stop()
      await start()
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
  await start()
}

async function deactivate() {
  await stop()
}

module.exports = { activate, deactivate }
