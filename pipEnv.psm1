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
class DependencyInfo {
  [string]$Name
  [string]$Version
}

class InstallException : Exception {
  InstallException() {}
  InstallException([string]$message) : base($message) {}
  InstallException([string]$message, [Exception]$innerException) : base($message, $innerException) {}
}

class InstallFailedException : InstallException {
  InstallFailedException() {}
  InstallFailedException([string]$message) : base($message) {}
  InstallFailedException([string]$message, [Exception]$innerException) : base($message, $innerException) {}
}

class Requirement {
  [string] $Name
  [version] $Version
  [string] $Description
  [string] $InstallScript

  Requirement() {}
  Requirement([array]$arr) {
    $this.Name = $arr[0]
    $this.Version = $arr.Where({ $_ -is [version] })[0]
    $this.Description = $arr.Where({ $_ -is [string] -and $_ -ne $this.Name })[0]
    $__sc = $arr.Where({ $_ -is [scriptblock] })[0]
    $this.InstallScript = ($null -ne $__sc) ? $__sc.ToString() : $arr[-1]
  }
  Requirement([string]$Name, [scriptblock]$InstallScript) {
    $this.Name = $Name
    $this.InstallScript = $InstallScript.ToString()
  }
  Requirement([string]$Name, [string]$Description, [scriptblock]$InstallScript) {
    $this.Name = $Name
    $this.Description = $Description
    $this.InstallScript = $InstallScript.ToString()
  }

  [bool] IsInstalled() {
    try {
      Get-Command $this.Name -Type Application
      return $?
    } catch [CommandNotFoundException] {
      return $false
    } catch {
      throw [InstallException]::new("Failed to check if $($this.Name) is installed", $_.Exception)
    }
  }
  [bool] Resolve() {
    return $this.Resolve($false, $false)
  }
  [bool] Resolve([switch]$Force, [switch]$What_If) {
    $is_resolved = $true
    if (!$this.IsInstalled() -or $Force.IsPresent) {
      Write-Console "[Resolve requrement] $($this.Name) " -f Green -NoNewLine
      if ($this.Description) {
        Write-Console "($($this.Description)) " -f BlueViolet -NoNewLine
      }
      Write-Console "$($this.Version) " -f Green
      if ($What_If.IsPresent) {
        Write-Console "Would install: $($this.Name)" -f Yellow
      } else {
        [ScriptBlock]::Create("$($this.InstallScript)").Invoke()
      }
      $is_resolved = $?
    }
    return $is_resolved
  }
}

Class InstallRequirements {
  [Requirement[]] $list
  [bool] $resolved = $false
  [string] $jsonPath = [IO.Path]::Combine($(Resolve-Path .).Path, 'requirements.json')

  InstallRequirements() {}
  InstallRequirements([array]$list) { $this.list = $list }
  InstallRequirements([List[array]]$list) { $this.list = $list.ToArray() }
  InstallRequirements([hashtable]$Map) { $Map.Keys | ForEach-Object { $Map[$_] ? ($this.$_ = $Map[$_]) : $null } }

  [void] Resolve() {
    $this.Resolve($false, $false)
  }
  [void] Resolve([switch]$Force, [switch]$What_If) {
    $res = $true; $this.list.ForEach({ $res = $res -and $_.Resolve($Force, $What_If) })
    $this.resolved = $res
  }
  [void] Import() {
    $this.Import($this.JsonPath, $false)
  }
  [void] Import([switch]$throwOnFail) {
    $this.Import($this.JsonPath, $throwOnFail)
  }
  [void] Import([string]$JsonPath, [switch]$throwOnFail) {
    if ([IO.File]::Exists($JsonPath)) { $this.list = Get-Content $JsonPath | ConvertFrom-Json }; return
    if ($throwOnFail) {
      throw [FileNotFoundException]::new("Requirement json file not found: $JsonPath")
    }
  }
  [void] Export() {
    $this.Export($this.JsonPath)
  }
  [void] Export([string]$JsonPath) {
    $this.list | ConvertTo-Json -Depth 1 -Verbose:$false | Out-File $JsonPath
  }
  [string] ToString() {
    return $this | ConvertTo-Json
  }
}

class EnvManager {
  [validateNotNullOrEmpty()][string]$BinPath
  [string]$CurrentEnvironment
  [Dictionary[string, string]]$Environments = @{}
  static [validateNotNullOrEmpty()][InstallRequirements]$req

  EnvManager() {
    $this.LoadEnvironments()
  }
  EnvManager([string]$Path) {
    $this.BinPath = $Path
    $this.LoadEnvironments()
  }
  [Object[]] Run([string[]]$commands) {
    $res = @()
    foreach ($c in $commands) {
      $n = [venv]::manager.BinPath | Split-Path -Leaf
      if ($n -eq "pipenv" -and $c -eq "shell") {
        $e = [venv]::Create([venv]::Config.ProjectPath); $s = [IO.Path]::Combine($e.Path, 'bin', 'activate.ps1')
        $(![string]::IsNullOrWhiteSpace($e) -and ![string]::IsNullOrWhiteSpace($s)) ? $( return &$s ) : $( throw "Failed to get activation script")
      }
      $res += & ($this.BinPath) $commands
    }
    return $res
  }
  [bool] CreateEnvironment([string]$Name, [string]$Path) {
    try {
      if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
      }
      & "$($this.BinPath)\python.exe" -m venv "$Path\$Name"
      $this.Environments[$Name] = $Path
      $this.SaveEnvironments()
      return $true
    } catch {
      Write-Error "Failed to create environment: $_"
      return $false
    }
  }
  [bool] ActivateEnvironment([string]$Name) {
    try {
      if (!$this.Environments.ContainsKey($Name)) {
        throw "Environment '$Name' does not exist."
      }
      $envPath = "$($this.Environments[$Name])\$Name\Scripts\Activate.ps1"
      if (Test-Path $envPath) {
        & $envPath
        $this.CurrentEnvironment = $Name
        return $true
      } else {
        throw "Activation script not found."
      }
    } catch {
      Write-Error "Failed to activate environment: $_"
      return $false
    }
  }
  [bool] DeactivateEnvironment() {
    try {
      if ($null -eq $this.CurrentEnvironment) {
        throw "No environment is currently active."
      }
      & "$($this.BinPath)\deactivate.ps1"
      $this.CurrentEnvironment = $null
      return $true
    } catch {
      Write-Error "Failed to deactivate environment: $_"
      return $false
    }
  }
  [bool] InstallPackage([string]$Package, [string]$Version) {
    try {
      if ($null -eq $this.CurrentEnvironment) {
        throw "No environment is currently active."
      }
      if ($Version) {
        & "$($this.Environments[$this.CurrentEnvironment])\$($this.CurrentEnvironment)\Scripts\pip.exe" install "$Package==$Version"
      } else {
        & "$($this.Environments[$this.CurrentEnvironment])\$($this.CurrentEnvironment)\Scripts\pip.exe" install $Package
      }
      return $true
    } catch {
      Write-Error "Failed to install package: $_"
      return $false
    }
  }
  [List[string]] ListEnvironments() {
    return [List[string]]$this.Environments.Keys
  }
  [bool] DeleteEnvironment([string]$Name) {
    try {
      if (!$this.Environments.ContainsKey($Name)) {
        throw "Environment '$Name' does not exist."
      }
      Remove-Item -Path "$($this.Environments[$Name])\$Name" -Recurse -Force
      $this.Environments.Remove($Name)
      $this.SaveEnvironments()
      return $true
    } catch {
      Write-Error "Failed to delete environment: $_"
      return $false
    }
  }
  ### Medium Pain Points (Helpful Features)
  [List[Hashtable]] ListPackages([string]$Environment) {
    try {
      if (!$this.Environments.ContainsKey($Environment)) {
        throw "Environment '$Environment' does not exist."
      }
      $packages = & "$($this.Environments[$Environment])\$Environment\Scripts\pip.exe" list --format=json
      return $packages | ConvertFrom-Json | ForEach-Object { @{
          Name    = $_.name
          Version = $_.version
        } }
    } catch {
      Write-Error "Failed to list packages: $_"
      return @()
    }
  }
  [bool] CloneEnvironment([string]$Source, [string]$Destination) {
    try {
      if (!$this.Environments.ContainsKey($Source)) {
        throw "Source environment '$Source' does not exist."
      }
      $sourcePath = $this.Environments[$Source]
      $destinationPath = "$sourcePath\..\$Destination"
      Copy-Item -Path "$sourcePath" -Destination $destinationPath -Recurse
      $this.Environments[$Destination] = $destinationPath
      $this.SaveEnvironments()
      return $true
    } catch {
      Write-Error "Failed to clone environment: $_"
      return $false
    }
  }
  [bool] UpdatePackage([string]$Package, [string]$Version) {
    try {
      if ($null -eq $this.CurrentEnvironment) {
        throw "No environment is currently active."
      }
      if ($Version) {
        & "$($this.Environments[$this.CurrentEnvironment])\$($this.CurrentEnvironment)\Scripts\pip.exe" install --upgrade "$Package==$Version"
      } else {
        & "$($this.Environments[$this.CurrentEnvironment])\$($this.CurrentEnvironment)\Scripts\pip.exe" install --upgrade $Package
      }
      return $true
    } catch {
      Write-Error "Failed to update package: $_"
      return $false
    }
  }
  [bool] ExportEnvironment([string]$Name, [string]$OutputFile) {
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
  [bool] ImportEnvironment([string]$InputFile) {
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
  ### Low Pain Points (Nice-to-Have Features)
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
        Active   = ($this.CurrentEnvironment -eq $Name)
      }
      return $details
    } catch {
      Write-Error "Failed to get details: $_"
      return @{}
    }
  }
  [bool] SyncWithGlobal([List[string]]$Exclusions) {
    try {
      if ($null -eq $this.CurrentEnvironment) {
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
        ($this.CurrentEnvironment -eq $Name) { "active"; break }
        default {
          "inactive"
        }
      }
    } catch {
      throw "Failed to check status: $_"
    }
    return $status
  }

  # Helper Methods

  # LoadEnvironments
  [void] LoadEnvironments() {
    # Load environments from a configuration file or registry
    # This is a placeholder for actual implementation
    # For example, reading from a JSON file
    # $config = Get-Content -Path "EnvManagerConfig.json" | ConvertFrom-Json
    # $this.Environments = $config.Environments
  }

  # SaveEnvironments
  [void] SaveEnvironments() {
    # Save environments to a configuration file or registry
    # This is a placeholder for actual implementation
    # For example, writing to a JSON file
    # $config = @{ Environments = $this.Environments }
    # $config | ConvertTo-Json | Set-Content -Path "EnvManagerConfig.json"
  }
}

# .SYNOPSIS
#   Python virtual environment manager
class pipEnv : EnvManager {
  static [venv] $env # [venv]::Create((Resolve-Path .).Path)
  static [PsRecord]$data = [pipEnv].data #starts $null until any instance is created
  pipEnv() { $this.__init__() }
  static [pipEnv] Create() { return [pipEnv]::new() }
  hidden [void] __init__() {
    [pipEnv].PsObject.Properties.Add([PsScriptproperty]::new('CONSTANTS', { return [scriptblock]::Create("@{
            # Add your constant primitives here:
            validversionregex = '^(0|[1-9]\d*)(\.(0|[1-9]\d*)){0,3}$'
          }").InvokeReturnAsIs()
        }, { throw [SetValueException]::new("CONSTANTS is read-only") }
      )
    )
    [pipEnv].PsObject.Properties.Add([PsNoteproperty]::new('session', $([ref]$this).Value))
    $1st_run = $null -eq [pipEnv]::data
    if ($1st_run) {
      [pipEnv]::req = [pipEnv]::get_default_requirements(); $r = [pipEnv]::req; !$r.resolved ? $r.Resolve() : $null
      [pipEnv].PsObject.Properties.Add([PsNoteproperty]::new('data', [PsRecord]::new()))
      [pipEnv].data.set(@{
          SelectedVersion = [version]$(python --version).Split(" ").Where({ $_ -match [pipEnv].CONSTANTS.validversionregex })[0]
          Home            = [pipEnv]::get_work_home()
          Os              = [xcrypt]::Get_Host_Os()
        }
      )
    }
    [pipEnv].data.PsObject.Properties.Add([PsScriptproperty]::new('PythonVersions', { return [pipEnv]::get_python_versions() }, { throw [SetValueException]::new("PythonVersions is read-only") }))
    [pipEnv].session.BinPath = (Get-Command pipenv -Type Application).Source
    if ($1st_run) {
      [pipEnv]::data = ([ref][pipEnv].data).Value
    }
  }
  [void] Install() {
    & ($this.BinPath) install -q
  }
  [void] Install([string]$package) {
    & ($this.BinPath) install -q $package
  }
  [void] Upgrade() {
    pip install --user --upgrade pipenv
  }
  [void] Remove() {
    & ($this.BinPath) --rm
  }
  static hidden [version[]] get_python_versions() {
    return ((pyenv versions).Split("`n").Trim() | Select-Object @{l = "version"; e = { $l = $_; if ($l.StartsWith("*")) { $l = $l.Substring(1).TrimStart().Split(' ')[0] }; $m = $l -match [pipEnv].CONSTANTS.validversionregex; $m ? $l : "not-a-version" } } | Where-Object { $_.version -ne "not-a-version" }).version
  }
  static hidden [string] get_work_home() {
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
  static hidden [List[array]] get_default_requirements() {
    # Add default requirements here. each array contains ("packageName", "description", { Install_script })
    return @(
      ("pip", "The package installer for Python", {
        switch ([pipEnv]::data.Os) {
          'Windows' { py -m ensurepip --upgrade }
          default { python -m ensurepip --upgrade }
        }
        pip install --user --upgrade pip }
      ),
      ("pyenv", "Python version manager", {
        switch ([pipEnv]::data.Os) {
          'Windows' { Write-Warning "Pyenv does not officially support Windows and does not work in Windows outside the Windows Subsystem for Linux." }
          default { curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash }
        } }
      ),
      ("pipenv", "Python virtualenv management tool", {
        pip install pipenv --user
        $sitepackages = python -m site --user-site
        $sitepackages = [pipEnv]::data.Os.Equals('Windows') ? $sitepackages.Replace('site-packages', 'Scripts') : $sitepackages
        # add $sitepackages to $env:PATH
        $env:PATH = "$env:PATH;$sitepackages" }
      )
    )
  }
}


# .SYNOPSIS
#   python virtual environment implementation
class venv {
  [string]$Path
  [string]$CreatedAt
  [version]$PythonVersion
  [PackageManager]$PackageManager
  [Dictionary[string, DependencyInfo]]$dependencies
  static [PsRecord]$Config = @{
    CustomName       = ""
    ProjectPath      = (Resolve-Path .).Path
    SharePipcache    = $False
    RequirementsFile = "requirements.txt"
  }
  static hidden [EnvManager]$manager = [venv]::GetEnvManager("pipEnv")
  hidden [string]$__name
  venv() {}
  venv([string]$dir) {
    [void][venv]::From([IO.DirectoryInfo]::new($dir), [ref]$this)
  }
  venv([IO.DirectoryInfo]$dir) {
    [void][venv]::From($dir, [ref]$this)
  }
  static [venv] Create() {
    return [venv]::Create([IO.DirectoryInfo]::new([venv]::Config.ProjectPath))
  }
  static [venv] Create([string]$dir) {
    [ValidateNotNullOrWhiteSpace()][string]$dir = $dir
    return [venv]::Create([IO.DirectoryInfo]::new($dir))
  }
  static [venv] Create([IO.DirectoryInfo]$dir) {
    # .NOTES
    # $dir.FullName can be ProjectPath or the exact path for the venv
    # Option1: check if the venv was already created:
    if (!$dir.Exists) { throw [Argumentexception]::new("Please provide a valid path!", [DirectoryNotFoundException]::new("Directory not found: $dir")) }
    if ([venv]::IsValid($dir.FullName)) {
      return [venv]::new($dir)
    }
    $_env_paths = [pipEnv]::get_work_home() | Get-ChildItem -Directory -ea Ignore
    if ($null -ne $_env_paths) {
      $reslt = [venv]::GetEnvPath($dir.FullName)
      $reslt = ($reslt.count -eq 0) ? $null : [venv]::Create($reslt)
      return $reslt
    }
    # Option2: check in the current directory
    $reslt = $null; $_env_paths = $dir.EnumerateDirectories("*", [SearchOption]::TopDirectoryOnly).Where({ [venv]::IsValid($_.FullName) })
    if ($null -ne $_env_paths) {
      $reslt = switch ($_env_paths.count) {
        0 { $null; break }
        1 { [venv]::new($_env_paths[0].FullName); break }
        Default {
          throw [InvalidOperationException]::new("Multiple environments found for project: $($dir.BaseName)")
        }
      }
    }
    if ($null -ne $reslt) { return $reslt }
    Push-Location $dir.FullName;
    [void][venv]::SetLocalVersion()
    Write-Console "[pipEnv] " -f SlateBlue -NoNewLine; Write-Console "Creating env ... "-f LemonChiffon -NoNewLine;
    [venv]::Run(("install", "check"))
    # https://pipenv.pypa.io/en/latest/virtualenv.html#virtual-environment-name
    $usrEnvfile = [Path]::Combine($dir.FullName, ".env");
    $name = [venv]::Config.CustomName
    $name = ($name -as [version] -is [version]) ? ("{0}_{1}" -f $dir.Parent.BaseName, $name) : $name
    if (![string]::IsNullOrWhiteSpace($name)) { "PIPENV_CUSTOM_VENV_NAME=$name" >> $usrEnvfile }
    $usrEnvfile ? ($usrEnvfile | Remove-Item -Force -ea Ignore) : $null
    Pop-Location; Write-Console "Done" -f Green

    $p = [venv]::GetEnvPath($dir.FullName)
    $p = [Directory]::Exists($p) ? $p : ([Path]::Combine($dir.FullName, "env"))
    return [venv]::new($p)
  }
  static hidden [venv] From([IO.DirectoryInfo]$dir) {
    return [venv]::From($dir, [ref]([venv]::new()))
  }
  static hidden [venv] From([IO.DirectoryInfo]$dir, [ref]$o) {
    [IO.Directory]::Exists($dir.FullName) ? ($dir | Set-ItemProperty -Name Attributes -Value ([IO.FileAttributes]::Hidden)) : $null
    if (![venv]::IsValid($dir.FullName)) { [InvalidOperationException]::new("Failed to create a venv Object", [Argumentexception]::new("$dir is not a valid venv folder", $dir)) | Write-Error }
    $o.Value.PsObject.Properties.Add([Psscriptproperty]::new('Name', {
          $v = [venv]::IsValid($this.Path)
          $has_deact_command = $null -ne (Get-Command deactivate -ea Ignore);
          $this.PsObject.Properties.Add([Psscriptproperty]::new('State', [scriptblock]::Create("return [EnvState][int]$([int]$($has_deact_command -and $v))"), { throw [SetValueException]::new("State is read-only") }));
          $this.PsObject.Properties.Add([Psscriptproperty]::new('IsValid', [scriptblock]::Create("return [IO.Path]::Exists(`$this.Path) -and [bool]$([int]$v)"), { throw [SetValueException]::new("IsValid is read-only") }));
          return ($v ? $this.__name : [string]::Empty);
        }, { Param([string]$n) [string]::IsNullOrWhiteSpace("$($this.__name) ".Trim()) ? ($this.__name = $n) : $null }
      )
    )
    $o.Value.Name = $dir.Name;
    $o.Value.Path = $dir.FullName; #the exact path for the venv
    $o.Value.CreatedAt = [Datetime]::Now.ToString();
    $o.Value.PythonVersion = [pipEnv].data.SelectedVersion;
    if (![string]::IsNullOrWhiteSpace($o.Value.Name) -and $o.Value.IsValid) {
      $venvconfig = Read-Env -File ([IO.Path]::Combine($dir.FullName, 'pyvenv.cfg'));
      $c = @{}; $venvconfig.Name.ForEach({ $n = $_; $c[$n] = $venvconfig.Where({ $_.Name -eq $n }).value });
      [venv]::Config.Set($c)
    }
    return $o.Value
  }
  static [Object[]] Run([string[]]$commands) {
    return [venv]::manager.Run($commands)
  }
  static [EnvManager] GetEnvManager([string]$name) {
    $m = switch ($name) {
      "pipenv" {
        [pipEnv].session ? ([pipEnv].session) : ([pipEnv]::Create())
      }
      Default {
        throw [Argumentexception]::new("Unknown environment manager: $name")
      }
    }
    return $m
  }
  static [Object[]] SetLocalVersion() {
    return [venv]::SetLocalVersion([Path]::Combine((Resolve-Path .).Path, ".python-version"))
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
  static [string] GetActivationScript() {
    return [venv]::GetActivationScript((Resolve-Path .).Path)
  }
  static [string] GetActivationScript([string]$ProjectPath) {
    $e = [venv]::Create($ProjectPath)
    return ([venv]::IsValid($e.Path) ? ([IO.Path]::Combine($e.Path, 'bin', 'activate.ps1')) : '')
  }
  static [string] GetEnvPath() {
    return [venv]::GetEnvPath([venv]::Config.ProjectPath)
  }
  static [string] GetEnvPath([string]$ProjectPath) {
    $reslt = $null; $_env_paths = [pipEnv]::get_work_home() | Get-ChildItem -Directory -ea Ignore
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
  [Object[]] verify() { return [venv]::Run("verify") }
  [Object[]] upgrade() { return [venv]::Run("upgrade") }
  [Object[]] sync() { return [venv]::Run("sync") }
  [Object[]] lock() { return [venv]::Run("lock") }
  [Object[]] install() { return [venv]::Run("install") }
  [void] Activate() {
    $spath = Resolve-Path ([IO.Path]::Combine($this.Path, 'bin', 'activate.ps1')) -ea Ignore
    if (![IO.File]::Exists($spath)) { throw [FileNotFoundException]::new("env activation script not found: $spath") }
    &$spath
  }
  [void] Delete() {
    $this.Path | Remove-Item -Force -Recurse -Verbose:$false -ea Ignore
  }
}

#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [InstallRequirements],
  [DependencyInfo],
  [Requirement],
  [EnvState],
  [pipEnv],
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
