#Requires -RunAsAdministrator

[CmdletBinding()]
param (
  [Parameter(ValueFromPipelineByPropertyName)]
  [ValidateNotNullOrEmpty()]
  [string] $AgentConfig = "C:\Program Files\Grafana Agent\agent-config.yaml",

  [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
  [ValidateNotNullOrEmpty()]
  [string] $StackName,

  [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
  [ValidateNotNullOrEmpty()]
  [string] $GrafanaInstanceApiKey,

  [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
  [ValidateNotNullOrEmpty()]
  [string] $GrafanaCloudApiKey,

  [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
  [ValidateNotNullOrEmpty()]
  [int] $PrometheusId,

  [Parameter(ValueFromPipelineByPropertyName)]
  [ValidateNotNullOrEmpty()]
  [string] $StackRegion = "us-central1",

  [Parameter(ValueFromPipelineByPropertyName)]
  [string] $PrometheusDefaultKeepString = "(.*)",

  [Parameter(ValueFromPipelineByPropertyName)]
  [string] $AdditionalReplace,

  [Parameter(ValueFromPipelineByPropertyName)]
  [string] $AdditionalWith,

  [Parameter(ValueFromPipelineByPropertyName)]
  [switch] $SkipAnalyzeMetrics,

  [Parameter(ValueFromPipelineByPropertyName)]
  [switch] $SkipRestartService
)

Push-Location -Path $PSScriptRoot

if (-Not $SkipAnalyzeMetrics.IsPresent) {
  # Download mimirtool
  $DOWLOAD_URL = "https://github.com/grafana/mimir/releases/latest/download/mimirtool-windows-amd64.exe"
  $OUTPUT_FILE = ".\mimirtool-windows-amd64.exe"
  Invoke-WebRequest -Uri $DOWLOAD_URL -OutFile $OUTPUT_FILE

  # Get used metrics
  $address = "https://$StackName.grafana.net"
  & .\mimirtool-windows-amd64.exe analyze grafana --address=$address --key=$GrafanaInstanceApiKey | Out-Host

  # From used metrics, get all unused metrics we can safely drop
  $address = "https://prometheus-$StackRegion.grafana.net/api/prom"
  & .\mimirtool-windows-amd64.exe analyze prometheus --address=$address --id=$PrometheusId --key=$GrafanaCloudApiKey --log.level=debug | Out-Host
}

if (-Not $SkipRestartService.IsPresent) {
  # Stop Grafana Agent service
  Stop-Service -Name "Grafana Agent" -NoWait -Force -PassThru -ErrorAction Ignore
  Start-Sleep -Seconds 30
  & taskkill /f /im agent-windows-amd64.exe
}

#region integrations/windows_exporter
$replace = @"
  prometheus_remote_write:
"@
$with = @"

  windows_exporter:
    enabled: true
  prometheus_remote_write:
"@
$replaceRegex = [regex]::Escape($replace) -replace '((\\ )|(\\t))+', '\s+' -replace '(\\r)?\\n', '\r?\n'
(Get-Content -Raw -Path $AgentConfig) -replace $replaceRegex, $with | Set-Content $AgentConfig
#endregion

#region integrations/prometheus_remote_write/write_relabel_configs
# Create Prometheus metrics keep string
if ($SkipAnalyzeMetrics.IsPresent) {
  $keepString = $PrometheusDefaultKeepString
}
else {
  $keep = (Get-Content -Path .\prometheus-metrics.json | ConvertFrom-Json -Depth 10).in_use_metric_counts.metric | Sort-Object
  $keepString = ""
  $keep | ForEach-Object { $keepString += "$_|" }
  $keepString = $keepString -replace "\|$"
}
Write-Host "Prometheus metrics keep string: $keepString"
# Add to config
$replace = @"
    url: https://prometheus-$StackRegion.grafana.net/api/prom/push
logs:
"@
$with = @"

    url: https://prometheus-$StackRegion.grafana.net/api/prom/push
    write_relabel_configs:
    - source_labels: [__name__]
      regex: $keepString
      action: keep
logs:
"@
$replaceRegex = [regex]::Escape($replace) -replace '((\\ )|(\\t))+', '\s+' -replace '(\\r)?\\n', '\r?\n'
(Get-Content -Raw -Path $AgentConfig) -replace $replaceRegex, $with | Set-Content $AgentConfig
#endregion

#region logs/configs/clients/scrape_configs
$replace = @"
      filename: /tmp/positions.yaml
    scrape_configs:
"@
$with = @"

      filename: /tmp/positions.yaml
    scrape_configs:
    - job_name: integrations/windows-exporter-application
      windows_events:
        use_incoming_timestamp: true
        bookmark_path: "./bookmark-application.xml"
        eventlog_name: "Application"
        xpath_query: '*'
        labels:
          job: integrations/windows_exporter
      relabel_configs:
        - source_labels: ['computer']
          target_label: 'agent_hostname'
      pipeline_stages:
        - json:
            expressions:
              source: source
        - labels:
            source:
    - job_name: integrations/windows-exporter-system
      windows_events:
        use_incoming_timestamp: true
        bookmark_path: "./bookmark-system.xml"
        eventlog_name: "System"
        xpath_query: '*'
        labels:
          job: integrations/windows_exporter
      relabel_configs:
        - source_labels: ['computer']
          target_label: 'agent_hostname'
      pipeline_stages:
        - json:
            expressions:
              source: source
        - labels:
            source:
"@
$replaceRegex = [regex]::Escape($replace) -replace '((\\ )|(\\t))+', '\s+' -replace '(\\r)?\\n', '\r?\n'
(Get-Content -Raw -Path $AgentConfig) -replace $replaceRegex, $with | Set-Content $AgentConfig
#endregion

#region Additional replace
if ($AdditionalReplace -And $AdditionalWith) {
  $replaceRegex = [regex]::Escape($AdditionalReplace) -replace '((\\ )|(\\t))+', '\s+' -replace '(\\r)?\\n', '\r?\n'
  (Get-Content -Raw -Path $AgentConfig) -replace $replaceRegex, $AdditionalWith | Set-Content $AgentConfig
}
#endregion

if (-Not $SkipRestartService.IsPresent) {
  # Re-start Grafana Agent service
  Start-Service -Name "Grafana Agent" -PassThru
  Get-Service "Grafana Agent"
}

Pop-Location
