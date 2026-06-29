# Read API keys/tokens from Windows Credential Manager
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class CredManager {
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

  [DllImport("advapi32.dll")]
  public static extern void CredFree(IntPtr buffer);
}
'@

function Get-WindowsCredential([string]$target) {
  $ptr = [IntPtr]::Zero
  if (-not [CredManager]::CredRead($target, 1, 0, [ref]$ptr)) {
    throw "Credential '$target' not found in Windows Credential Manager."
  }
  try {
    # CREDENTIAL struct offsets on 64-bit Windows:
    #   +32 CredentialBlobSize (DWORD)
    #   +40 CredentialBlob (IntPtr, after 4-byte padding for alignment)
    $blobSize = [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr, 32)
    $blobPtr  = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($ptr, 40)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($blobPtr, $blobSize / 2)
  } finally {
    [CredManager]::CredFree($ptr)
  }
}
