# [pipEnv](https://www.powershellgallery.com/packages/pipEnv)

Python project environment manager using
[pipEnv](https://pipenv.pypa.io/en/latest/)

this is basically a pipenv wrapper installer and utilities for PowerShell.

## Usage

```PowerShell
Install-Module pipEnv
```

then

```PowerShell
Import-Module pipEnv
# do stuff here.
```

## FAQs

- Why make this wrapper? Why not use pipenv directly?

  -> Some commands do not work as expected,ex: The command `pipenv shell` does
  not always work in Powershell. so a wrapper makes sure it works.

## License

This project is licensed under the [WTFPL License](LICENSE).
