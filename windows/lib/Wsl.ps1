function Test-WslInstanceExists([string]$name) {
  # WSL_UTF8=1 makes `wsl --list` emit clean UTF-8 (avoids the UTF-16/null-byte mangling
  # that otherwise breaks string matching on the output).
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
  # Map a Windows path (e.g. C:\Program Files\Git\x.exe) to its WSL /mnt form
  # (/mnt/c/Program\ Files/Git/x.exe): lowercase the drive letter, drop "C:\",
  # flip backslashes to slashes, and escape spaces.
  # Precedence note: + binds tighter than -replace, so the trailing -replace
  # operators apply to the whole concatenated string.
  return '/mnt/' + $windowsPath[0].ToString().ToLower() + '/' + `
         $windowsPath.Substring(3) -replace '\\', '/' -replace ' ', '\ '
}
