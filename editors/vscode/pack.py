import json
import os
import sys
import zipfile

here = os.path.dirname(os.path.abspath(__file__))
pkg = json.load(open(os.path.join(here, "package.json")))
name = "%s-%s.vsix" % (pkg["name"], pkg["version"])
files = ["package.json", "extension.js", "language-configuration.json", "README.md", "syntaxes/zark.tmLanguage.json", "snippets/zark.json"]
for root, dirs, names in os.walk(os.path.join(here, "node_modules")):
    dirs[:] = [d for d in dirs if d not in (".bin", "test", "tests", "docs")]
    for n in names:
        if n.endswith((".md", ".map", ".ts", ".txt")) and not n.endswith(".d.ts") and n not in ("LICENSE.txt",):
            continue
        if n.endswith((".d.ts", ".map")):
            continue
        files.append(os.path.relpath(os.path.join(root, n), here))

manifest = """<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="%s" Version="%s" Publisher="%s"/>
    <DisplayName>%s</DisplayName>
    <Description xml:space="preserve">%s</Description>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Properties>
    <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.82.0"/>
    <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="workspace"/>
  </Properties>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
""" % (pkg["name"], pkg["version"], pkg["publisher"], pkg["displayName"], pkg["description"])

types = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".js" ContentType="application/javascript"/>
  <Default Extension=".txt" ContentType="text/plain"/>
  <Default Extension=".md" ContentType="text/markdown"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
"""

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, name)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", types)
    z.writestr("extension.vsixmanifest", manifest)
    for f in files:
        z.write(os.path.join(here, f), "extension/" + f)
print(out)
