# Monitoring and operations

## Signals and dashboard

Prometheus scrapes Spring Boot Actuator at `/actuator/prometheus`, Node Exporter for host metrics, and cAdvisor for container metrics every 15 seconds. Grafana provisions the **Todo Summary Assistant** dashboard at startup.

| Signal | Why it matters |
| --- | --- |
| HTTP request rate | Shows traffic changes and whether the service is receiving requests. |
| HTTP 5xx rate | Detects failed API requests; distinguish application faults from client 4xx responses. |
| p95 HTTP latency | Highlights user-visible slowdowns that averages can hide. |
| Host CPU, available memory, and root filesystem usage | Finds resource saturation and imminent disk exhaustion. |
| Container uptime and start-time resets over 24 hours | Identifies restarts and unstable deployments. |
| Backend scrape/health status | Detects an unreachable service independently of frontend availability. |

Prometheus alert rules are in `monitoring/alert-rules.yml`. They alert on an unavailable backend, a sustained 5xx rate above 5%, CPU above 90%, and less than 10% free root-disk space. The rules include `for` windows to suppress brief spikes. Configure an Alertmanager receiver/contact point for delivery in a real environment; the checked-in rules define detection but do not send notifications by themselves.

## Logs

Prioritize Spring Boot startup errors, database connection/pool failures, API exceptions, and container restart/health-check events. Inspect Nginx access/error logs for routing and browser/API failures, Docker daemon and SSM agent logs for host/deployment faults, and RDS events/CloudWatch logs for database faults. Keep credentials and request payloads (especially todo content) out of logs. Use centralized, access-controlled, retained logs in production; local Compose logs are ephemeral.

## Alerting and noise control

Page for sustained service unavailability or resource exhaustion with imminent user impact. Notify at a lower urgency for a sustained high server-error rate. Do not alert on individual 4xx responses, one-off latency spikes, every short CPU burst, or every normal container start; use ratios, aggregation, and `for` durations. Alerts should have an owner, an actionable runbook, and tested notification routing.

## Early detection and operations

The health endpoint is used by Docker health checks and deployment verification. CI waits for both new containers to become healthy and returns failure on timeout; the EC2 deploy script restores the previous image references when a release fails its health check. Review dashboard trends and alert history after releases, verify RDS connectivity and backup status, and periodically test restore/rollback procedures. Prometheus, Grafana, Node Exporter, and cAdvisor are included in local Compose for repeatable demonstration.

The Compose monitoring ports and local Grafana credentials are for development only. In AWS, keep Prometheus/Grafana private or behind authenticated access, restrict security groups, configure persistent storage/retention, and provision Alertmanager/Grafana contact points. The local Compose setup's Node Exporter and cAdvisor expose host/container signals for demonstration and require privileged host access; apply the least permissions and isolation needed in production.
