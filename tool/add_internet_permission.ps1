$path = Join-Path $PSScriptRoot '..\android\app\src\main\AndroidManifest.xml'
if (-not (Test-Path $path)) {
  Write-Error "AndroidManifest.xml not found: $path"
  exit 1
}
$content = [IO.File]::ReadAllText($path)
# App name shown on the launcher
$content = [regex]::Replace($content, 'android:label="[^"]*"', 'android:label="Keenon 관제"')
[IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
if ($content -match 'android\.permission\.INTERNET') {
  Write-Host 'INTERNET permission already present.'
  exit 0
}
$perm = '<uses-permission android:name="android.permission.INTERNET"/>'
$idx = $content.IndexOf('<application')
if ($idx -lt 0) {
  Write-Error '<application> tag not found.'
  exit 1
}
$content = $content.Insert($idx, $perm + [Environment]::NewLine + '    ')
[IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'INTERNET permission added.'
