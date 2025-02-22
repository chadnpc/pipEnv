#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Collections.Generic
using namespace System.Management.Automation

#Requires -RunAsAdministrator
#Requires -Modules clihelper.env, cliHelper.core
#Requires -Psedition Core

#region    Classes
enum EnvState {
  Inactive
  Active
}

enum PackageManager {
  pip
  poetry
}

enum EnvManagerName {
  pipEnv
}

class EnvManager {
  static [Dictionary[string, string]]$Environments = @{}
  static [PsRecord]$data = @{ # Cached data
    SharePipcache = $False
    ProjectPath   = (Resolve-Path .).Path
    Session       = $null
    Manager       = [EnvManagerName]::pipEnv
    Home          = [EnvManager]::Get_work_Home()
    Os            = Get-HostOs
  }

  static [string] Get_work_Home() {
    $xdgDataHome = [Environment]::GetEnvironmentVariable("XDG_DATA_HOME", [EnvironmentVariableTarget]::User) # For Unix-like systems
    $whm = $xdgDataHome ? ([IO.Path]::Join($xdgDataHome, "virtualenvs")) : ([IO.Path]::Combine([Environment]::GetFolderPath("UserProfile"), ".local", "share", "virtualenvs"))
    $exp = [IO.Path]::Combine([Environment]::ExpandEnvironmentVariables($whm), "")
    $exp = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($exp))
    if (![IO.Directory]::Exists($exp)) {
      try {
        New-Item -Path $exp -ItemType Directory -Force | Out-Null
      } catch {
        throw "Failed to create directory '$exp': $_"
      }
    }
    return $exp
  }
  static [void] LoadEnvironments() {
    # Example: Load environments from a JSON file (you can customize this)
    $envFilePath = Join-Path $env:USERPROFILE ".python_environments.json"
    if (Test-Path $envFilePath) {
      [EnvManager]::Environments = Get-Content $envFilePath | ConvertFrom-Json -AsHashtable
    } else {
      [EnvManager]::Environments = @{}
    }
  }
  static [void] SaveEnvironments() {
    $envFilePath = Join-Path $env:USERPROFILE ".python_environments.json"
    [EnvManager]::Environments | ConvertTo-Json | Set-Content $envFilePath
  }
  static [bool] InstallPackage([string]$Environment, [string]$Package, [string]$Version) {
    try {
      if (![EnvManager]::Environments.ContainsKey($Environment)) {
        throw "Environment '$Environment' does not exist."
      }

      $pipPath = [EnvManager]::GetPipPath($Environment)
      if (!$pipPath) {
        throw "Could not find pip for environment '$Environment'."
      }

      $packageSpec = if ($Version) { "$Package==$Version" } else { $Package }
      & $pipPath install $packageSpec
      return $true
    } catch {
      Write-Error "Failed to install package: $_"
      return $false
    }
  }
  static [bool] UpdatePackage([string]$Environment, [string]$Package, [string]$Version) {
    try {
      if (![EnvManager]::Environments.ContainsKey($Environment)) {
        throw "Environment '$Environment' does not exist."
      }

      $pipPath = [EnvManager]::GetPipPath($Environment)
      if (!$pipPath) {
        throw "Could not find pip for environment '$Environment'."
      }

      $packageSpec = if ($Version) { "$Package==$Version" } else { $Package }
      & $pipPath install --upgrade $packageSpec
      return $true
    } catch {
      Write-Error "Failed to update package: $_"
      return $false
    }
  }
  static [List[Hashtable]] ListPackages([string]$Environment) {
    try {
      if (![EnvManager]::Environments.ContainsKey($Environment)) {
        throw "Environment '$Environment' does not exist."
      }

      $pipPath = [EnvManager]::GetPipPath($Environment)
      if (!$pipPath) {
        throw "Could not find pip for environment '$Environment'."
      }

      $packages = & $pipPath list --format=json
      return $packages | ConvertFrom-Json | ForEach-Object { @{
          Name    = $_.name
          Version = $_.version
        } }
    } catch {
      Write-Error "Failed to list packages: $_"
      return [List[Hashtable]]::new()
    }
  }
  static [List[string]] ListEnvironments() {
    return [List[string]][EnvManager]::Environments.Keys
  }
  static [string] GetPipPath([string]$Environment) {
    $envPath = [EnvManager]::Environments[$Environment]
    if (!$envPath) {
      return $null
    }
    if ((xcrypt Get_Host_Os) -eq "Windows") {
      return [IO.Path]::Combine($envPath, "Scripts", "pip.exe")
    } else {
      return [IO.Path]::Combine($envPath, "bin", "pip")
    }
  }
  static [bool] AddEnvironment([string]$Name, [string]$Path) {
    if ([EnvManager]::Environments.ContainsKey($Name)) {
      Write-Error "Environment '$Name' already exists."
      return $false
    }
    [EnvManager]::Environments[$Name] = $Path
    [EnvManager]::SaveEnvironments()
    return $true
  }
  static [bool] RemoveEnvironment([string]$Name) {
    if (![EnvManager]::Environments.ContainsKey($Name)) {
      Write-Error "Environment '$Name' does not exist."
      return $false
    }
    [EnvManager]::Environments.Remove($Name)
    [EnvManager]::SaveEnvironments()
    return $true
  }
}

# .SYNOPSIS
#   python virtual environment manager
class venv : EnvManager {
  [string]$Path
  [string]$CreatedAt
  [version]$PythonVersion
  [PackageManager]$PackageManager
  [validateNotNullOrEmpty()][string]$BinPath
  static [validateNotNullOrEmpty()][InstallRequirements]$req = @{ list = @() }
  hidden [string]$__name
  venv() {
    [void][venv]::From([IO.DirectoryInfo]::new([venv]::data.ProjectPath), [ref]$this)
  }
  venv([string]$dir) {
    [void][venv]::From([IO.DirectoryInfo]::new($dir), [ref]$this)
  }
  venv([IO.DirectoryInfo]$dir) {
    [void][venv]::From($dir, [ref]$this)
  }
  static [venv] Create() {
    return [venv]::Create([IO.DirectoryInfo]::new([venv]::data.ProjectPath))
  }
  static [venv] Create([string]$dir) {
    return [venv]::Create([IO.DirectoryInfo]::new($dir))
  }
  static [venv] Create([IO.DirectoryInfo]$dir) {
    # .INPUTS
    #  DirectoryInfo: It can be ProjectPath or the exact path for the venv.
    if (!$dir.Exists) { throw [Argumentexception]::new("Please provide a valid path!", [DirectoryNotFoundException]::new("Directory not found: $dir")) }
    $p = $null; $r = $null; $v = (Get-Variable 'VerbosePreference' -ValueOnly) -eq 'Continue'
    try {
      $path_str = $dir.FullName | Invoke-PathShortener
      if (![venv]::IsValid($dir.FullName)) {
        $v ? $(Write-Console "[venv] " -f SlateBlue -NoNewLine; Write-Console "Try Create from '$path_str' ... "-f LemonChiffon -NoNewLine) : $null
        $_env_paths = $dir.EnumerateDirectories("*", [SearchOption]::TopDirectoryOnly).Where({ [venv]::IsValid($_.FullName) })
        if ($_env_paths.count -eq 0) { throw "No environment directory found for in '$path_str' ." }
        if ($_env_paths.count -gt 1) { throw "Multiple environment directories found in '$path_str' ." }
        $p = $_env_paths[0].FullName;
      } else {
        $dir
      }
    } catch {
      $v ? $(Write-Console "Failed" -f PaleTurquoise -NoNewLine; Write-Console "`n       Search already created env in: $([venv]::data.Home | Invoke-PathShortener) ... "-f LemonChiffon -NoNewLine) : $null
      $p = [venv]::GetEnvPath($dir.FullName)
    } finally {
      $r = $p ? [venv]::new($p) : $null
    }
    if ($r.IsValid) { $v ? $(Write-Console "Done" -f Green) : $null; return $r } else { $v ? $(Write-Console "Failed" -f PaleVioletRed) : $null }

    # Create new virtual environment named $dir.BaseName and save in work_home [venv]::data.Home
    Push-Location $dir.FullName;
    [void][venv]::SetLocalVersion()
    Write-Console "[venv] " -f SlateBlue -NoNewLine; Write-Console "Creating new env ... "-f LemonChiffon -NoNewLine;
    # https://pipenv.pypa.io/en/latest/virtualenv.html#virtual-environment-name
    $usrEnvfile = [FileInfo]::new([Path]::Combine($dir.FullName, ".env"))
    $name = ($dir.BaseName -as [version] -is [version]) ? ("{0}_{1}" -f $dir.Parent.BaseName, $dir.BaseName) : $dir.BaseName
    if (![string]::IsNullOrWhiteSpace($name)) { "PIPENV_CUSTOM_VENV_NAME=$name" >> $usrEnvfile.FullName }
    [venv]::Run(("install", "check"))
    $usrEnvfile.Exists ? ($usrEnvfile.FullName | Remove-Item -Force -ea Ignore) : $null
    Pop-Location; Write-Console "Done" -f Green

    $p = [venv]::GetEnvPath($dir.FullName)
    if (![Directory]::Exists($p)) { throw [InvalidOperationException]::new("Failed to create a venv Object", [DirectoryNotFoundException]::new("Directory not found: $p")) }
    return [venv]::new($p)
  }
  static hidden [venv] From([IO.DirectoryInfo]$dir, [ref]$o) {
    # .SYNOPSIS
    #  venv object initializer (like __init__ ), Loads the venv object from directory info
    # .DESCRIPTION
    #  Does not create a new venv, meaning it can create a valid venv object from a directory
    #  Only if that directory is a valid env directory.
    [venv]::data.set('Session', $([ref]$o.Value).Value)
    [IO.Directory]::Exists($dir.FullName) ? ($dir | Set-ItemProperty -Name Attributes -Value ([IO.FileAttributes]::Hidden)) : $null
    if (![venv]::IsValid($dir.FullName)) { [InvalidOperationException]::new("Failed to create a venv Object", [Argumentexception]::new("$dir is not a valid venv folder", $dir)) | Write-Error }
    [venv].PsObject.Properties.Add([PsScriptproperty]::new('CONSTANTS', { return [scriptblock]::Create("@{
            # Add your constant primitives here:
            validversionregex = '^(0|[1-9]\d*)(\.(0|[1-9]\d*)){0,3}$'
          }").InvokeReturnAsIs()
        }, { throw [SetValueException]::new("CONSTANTS is read-only") }
      )
    )
    $o.Value.PsObject.Properties.Add([Psscriptproperty]::new('Name', {
          $v = [venv]::IsValid($this.Path)
          $has_deact_command = $null -ne (Get-Command deactivate -ea Ignore);
          $this.PsObject.Properties.Add([Psscriptproperty]::new('State', [scriptblock]::Create("return [EnvState][int]$([int]$($has_deact_command -and $v))"), { throw [SetValueException]::new("State is read-only") }));
          $this.PsObject.Properties.Add([Psscriptproperty]::new('IsValid', [scriptblock]::Create("return [IO.Path]::Exists(`$this.Path) -and [bool]$([int]$v)"), { throw [SetValueException]::new("IsValid is read-only") }));
          return "({0}) {1}" -f [venv]::data.Manager, ($v ? $this.__name : '✖');
        }, { Param([string]$n) [string]::IsNullOrWhiteSpace("$($this.__name) ".Trim()) ? ($this.__name = $n) : $null }
      )
    )
    # $o.Value.Name = $dir.Name;
    $o.Value.Path = $dir.FullName; #the exact path for the venv
    $o.Value.CreatedAt = [Datetime]::Now.ToString();
    [venv]::data.PsObject.Properties.Add([PsScriptproperty]::new('PythonVersions', { return [venv]::get_python_versions() }, { throw [SetValueException]::new("PythonVersions is read-only") }))
    [venv]::data.PsObject.Properties.Add([PsScriptproperty]::new('SelectedVersion', { return [version]$(python --version).Split(" ").Where({ $_ -match [venv].CONSTANTS.validversionregex })[0] }, { throw [SetValueException]::new("SelectedVersion is read-only") }))
    # $p = python -c "import pipenv; print(pipenv.__file__)"; ie: (Get-Command pipenv -Type Application -ea Ignore).Source
    [venv]::data.set('RequirementsFile', "requirements.txt")
    ![venv]::req ? ([venv]::req = [InstallRequirements][requirement]("pipenv", "Python virtualenv management tool", { Install-Pipenv } )) : $null
    ![venv]::req.resolved ? [venv]::req.Resolve() : $null
    $o.Value.PythonVersion = [venv]::data.selectedversion;
    if (![string]::IsNullOrWhiteSpace($o.Value.Name) -and $o.Value.IsValid) {
      $venvconfig = Read-Env -File ([IO.Path]::Combine($dir.FullName, 'pyvenv.cfg'));
      $c = @{}; $venvconfig.Name.ForEach({ $n = $_; $c[$n] = $venvconfig.Where({ $_.Name -eq $n }).value });
      [venv]::data.Set($c)
    }
    return $o.Value
  }
  static hidden [version[]] get_python_versions() {
    return ((pyenv versions).Split("`n").Trim() | Select-Object @{l = "version"; e = { $l = $_; if ($l.StartsWith("*")) { $l = $l.Substring(1).TrimStart().Split(' ')[0] }; $m = $l -match [venv].CONSTANTS.validversionregex; $m ? $l : "not-a-version" } } | Where-Object { $_.version -ne "not-a-version" }).version
  }
  static [Object[]] SetLocalVersion() {
    return [venv]::SetLocalVersion([Path]::Combine([venv]::data.ProjectPath, ".python-version"))
  }
  static [Object[]] SetLocalVersion([string]$str = "versionfile_or_version") {
    [ValidateNotNullOrWhiteSpace()][string]$str = $str; $res = $null;
    $ver = switch ($true) {
      ([IO.File]::Exists($str)) {
        $ver_in_file = Get-Content $str; $localver = pyenv local
        ($localver -ne $ver_in_file) ? $ver_in_file : $null
        break
      }
      ($str -as [version] -is [version]) { $str; break }
      Default { $null }
    }
    if ($null -ne $ver) {
      $sc = [scriptblock]::Create("pyenv install $ver")
      Write-Console "[Python v$ver] " -f SlateBlue -NoNewLine;
      $res = [progressUtil]::WaitJob("Installing", (Start-Job -Name "Install python $ver" -ScriptBlock $sc));
    }
    return $res
  }
  [string] GetActivationScript() {
    return $this.GetActivationScript($this.Path)
  }
  [string] GetActivationScript([string]$ProjectPath) {
    $s = ([venv]::IsValid($ProjectPath) ? ([IO.Path]::Combine($ProjectPath, 'bin', 'activate.ps1')) : '')
    if (![IO.File]::Exists($s)) { throw [Exception]::new("Failed to get activation script", [FileNotFoundException]::new("file '$s' not found!")) }
    return $s
  }
  static [string] GetEnvPath() {
    return [venv]::GetEnvPath([venv]::data.ProjectPath)
  }
  static [string] GetEnvPath([string]$ProjectPath) {
    $reslt = $null; $_env_paths = [venv]::Get_work_Home() | Get-ChildItem -Directory -ea Ignore
    if ($null -ne $_env_paths) {
      $reslt = $_env_paths.Where({ [IO.File]::ReadAllLines([IO.Path]::Combine($_.FullName, ".project"))[0] -eq $ProjectPath })
      $reslt = ($reslt.count -eq 0) ? $null : $reslt[0]
    }
    return $reslt
  }
  static [bool] IsValid([string]$dir) {
    $v = $true; $d = [IO.DirectoryInfo]::new($dir); ("bin", "lib").ForEach{
      $_d = $d.EnumerateDirectories($_); $v = $v -and (($_d.count -eq 1) ? $true : $false)
      if ($_ -eq 'bin') { $v = $v -and (($_d[0].EnumerateFiles("activate*").Count -gt 0) ? $true : $false) }
    }; $v = $v -and (($d.EnumerateFiles("pyvenv.cfg").Count -eq 1) ? $true : $false);
    return $v
  }
  [Object[]] Activate() { return & ([venv]::data.Session.GetActivationScript()) }
  [Object[]] verify() { return [venv]::Run("verify") }
  [Object[]] upgrade() { pip install --user --upgrade pipenv; return [venv]::Run("upgrade") }
  [Object[]] sync() { return [venv]::Run("sync") }
  [Object[]] lock() { return [venv]::Run("lock") }
  [Object[]] install() { python -m pipenv install -q; return [venv]::Run("install") }
  [Object[]] Install([string]$package) { python -m pipenv install -q $package; return [venv]::Run("install") }
  [Object[]] Remove() { return python -m pipenv --rm }

  static [Object[]] Run([string[]]$commands) {
    $res = @(); foreach ($c in $commands) {
      $res += switch ($true) {
        $($c -eq "shell") { [venv]::data.Session.Activate(); break }
        default { python -m pipenv $c }
      }
    }
    return $res
  }
  [bool] Clone([string]$Source, [string]$Destination) {
    try {
      if (!$this.Environments.ContainsKey($Source)) {
        throw "Source environment '$Source' does not exist."
      }
      $sourcePath = $this.Environments[$Source]
      $destinationPath = "$sourcePath\..\$Destination"
      Copy-Item -Path "$sourcePath" -Destination $destinationPath -Recurse
      $this.Environments[$Destination] = $destinationPath
      $this.Save()
      return $true
    } catch {
      Write-Error "Failed to clone environment: $_"
      return $false
    }
  }
  [bool] Export([string]$Name, [string]$OutputFile) {
    try {
      if (!$this.Environments.ContainsKey($Name)) {
        throw "Environment '$Name' does not exist."
      }
      & "$($this.Environments[$Name])\$Name\Scripts\pip.exe" freeze > $OutputFile
      return $true
    } catch {
      Write-Error "Failed to export environment: $_"
      return $false
    }
  }
  [bool] Import([string]$InputFile) {
    try {
      $packages = Get-Content $InputFile
      foreach ($package in $packages) {
        $this.InstallPackage($package, $null)
      }
      return $true
    } catch {
      Write-Error "Failed to import environment: $_"
      return $false
    }
  }
  [bool] CheckCompatibility([string]$Package, [string]$Version) {
    try {
      $result = & "$($this.BinPath)\pip.exe" check "$Package==$Version"
      return ($result -eq "No broken dependencies")
    } catch {
      Write-Error "Failed to check compatibility: $_"
      return $false
    }
  }
  [Hashtable] GetDetails([string]$Name) {
    try {
      if (!$this.Environments.ContainsKey($Name)) {
        throw "Environment '$Name' does not exist."
      }
      $details = @{
        Name     = $Name
        Path     = $this.Environments[$Name]
        Packages = $this.ListPackages($Name)
        Active   = ($this.Name -eq $Name)
      }
      return $details
    } catch {
      Write-Error "Failed to get details: $_"
      return @{}
    }
  }
  [bool] SyncWithGlobal([List[string]]$Exclusions) {
    try {
      if ($null -eq $this.Name) {
        throw "No environment is currently active."
      }
      $globalPackages = & "$($this.BinPath)\pip.exe" list --format=json | ConvertFrom-Json | ForEach-Object { $_.name }
      foreach ($package in $globalPackages) {
        if (!($Exclusions -contains $package)) {
          $this.InstallPackage($package, $null)
        }
      }
      return $true
    } catch {
      Write-Error "Failed to sync with global: $_"
      return $false
    }
  }
  [EnvState] CheckStatus([string]$Name) {
    if (!$this.Environments.ContainsKey($Name)) { throw "Environment '$Name' does not exist." }
    $status = ''
    try {
      $status = switch ($true) {
        ($this.Name -eq $Name) { "active"; break }
        default {
          "inactive"
        }
      }
    } catch {
      throw "Failed to check status: $_"
    }
    return $status
  }
  [bool] Deactivate() {
    try {
      if ($null -eq $this.Name) {
        throw "No environment is currently active."
      }
      & "$($this.BinPath)\deactivate.ps1"
      $this.Name = $null
      return $true
    } catch {
      Write-Error "Failed to deactivate environment: $_"
      return $false
    }
  }
  [void] Save() {
    # Save environments to a configuration file or registry
    # This is a placeholder for actual implementation
    # For example, writing to a JSON file
    # $config = @{ Environments = $this.Environments }
    # $config | ConvertTo-Json | Set-Content -Path "EnvManagerConfig.json"
  }
  [void] Delete() {
    $this.Path | Remove-Item -Force -Recurse -Verbose:$false -ea Ignore
  }
}

#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [EnvManagerName],
  [EnvState],
  [venv]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '

    [System.Management.Automation.ErrorRecord]::new(
      [System.InvalidOperationException]::new($Message),
      'TypeAcceleratorAlreadyExists',
      [System.Management.Automation.ErrorCategory]::InvalidOperation,
      $Type.FullName
    ) | Write-Warning
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
