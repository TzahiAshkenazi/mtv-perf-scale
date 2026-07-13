# Define the directory to store the files
$dir = "c:\users\administrator\download\mtv\data"

# Ensure the directory exists; create it if it doesn't
if (-not (Test-Path $dir)) {
    New-Item -Path $dir -ItemType Directory -Force
    Write-Host "Created directory: $dir"
}
for ($i=1; $i -le 50; $i++) {
    $sizeInBytes = [int](Get-Random -Minimum 10MB -Maximum 1GB)
    $file = Join-Path -Path $dir -ChildPath "randomfile_$i.bin"
    $random = New-Object byte[]($sizeInBytes)
    (New-Object Random).NextBytes($random)
    [System.IO.File]::WriteAllBytes($file, $random)
    Write-Output "Created: $file ($sizeInBytes bytes)"
}