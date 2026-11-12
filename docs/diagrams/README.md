# Architecture diagrams

The SVG files are editable in Inkscape. Each uses named layers, generic labels and private address ranges.

| Diagram | Platform |
| --- | --- |
| [07-private-container-apps.svg](07-private-container-apps.svg) | Container Apps: internal zone-redundant environment, six replicas, readiness-withdrawal fault |
| [06-private-aks-zone-lab.svg](06-private-aks-zone-lab.svg) | AKS: six single-node pools, internal load balancer, zone-compute fault boundary |
| [04-private-linux-app-service.svg](04-private-linux-app-service.svg) | App Service: six workers in three zones, Private Endpoint ingress, VNet Integration egress |

To export a PNG preview from this folder:

```powershell
& 'C:\Program Files\Inkscape\bin\inkscape.com' '.\07-private-container-apps.svg' '--export-type=png' '--export-filename=.\07-private-container-apps.png'
```
