import json
import os
import sys
import zipfile

here = os.path.dirname(os.path.abspath(__file__))
pkg = json.load(open(os.path.join(here, "package.json")))
name = "%s-%s.vsix" % (pkg["name"], pkg["version"])
files = ["package.json", "extension.js", "language-configuration.json", "syntaxes/vibe.tmLanguage.json", "snippets/vibe.json"]

manifest = """<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="%s" Version="%s" Publisher="%s"/>
    <DisplayName>%s</DisplayName>
    <Description xml:space="preserve">%s</Description>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
""" % (pkg["name"], pkg["version"], pkg["publisher"], pkg["displayName"], pkg["description"])

types = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".js" ContentType="application/javascript"/>
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
