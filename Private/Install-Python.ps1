function Install-Python {
  [CmdletBinding()]
  param ()
  begin { }
  process {
    if ([venv]::data.Os.Equals('Windows')) {
      if (!(Get-Command choco -Type Application -ea Ignore)) { Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; [scriptBlock]::Create("$((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))").Invoke() }
      choco install -y python3
    } else {
      throw "not implemented yet"
    }
    Write-Host "Installed $((python --version))"
  }
}