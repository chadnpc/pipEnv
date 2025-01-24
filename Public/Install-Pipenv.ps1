function Install-Pipenv {
  [CmdletBinding()]
  param (
  )

  begin {
    function Install-Pyenv {
      [CmdletBinding()]
      param ()

      process {
        switch ([pipEnv]::data.Os) {
          'Windows' { Write-Warning "Pyenv does not officially support Windows and does not work in Windows outside the Windows Subsystem for Linux."; break }
          default { curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash }
        }
      }
      end {
        cliHelper.env\Update-SessionEnv
      }
    }
    function Install-Pip {
      [CmdletBinding()]
      param ()

      begin {}

      process {
        if (!(Get-Command python -type Application -ea Ignore)) { Install-Python }
        switch ([pipEnv]::data.Os) {
          'Windows' { python -m ensurepip --upgrade; break }
          default { python -m ensurepip --upgrade }
        }
      }

      end {
        pip install --user --upgrade pip
      }
    }
    function Install-Python {
      [CmdletBinding()]
      param ()
      begin { }
      process {
        if ($IsWindows) {
          if (!(Get-Command choco -Type Application -ea Ignore)) { Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; [scriptBlock]::Create("$((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))").Invoke() }
          choco install -y python3
        } else {
          throw "not implemented yet"
        }
        Write-Host "Installed Python v$((python --version))"
      }
    }
  }

  process {
    Install-Python
    Install-Pip
    Install-Pyenv
    pip install pipenv --user
    $sitepackages = python -m site --user-site
    $sitepackages = [pipEnv]::data.Os.Equals('Windows') ? $sitepackages.Replace('site-packages', 'Scripts') : $sitepackages
    # add $sitepackages to $env:PATH
    # $env:PATH = "$env:PATH;$sitepackages"
  }
}