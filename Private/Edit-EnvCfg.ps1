function Edit-EnvCfg {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Path = "pyvenv.cfg",

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Key,

    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Value
  )

  process {
    $_cp = [IO.FileInfo]::new(($Path | xcrypt GetUnResolvedPath))
    if ($_cp.Exists) {
      # discardedbcz it deletes comments
      # $cfg = Read-Env $_cp.FullName
      # $cfg = $cfg | Select-Object @{ l = 'Name'; e = { $_.Name } }, @{ l = 'value'; e = { ($_.Name -eq $Key) ? $Value : $_.Value } }
      # $str = ''; $cfg.ForEach({ $str += "{0} = {1}`n" -f $_.Name, $_.value });
      # [void][IO.File]::WriteAllText($_cp.FullName, $str.TrimEnd())
      "$Key = $Value" | Out-File $_cp.FullName -Append
    }
  }
}