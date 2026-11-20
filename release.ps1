# Releases Rogue Poison: test, bump the .toc, commit, tag, push, zip, upload to CurseForge,
# copy into the game. Usage: pwsh -File release.ps1 0.1.2 path\to\changelog.md [-ReleaseType release]
# Beta by default: what the addon does on the poison click is not confirmed in game yet.
param(
  [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
  [Parameter(Mandatory)][string]$Changelog,
  [ValidateSet('alpha', 'beta', 'release')][string]$ReleaseType = 'beta'
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$ProjectId = 1817450
$GameVersion = 17053 # WoW Forever 1.60.1 on CurseForge
$TokenFile = "$HOME\.config\curseforge\api-token"
$AddOns = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\RoguePoison'

function Assert-Ok($what) { if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" } }

$notes = Get-Content -Raw $Changelog
if (git status --porcelain) { throw 'working tree is not clean: commit or stash first' }
if ((git branch --show-current) -ne 'main') { throw 'not on main' }
if (git tag --list "v$Version") { throw "tag v$Version already exists" }

uv run -q tests/test_layout.py; Assert-Ok 'tests'

$toc = Get-Content -Raw RoguePoison.toc
$bumped = $toc -replace '(?m)^## Version: .*$', "## Version: $Version"
if ($bumped -ceq $toc) { throw "RoguePoison.toc already says $Version" }
Set-Content RoguePoison.toc $bumped -NoNewline
git commit -q -am "Release $Version"; Assert-Ok 'commit'
git tag "v$Version"; Assert-Ok 'tag'
git push -q origin main --tags; Assert-Ok 'push'

$zip = Join-Path ([IO.Path]::GetTempPath()) "RoguePoison-$Version.zip"
git archive --format=zip --prefix=RoguePoison/ -o $zip "v$Version"; Assert-Ok 'archive'

$metadata = @{
  changelog     = $notes
  changelogType = 'markdown'
  displayName   = "Rogue Poison $Version"
  gameVersions  = @($GameVersion)
  releaseType   = $ReleaseType
} | ConvertTo-Json -Compress
$headers = @{ 'X-Api-Token' = (Get-Content -Raw $TokenFile).Trim() }
$upload = Invoke-RestMethod -Method Post -Headers $headers `
  -Uri "https://wow.curseforge.com/api/projects/$ProjectId/upload-file" `
  -Form @{ metadata = $metadata; file = Get-Item $zip }
"CurseForge file $($upload.id)"

Copy-Item RoguePoison.lua, RoguePoison.toc $AddOns
Copy-Item Media\icon.tga (Join-Path $AddOns Media)
"v$Version released and copied to $AddOns"
