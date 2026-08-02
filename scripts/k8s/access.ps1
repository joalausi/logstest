$ErrorActionPreference = 'Stop'

$MinikubeIp = (ssh optiplex 'export PATH="$HOME/.local/bin:$PATH"; minikube --profile cluster-chronicles ip').Trim()

Write-Host 'Ingress tunnel is starting on http://127.0.0.1:8080.'
Write-Host 'Add these names to the Windows hosts file with address 127.0.0.1:'
Write-Host 'cluster-chronicles.local jenkins.cluster-chronicles.local grafana.cluster-chronicles.local prometheus.cluster-chronicles.local kibana.cluster-chronicles.local'
Write-Host 'Keep this terminal open while using the services. Press Ctrl+C to stop.'

ssh -N -L "8080:${MinikubeIp}:80" optiplex
