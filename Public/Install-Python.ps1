function Install-Python {
  [CmdletBinding()]
  param (
    [switch]$Force
  )

  begin {
    $Host_Os = cliHelper.xcrypt\xcrypt Get_Host_Os
    $skip_install = !$Force -and [bool](Get-Command python -ErrorAction Ignore)
  }
  process {
    if ($skip_install) { return }
    switch ($Host_Os) {
      'Windows' {
        # Install Chocolatey if not already installed
        if (!(Get-Command choco -ErrorAction Ignore)) {
          Write-Console "Installing Chocolatey..." -f LimeGreen
          Set-ExecutionPolicy Bypass -Scope Process -Force
          [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
          [scriptBlock]::Create("$((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))").Invoke()
        }
        Write-Console "Installing Python..." -f LimeGreen
        choco install -y python3
      }
      'Linux' {
        # Install Python using the system package manager
        if ([bool](Get-Command apt-get -ErrorAction Ignore)) {
          Write-Console "Installing Python using apt..." -f LimeGreen
          sudo apt-get update
          sudo apt-get install -y python3
        } elseif ([bool](Get-Command yay -ErrorAction Ignore)) {
          Write-Console "Installing Python using yay..." -f LimeGreen
          yay -S --noconfirm python3
        } else {
          throw "Unsupported Linux package manager."
        }
      }
      'MacOS' {
        if (![bool](Get-Command brew -ErrorAction Ignore)) {
          Write-Console "Installing Homebrew..." -f LimeGreen
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        }
        Write-Console "Installing Python using Homebrew..." -f LimeGreen
        brew install python
      }
      Default {
        throw "Unsupported OS: $Host_Os"
      }
    }
  }
  end {
    if (!$skip_install) {
      $(Write-Console "verifying: gcm python " -f Yellow -NoNewLine; [bool](Get-Command python -ErrorAction Ignore)) ? (Write-Console "Successfully installed python" -f LimeGreen) : $(Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to install python" -f LightCoral)
    } else {
      Write-Console "[+] $(python --version 2>&1) is already installed" -f LimeGreen
    }
  }
}