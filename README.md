# Grafana Agent config

> **Note**
>
> The setup script in this repo includes reducing metrics usage as documented here: [Analyze and reduce metrics usage with Grafana Mimirtool](https://grafana.com/docs/grafana-cloud/billing-and-usage/control-prometheus-metrics-usage/usage-analysis-mimirtool/)

## Install the agent

1. Install Grafana Agent (`https://<stack name>.grafana.net/a/grafana-easystart-app/windows-exporter`) (see tab **Configuration Details**).
2. Skip manually modifying the agent configuration and instead run `grafana-agent-config.ps1` in a PowerShell session with elevated rights (_Run as Administrator_):

   ```powershell
   .\grafana-agent-config.ps1 -StackName "<Grafana Cloud stack name>" -GrafanaInstanceApiKey "<api-key>" -GrafanaCloudApiKey "<api-key>" -PrometheusId <user-id>
   ```

   _Note: `GrafanaInstanceApiKey` refers to [this](https://grafana.com/docs/grafana/latest/administration/service-accounts/#add-a-token-to-a-service-account-in-grafana), `GrafanaCloudApiKey` to [this](https://grafana.com/docs/grafana-cloud/reference/create-api-key/#create-a-grafana-cloud-api-key), and `PrometheusId` to the [Prometheus instance ID](https://grafana.com/docs/grafana-cloud/billing-and-usage/control-prometheus-metrics-usage/usage-analysis-mimirtool/#step-2-identify-unused-active-metrics)._

3. Verify that the file `C:\Program Files\Grafana Agent\agent-config.yaml` has been properly updated by comparing it to `agent-config-example.yaml`
4. Done!

## Logs

When Grafana Agent runs as a service, logs are written to the *Windows Event Log*. Open the *Event Viewer*, navigate to **Windows > Applications**, and filter on event source `Grafana Agent`.
