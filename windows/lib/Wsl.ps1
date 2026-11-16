function Test-WslInstanceExists([string]$name) {
  # Without WSL_UTF8=1, `wsl --list` output is UTF-16 with null bytes, which breaks string
  # matching on it.
  $prev = $env:WSL_UTF8
  $env:WSL_UTF8 = "1"
  try {
    $names = (wsl --list --quiet) | ForEach-Object { $_.Trim() }
  } finally {
    if ($null -eq $prev) { Remove-Item Env:\WSL_UTF8 -ErrorAction SilentlyContinue }
    else { $env:WSL_UTF8 = $prev }
  }
  return $names -contains $name
}

function ConvertTo-WslPath([string]$windowsPath) {
  # Maps C:\Program Files\Git\x.exe to /mnt/c/Program\ Files/Git/x.exe, spaces escaped.
  # Precedence: + binds tighter than -replace, so the trailing -replace operators apply to
  # the whole concatenated string.
  return '/mnt/' + $windowsPath[0].ToString().ToLower() + '/' + `
         $windowsPath.Substring(3) -replace '\\', '/' -replace ' ', '\ '
}
