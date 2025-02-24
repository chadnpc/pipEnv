function Install-PyEnv {
  # .SYNOPSIS
  #   Installs Pyenv
  # .DESCRIPTION
  #   Install Pyenv using the pyenv-installer script.
  # .LINK
  #   https://github.com/alainQtec/pipEnv/blob/main/Public/Install-PyEnv.ps1
  [CmdletBinding()]
  param (
    [switch]$Force
  )
  begin {
    $has_pyenv = { return [bool](Get-Command pyenv -type Application -ea Ignore) }
    $skip_inst = !$Force -and $has_pyenv.Invoke()
  }
  process {
    if ($skip_inst) { return }
    # First we add to PATH
    $add_to_path = "cliHelper.env\Set-Env -Name PATH -Scope 'Machine' -Value ('{0}{1}{2}' -f `$env:PATH, [IO.Path]::PathSeparator, '${Home}/.pyenv/bin')"
    [scriptblock]::Create($add_to_path).Invoke()
    # Install only for non-Windows
    switch ([venv]::data.Os) {
      'Windows' {
        Write-Console "Pyenv does not officially support Windows and does not work in Windows outside the Windows Subsystem for Linux." -f LightCoral
        break
      }
      default {
        $d = [IO.DirectoryInfo]::new([IO.Path]::Combine((Get-Variable HOME -ValueOnly), ".pyenv"));
        if ($d.Exists) { $d.Delete($true) } # uninstall if it was already installed.
        [void][progressUtil]::WaitJob("Installing pyenv from https://github.com/pyenv/pyenv-installer",
          { curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash }
        )
        $s = "`nif ([IO.Path]::Exists('${Home}/.pyenv/bin')) { $add_to_path }"
        $s >> (Get-Variable PROFILE -ValueOnly)
        $s += "`nif ((Get-Command pyenv -type Application -ea Ignore)) { pyenv init pwsh }"
        [scriptblock]::Create($s).Invoke()
      }
    }
  }
  end {
    if (!$skip_inst) {
      $(Write-Console "verifying: gcm pyenv " -f Yellow -NoNewLine; $has_pyenv.Invoke()) ? (Write-Console "Successfully installed pyenv" -f LimeGreen) : (Write-Console "pyenv install failed" -f LightCoral)
    } else {
      Write-Console "$(pyenv --version) is already installed" -f LimeGreen
    }
  }
}