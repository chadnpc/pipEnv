function New-pipEnv {
  [CmdletBinding(supportsShouldProcess = $true)]
  [OutputType([Venv])]
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Name = [pipEnv]::data.venv.Config.defaultName
  )

  process {
    $v = $null
    if ($PSCmdlet.ShouldProcess("Create virtual environment")) {
      $v = [Venv]::Create($Name)
    }
  }

  end {
    return $v
  }
}