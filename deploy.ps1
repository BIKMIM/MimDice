# 개발 폴더(D:\Dev\MimDice)의 애드온 파일을 게임 AddOns 폴더로 복사한다.
#   .\deploy.ps1        게임 폴더로 복사 (테스트용)
#   .\deploy.ps1 -Zip   복사 후 커스포지 업로드용 zip도 만든다
#   .\deploy.ps1 -ListOnly   sounds 목록(SoundList.lua)만 다시 만든다
# 매번 sounds 폴더의 mp3/ogg를 읽어 SoundList.lua를 새로 만든다.
# 와우 애드온은 폴더 내용을 읽을 수 없어서, 배포 때 목록을 미리 만들어 넣는다.
param([switch]$Zip, [switch]$ListOnly)

$ErrorActionPreference = "Stop"
$Src = $PSScriptRoot
$Dst = "D:\Games\World of Warcraft\_retail_\Interface\AddOns\MimDice"

# 배포본에 넣지 않을 개발 파일
$ExcludeDirs  = @(".git", ".vscode", ".claude", "tests", "dist")
$ExcludeFiles = @(".gitignore", "AGENTS.md", "CLAUDE.md", "DEVGUIDE.md", "README.md", "deploy.ps1", "*.zip")

# ── 내장 선택창용 sounds 목록 생성 ──
$soundDir = Join-Path $Src "sounds"
$files = @()
if (Test-Path $soundDir) {
    $files = Get-ChildItem -Path $soundDir -File |
        Where-Object { $_.Extension -match '^\.(mp3|ogg)$' } |
        Sort-Object Name | ForEach-Object { $_.Name }
}
$lines = @(
    "-- 자동 생성 파일입니다. 직접 고치지 말고 deploy.ps1을 다시 실행하세요.",
    "-- sounds 폴더에 함께 배포되는 효과음 목록 (내장 선택창에 표시)",
    "MimDiceBundledSoundList = {"
)
foreach ($name in $files) {
    $escaped = $name.Replace("\", "\\").Replace('"', '\"')
    $lines += "    `"$escaped`","
}
$lines += "}"
[IO.File]::WriteAllText((Join-Path $Src "SoundList.lua"), (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "sounds 목록을 만들었습니다: $($files.Count)개"
if ($ListOnly) { return }

# /MIR: 게임 폴더를 배포본과 똑같이 맞춘다 (남는 파일은 지운다)
robocopy $Src $Dst /MIR /R:1 /W:1 /NFL /NDL /NP /NJH /XD $ExcludeDirs /XF $ExcludeFiles | Out-Null
if ($LASTEXITCODE -ge 8) { throw "복사 실패 (robocopy 코드 $LASTEXITCODE)" }
# 제외 목록은 /MIR 삭제에서도 빠지므로, 게임 폴더에 남은 개발 파일은 직접 지운다
foreach ($name in $ExcludeDirs + $ExcludeFiles) {
    Get-ChildItem -Path $Dst -Filter $name -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -Confirm:$false
}
Write-Host "게임 폴더로 복사했습니다: $Dst"

if ($Zip) {
    $ver = (Select-String -Path "$Src\MimDice.toc" -Pattern "^## Version:\s*(.+)$").Matches[0].Groups[1].Value.Trim()
    $out = Join-Path $Src "dist"
    New-Item -ItemType Directory -Force $out | Out-Null
    $zipPath = Join-Path $out "MimDice-v$ver.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Confirm:$false }
    # zip 안에 MimDice 폴더가 들어가야 커스포지가 올바르게 설치한다
    # Compress-Archive(PS 5.1)는 경로에 \ 를 써서 다른 압축 도구에서 깨지므로 직접 / 로 만든다
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zipPath, "Create")
    try {
        Get-ChildItem -Path $Dst -Recurse -File -Force | ForEach-Object {
            $rel = "MimDice/" + $_.FullName.Substring($Dst.Length + 1).Replace("\", "/")
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $rel) | Out-Null
        }
    } finally { $archive.Dispose() }
    Write-Host "업로드용 zip을 만들었습니다: $zipPath"
}
