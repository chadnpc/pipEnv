## [**pipEnv**](https://www.powershellgallery.com/packages/pipEnv).

A module for **python virtual environment** management using [pipenv](https://pipenv.pypa.io/en/latest/).


## usage

```PowerShell
Install-Module pipEnv
```

then

```PowerShell
Import-Module pipEnv
$e = New-venv .
$e.Activate()
# do stuff:
deactivate
```

hint: run `deactivate` to return

### Benefits

- Automations. Ex: The module auto installs it's own requirements

- Using pipenv directly?

  I rarely use it / This is for convenience.

  tldr: Command not work => I get frustated => I build wrapper-patch thing.

  Ex: The command `pipenv shell` does not always work in Powershell.

  This wrapper created to deal with those kinds of problems, not manually by me everytime.

## status

- [x] wrapper. 60% complete

- [x] utilities

- [ ] tests

- [![GitHub Release Date](https://img.shields.io/github/release/chadnpc/pipEnv.svg)](https://github.com/chadnpc/pipEnv/releases)

## contributing

Pull requests are welcome.

```PowerShell
git clone https://github.com/chadnpc/pipEnv
cd pipEnv
git remote add upstream https://github.com/yourUserName/pipEnv.git
git fetch upstream
# make your changes... then
# Run build.ps1 -Task Test
# If everything passes:
git add .
git commit -m 'made cool changes to abc 😊'
git push origin main
```

## license

This project is licensed under the [WTFPL License](LICENSE).
