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
$e.Dispose()
#same as: deactivate but also deletes the venv directory
```

`Automation examples`

- On First time usage, The module auto installs all requirements:

  https://github.com/user-attachments/assets/171f6913-9119-4582-b51a-d865cd90a0e3


- every next time, its faster:

  https://github.com/user-attachments/assets/0fb91653-cdf0-4d21-9d1f-edcf91adeee6

### faqs

- why not just use pipenv directly?

  I rarely use it / This is for convenience.

  tldr: Command not work => I get frustated => I build wrapper-patch thing.

  This wrapper created to deal with those kinds of problems, so I dont have to deal with them manually everytime.

  Ex: The command `pipenv shell` does not always work in Powershell.


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
