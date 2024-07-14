Param(
  [String]$GitHubOrganisationName,
  [String]$GitHubRepositoryName,
  [ValidateLength(4, 17)]
  [String]$ProjectName
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$checksScript = Join-Path $scriptRoot "checks.ps1"
$environmentsFile = Join-Path $scriptRoot "environments.json"

try {
    . $checksScript
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Setup script terminated due to the checks failure." -ForegroundColor Red
    exit 1
}

$MissingParameterValues = $false

if (-not $GitHubOrganisationName) {
  $ownerJson = gh repo view --json owner 2>$null | ConvertFrom-Json
  if ($ownerJson -and $ownerJson.owner -and $ownerJson.owner.login) {
    $GitHubOrganisationName = $ownerJson.owner.login
  }
  else {
    $MissingParameterValues = $true
  }
}

if (-not $GitHubRepositoryName) {
  $GitHubRepositoryName = $(gh repo view --json name -q '.name' 2> $null)
  if (-not $GitHubRepositoryName) { $MissingParameterValues = $true }
}

if (-not $ProjectName) {
  if ($GitHubRepositoryName) {
    $ProjectName = $GitHubRepositoryName
  }

  if (-not $ProjectName) { $MissingParameterValues = $true }
}

$repoUrl = "https://github.com/$GitHubOrganisationName/$GitHubRepositoryName"

$environments = Get-Content -Raw -Path $environmentsFile | ConvertFrom-Json

$ParametersTableData = @{
  "GitHubOrganisationName" = $GitHubOrganisationName
  "GitHubRepositoryName"   = $GitHubRepositoryName
  "ProjectName"            = $ProjectName
}

Write-Host
Write-Host "This script automates the setup of environments, resources, and credentials for a project hosted on GitHub. It configures environment-specific variables and secrets in the GitHub repository. The script leverages the GitHub CLI and GitHub APIs to perform these tasks. It aims to streamline the process of setting up and configuring development, staging, and production environments for the project."
Write-Host
Write-Host "Parameters:" -ForegroundColor Green
$ParametersTableData | Format-Table -AutoSize

if ($MissingParameterValues) {
  Write-Host "Script execution cancelled. Missing parameter values." -ForegroundColor Red
  exit 1
}

$EnvironmentTableData = foreach ($environment in $environments.PSObject.Properties) {
  [PSCustomObject]@{
    Abbreviation = $environment.Name
    Name         = $environment.Value
  }
} 

Write-Host "Environments:" -ForegroundColor Green
$EnvironmentTableData | Select-Object Name, Abbreviation | Format-Table -AutoSize
Write-Host

Write-Host "Warning: Running this script will perform various operations in your GitHub repository. Ensure that you have the necessary permissions and understand the consequences. " -ForegroundColor Red
Write-Host
Write-Host "Disclaimer: Use this script at your own risk. The author and contributors are not responsible for any loss of data or unintended consequences resulting from running this script." -ForegroundColor Yellow
Write-Host

$confirmation = Read-Host "Do you want to continue? (y/N)"

if ($confirmation -ne "y") {
  Write-Host "Script execution cancelled." -ForegroundColor Red
  return
}

Write-Host

function CreateEnvironment {
  param (
    $environmentName
  )
  
  $token = gh auth token
  $header = @{"Authorization" = "token $token" }
  $contentType = "application/json"

  $uri = "https://api.github.com/repos/$GitHubOrganisationName/$GitHubRepositoryName/environments/$environmentName"
  Invoke-WebRequest -Method PUT -Header $header -ContentType $contentType -Uri $uri
}

function GenerateRandomPassword {
  param (
    [int]$Length = 16
  )

  $ValidChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#^_-+=?<>|~".ToCharArray()
  $Password = -join ((Get-Random -Count $Length -InputObject $ValidChars) | Get-Random -Count $Length)

  return $Password
}

function SetVariables() {    
  gh variable set PROJECT_NAME --body $ProjectName --repo $repoUrl
}

function SetEnvironmentVariablesAndSecrets {
  param(
    $environmentAbbr,
    $environmentName
  )
  
  gh variable set PROJECT_NAME --body "$ProjectName" --env $environmentName --repo $repoUrl
}

SetVariables

foreach ($environment in $environments.PSObject.Properties) {
  $environmentAbbr = $environment.Name
  $environmentName = $environment.Value
  
  CreateEnvironment $environmentName
  SetEnvironmentVariablesAndSecrets $environmentAbbr $environmentName
}

Write-Host "✅ Done"
