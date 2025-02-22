function New-PythonProject {
  [CmdletBinding(supportsShouldProcess = $true)]
  param (
    [Parameter(Mandatory = $false)]
    [string]$Path = (Resolve-Path .).Path,

    [Parameter(Mandatory = $false)]
    [Alias('Version')][ValidateScript({
        if (($_ -as 'version') -is [version] -and $_ -in [venv]::data.PythonVersions) {
          return $true
        } else {
          throw [System.IO.InvalidDataException]::New('Please Provide a valid version')
        }
      })]
    [string]$pythonVersion
  )

  begin {
    if (!(Get-Command pipenv -type Application -ea Ignore)) { pipEnv\Install-Pipenv }
    $Name = Split-Path $Path -Leaf
  }

  process {
    if ($PSCmdlet.ShouldProcess(" Create python project", $Name)) {
      pipenv --python $pythonVersion
    }
  }
}