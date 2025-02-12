function Install-Pipenv {
  [CmdletBinding()]
  param ()

  process {
    if (!(Get-Command python -type Application -ea Ignore)) { Install-Python }
    python -m ensurepip --upgrade
    python -m pip install --upgrade pip
    switch ([venv]::data.Os) {
      'Windows' { Write-Warning "Pyenv does not officially support Windows and does not work in Windows outside the Windows Subsystem for Linux."; break }
      default { curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash }
    }
    python -m pip install pipenv --user --no-warn-script-location
    $sitepackages = python -m site --user-site
    $sitepackages = [venv]::data.Os.Equals('Windows') ? $sitepackages.Replace('site-packages', 'Scripts') : $sitepackages
    cliHelper.env\Set-Env -Name PATH -Scope 'Machine' -Value ("{0}{1}{2}" -f $env:PATH, [IO.Path]::PathSeparator, $sitepackages)
    cliHelper.env\Update-SessionEnv
  }
}