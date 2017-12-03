clear

# '[p]sake' is the same as 'psake' but $Error is not polluted
Remove-Module [p]sake

# find psake's path
$psakeModule = (Get-ChildItem (".\packages\psake*\tools\psake\psake.psm1")).FullName | Sort-Object $_ | select -Last 1

Import-Module $psakeModule

Invoke-psake -docs
Invoke-psake -buildFile .\Build\psakefile.ps1 `
			 -taskList CodeCoverage `
			 -framework 4.6.1 `
			 -properties @{
				 "buildConfiguration" = "Release"
				 "buildPlatform" = "Any CPU"
			 }`
			 -parameters @{
				 "solutionFile" = "..\psake.sln"
			 }`
			 -Verbose


Write-Host "`r`n`r`n===== Build exit code:" $LASTEXITCODE "====="

#Propagating the exit code so that builds actually fail when there is a problem
exit $LASTEXITCODE