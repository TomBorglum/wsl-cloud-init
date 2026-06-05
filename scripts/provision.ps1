# User-specific variables — edit these before running
$LinuxUsername   = "myuser"
$LinuxGecos      = "My User"
$GitName         = "Tom Borglum"
$GitEmail        = "tom.borglum@gmail.com"
$WindowsUsername = "tombo"

# Substitute and write user-data
$template = Get-Content "$PSScriptRoot\..\distros\ubuntu\24.04\user-data.template" -Raw

$template = $template `
    -replace '__LINUX_USERNAME__',   $LinuxUsername `
    -replace '__LINUX_GECOS__',      $LinuxGecos `
    -replace '__GIT_NAME__',         $GitName `
    -replace '__GIT_EMAIL__',        $GitEmail `
    -replace '__WINDOWS_USERNAME__', $WindowsUsername

$template | Set-Content "$PSScriptRoot\user-data" -NoNewline
Write-Host "Generated user-data for $LinuxUsername"
