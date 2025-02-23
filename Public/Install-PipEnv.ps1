function Install-PipEnv {
  [CmdletBinding()]
  param (
    [switch]$Force
  )
  begin {
    $has_pipenv = { [bool](Get-Command pipenv -ea Ignore) }
    $skip_minst = !$Force -and $has_pipenv.Invoke()
    $_set_alias = { Set-Alias pipenv pipEnv\Invoke-PipEnv -Scope Global }
  }
  process {
    if ($skip_minst) { return }
    Write-Console "Installing pipEnv ..." -f LimeGreen
    # "pip" comes pre-installed with Python versions 3.4+, but just in case if its not there we use the one in the venv
    if (!(Get-Command python -type Application -ea Ignore)) { pipEnv\Install-Python }
    $pip_path = Get-Command pip -type Application -ea Ignore | Select-Object -Expand Source -First 1
    # $pip_path = [string]::IsNullOrEmpty($pip_path) ? ([IO.Path]::combine($venv_name, 'bin', 'pip')) : $pip_path
    if (![IO.File]::Exists($pip_path)) { throw [IO.FileNotFoundException]::new("pip was not found") }
    &$pip_path install --upgrade pip --break-system-packages
    Install-PyEnv
    [void][venv]::SetLocalVersion()
    &$pip_path install pipenv --user --no-warn-script-location --break-system-packages
    if ([venv]::data.Os.Equals('Windows')) {
      cliHelper.env\Update-SessionEnv
    }
    [void]("`nif (!$($has_pipenv.ToString().Trim())) {$_set_alias}" >> (Get-Variable PROFILE -ValueOnly))
    if (!$has_pipenv.Invoke()) { $_set_alias.Invoke() }
  }

  end {
    if (!$skip_minst) {
      Write-Console "TEST: gcm pipenv" -f Yellow
      $has_pipenv.Invoke() ? (Write-Console "Successfully installed pipenv" -f LimeGreen) : (Write-Console "pipenv install failed" -f LightCoral)
    } else {
      Write-Console "$(pipenv --version) is already installed" -f LimeGreen
    }
  }
}