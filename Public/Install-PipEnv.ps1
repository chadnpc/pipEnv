function Install-PipEnv {
  [CmdletBinding()]
  param (
    [switch]$Force
  )
  begin {
    $has_pipenv = { [bool](Get-Command pipenv -ea Ignore) }
    $skip_minst = !$Force -and $has_pipenv.Invoke()
    $_set_alias = { Set-Alias pipenv pipEnv\Invoke-PipEnv -Scope Global }
    if ($skip_minst) { return }
    Write-Console "Installing pipEnv ..." -f LimeGreen
    # "pip" comes pre-installed with Python versions 3.4+, but just in case if its not there we use the one in the venv
    if (!(Get-Command python -type Application -ea Ignore)) { pipEnv\Install-Python }
    if (![IO.File]::Exists((Get-Command pip -type Application -ea Ignore | Select-Object -Expand Source -First 1))) {
      throw [IO.FileNotFoundException]::new("Install-PipEnv failed: pip was not found")
    }
  }
  process {
    Install-PyEnv
    [void][venv]::SetLocalVersion()
    $pip = [IO.FileInfo]::new("/$(Get-Variable HOME -ValueOnly)/.pyenv/shims/pip")
    &$pip.FullName install --upgrade pip --break-system-packages
    &$pip.FullName install pipenv --user --no-warn-script-location --break-system-packages
    if ([venv]::data.Os.Equals('Windows')) { cliHelper.env\Update-SessionEnv }
    [void]("`nif (!$($has_pipenv.ToString().Trim())) {$_set_alias}" >> (Get-Variable PROFILE -ValueOnly))
    if (!$has_pipenv.Invoke()) { $_set_alias.Invoke() }
  }

  end {
    if (!$skip_minst) {
      Write-Console "verifying: gcm pipenv " -f Yellow -NoNewLine
      $has_pipenv.Invoke() ? (Write-Console "[+] Successfully installed pipenv" -f LimeGreen) : (Write-Console "pipenv install failed" -f LightCoral)
    } else {
      Write-Console "[+] $(pipenv --version) is already installed" -f LimeGreen
    }
  }
}