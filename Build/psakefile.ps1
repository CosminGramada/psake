Include ".\helpers.ps1"

Properties {
	#Text constants
	$testMessage = 'Executed Test!'
	$compileMessage = 'Executed Compile!'
	$cleanMessage = 'Executed Clean!'

	#Solution and output directories
	$solutionDirectory = (Get-Item $solutionFile).DirectoryName
	$outputDirectory = "$solutionDirectory\.build"
	$tempOutputDirectory = "$solutionDirectory\temp"

	#Test results
	$testResultsDirectory = "$outputDirectory\TestResults"

	$packagesPath = "$solutionDirectory\packages"
	$NUnitExe = (Find-PackagePath $packagesPath "NUnit.ConsoleRunner") + "\Tools\nunit3-console.exe"

	#MSBuild parameters
	$buildConfiguration = "Release"
	$buildPlatform = "Any CPU"
}

FormatTaskName "`r`n`r`n`r`n========== Executing {0} Task =========="

task default -depends Test

task Init `
			-description "Initializes the build by removing previous artifacts and creating output directories" `
			-requiredVariables outputDirectory, tempOutputDirectory	`
{
	Assert -conditionToCheck ("Debug", "Release" -contains $buildConfiguration) `
			-failureMessage "Invalid build configuration '$buildConfiguration'. Valid values are 'Debug' or 'Release'."
	Assert -conditionToCheck ("x86", "x64", "Any CPU" -contains $buildPlatform) `
			-failureMessage "Invalid build platform '$buildPlatform'. Valid values are 'x86', 'x64', or 'Any CPU'"

	#Check that all tools are available
	Write-Host "Checking that all required tools are available."

	Assert (Test-Path $NUnitExe) "Nunit Console could not be found"

	#remove previous build results
	if(Test-Path $outputDirectory)
	{
		Write-Host "Removing output directory located at $outputDirectory"
		Remove-Item $outputDirectory -Force -Recurse
	}
	if(Test-Path $tempOutputDirectory)
	{
		Write-Host "Removing temporary output directory located at $tempOutputDirectory"
		Remove-Item $tempOutputDirectory -Force -Recurse
	}

	Write-Host "Creating output directory located at $outputDirectory"
	New-Item $outputDirectory -ItemType Directory | Out-Null

	Write-Host "Creating temporary output directory located at $tempOutputDirectory"
	New-Item $tempOutputDirectory -ItemType Directory | Out-Null
}


task Clean `
			-description "Remove temporary files" `
{
	Write-Host $cleanMessage
}


#Restore and Build solution
task Compile `
			-depends Init `
			-description "Compile the code" `
			-requiredVariables solutionFile, buildConfiguration, buildPlatform, tempOutputDirectory `
{
	Write-Host "Performing dotnet restore"
	Exec {
		dotnet restore $solutionFile
	}
	Write-Host "Building the solution"
	Exec {
		#& "C:\BuildTools\MSBuild\15.0\Bin\msbuild.exe" $solutionFile `
		& msbuild $solutionFile `
			"/p:Configuration=$buildConfiguration;Platform=$buildPlatform;OutDir=$tempOutputDirectory"
	}
	
}

#Run tests
task Test `
			-depends Compile, Clean `
			-description "Run unit tests" `
{
	#Create the test results directory if needed
	if (!(Test-Path $testResultsDirectory))
	{
		Write-Host "Creating test results directory located at $testResultsDirectory"
		mkdir $testResultsDirectory | Out-Null
	}

	Write-Host $testResultsDirectory

	$dll = "$tempOutputDirectory\WebApp.Tests.dll"

	Exec {
		&$NUnitExe $dll --work=$testResultsDirectory }
}