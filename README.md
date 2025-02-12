# [venv](https://www.powershellgallery.com/packages/pipEnv)

A python virtual environment manager using pipenv.

Uses: [pipenv.pypa.io](https://pipenv.pypa.io/en/latest/)

Has functions to install, run, test and uninstall pipenv in PowerShell.

> Why not use pipenv directly?

**tldr**: Command not work => I get frustated => I build patch thing.

**ex**: The command `pipenv shell` does not always work in Powershell. But this
wrapper was created to deal with that, not manually by me everytime.

## usage

```PowerShell
Install-Module pipEnv
```

then

```PowerShell
Import-Module pipEnv
$e = New-pipEnv .
$e.Activate()
# do stuff:
deactivate
```

hint: run `deactivate` to return

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
