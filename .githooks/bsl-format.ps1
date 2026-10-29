# Автоформат BSL-модулей перед коммитом.
# Исправляет: хвостовые пробелы/табы в конце строк, переводы строк (LF), UTF-8 BOM.
# Проверяет (-Check): хвостовые пробелы и отступы пробелами вместо табов.

param(
    [switch]$Check   # только проверка, без правок
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# Файлы: staged .bsl; если нет — все .bsl в Documents
$staged = @(& git -C $repoRoot diff --cached --name-only --diff-filter=ACM 2>$null |
    Where-Object { $_ -match '\.bsl$' })

if ($staged.Count -gt 0) {
    $files = @($staged | ForEach-Object { Join-Path $repoRoot $_ })
} else {
    $files = @(Get-ChildItem -Path (Join-Path $repoRoot 'Documents') -Recurse -Filter '*.bsl' -File |
        ForEach-Object { $_.FullName })
}

$fixedCount = 0
$warnCount = 0

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $rel = $f.Substring($repoRoot.Length + 1)

    $bytes = [System.IO.File]::ReadAllBytes($f)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $start = if ($hasBom) { 3 } else { 0 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $start, $bytes.Length - $start)

    # Хвостовые пробелы/табы в конце строк
    $noTrailing = [regex]::Replace($text, '(?m)[ \t]+(?=\r?$)', '')
    $hasTrailing = ($noTrailing -ne $text)

    # Отступы пробелами вместо табов (первая такая строка)
    $hasSpaceIndent = [bool]($noTrailing -split "`n" | Where-Object { $_ -match '^ +' } | Select-Object -First 1)

    if ($Check) {
        if ($hasTrailing) { Write-Output "[STYLE] $rel : хвостовые пробелы"; $warnCount++ }
        if ($hasSpaceIndent) { Write-Output "[STYLE] $rel : отступы пробелами"; $warnCount++ }
        continue
    }

    # Автоформат: хвостовые пробелы + LF + BOM
    $newText = $noTrailing -replace "`r`n", "`n" -replace "`r", "`n"
    if (($newText -ne $text) -or (-not $hasBom)) {
        $outBytes = [System.Text.Encoding]::UTF8.GetBytes($newText)
        $out = New-Object byte[] (3 + $outBytes.Length)
        $out[0] = 0xEF; $out[1] = 0xBB; $out[2] = 0xBF
        [Array]::Copy($outBytes, 0, $out, 3, $outBytes.Length)
        [System.IO.File]::WriteAllBytes($f, $out)
        Write-Output "[FIX] $rel"
        $fixedCount++
    }
}

Write-Output "[bsl-format] модулей: $($files.Count), исправлено: $fixedCount, предупреждений: $warnCount"
exit 0
