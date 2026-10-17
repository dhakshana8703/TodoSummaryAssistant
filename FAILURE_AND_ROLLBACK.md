# Failure and rollback procedures

## 1. A faulty version is deployed. How do you roll back?

Each CI deployment uses an immutable commit-SHA image tag. The EC2 deployment script records the currently running image references before replacement. If the new backend or frontend does not become healthy, it removes the failed containers and starts the previous images with the same secret values. The workflow fails rather than reporting a successful deployment. For a manual rollback, identify the last known-good SHA in the GitHub Actions run history and redeploy that SHA through the approved SSM deployment procedure; do not rebuild a mutable `latest` tag.

Database schema changes must remain backward-compatible with both the current and immediately previous application image. Take an RDS snapshot before any intentional schema migration that cannot be rolled back by the application image alone.

## 2. The application crashes after deployment. What happens?

Docker uses `restart: unless-stopped` to restart an exited container. Docker health checks mark an unhealthy process, and Prometheus alerts if the backend scrape is down. Restart loops or failed health checks are investigated using `docker ps`, `docker inspect`, and `docker logs` on EC2, plus the SSM command output and CloudWatch/SSM agent logs. Restart policy is recovery assistance, not a fix; roll back if the incident followed a release.

## 3. The CI/CD tool is unavailable. Can you still deploy?

Yes. The GitHub Actions workflow is the normal deployment path. An authorized operator can use AWS Systems Manager Run Command from the AWS console or CLI to pull a previously published ECR SHA image and run the checked-in deployment procedure on the managed EC2 instance. The EC2 instance role supplies ECR and Secrets Manager access; do not copy credentials into a shell history or repository. If ECR or AWS APIs are also unavailable, a deployment cannot proceed until service is restored.

## 4. Secrets are leaked. What steps do you take?

Revoke/rotate the affected database password, Cohere key, Slack webhook, or AWS credential immediately; update Secrets Manager and redeploy. Invalidate any exposed GitHub token/role trust, review CloudTrail, GitHub audit logs, and access logs for misuse, and check repository history and build artifacts. Remove the leaked value from active branches and history according to incident policy, but treat deletion as insufficient—the credential must still be rotated. Notify stakeholders and document the incident.

## 5. The EC2 instance fails. How do you recover?

Recreate or replace the instance from the approved AMI/launch template in the correct VPC and private subnets, attach the least-privilege instance role and security groups, and register it with Systems Manager. Reinstall/enable Docker and the SSM agent through the bootstrap process. The GitHub OIDC role can then run the last known-good image deployment from ECR using the application secret in Secrets Manager. Use an ALB/DNS health check to route traffic only to a healthy replacement. Persistent application state belongs in RDS, not the instance filesystem.

## 6. RDS becomes unavailable. What is the impact and recovery plan?

CRUD operations and any summarization request that first reads pending todos will fail while the database is unavailable. The API returns an error; the frontend displays its existing failure notification. Investigate RDS events, CloudWatch database metrics, network/security-group changes, and connectivity from the EC2 security group. For transient problems, restore connectivity or fail over to the standby when using Multi-AZ. For data loss/corruption, restore the latest automated backup or point-in-time recovery to a new instance, validate it, then update the secret's JDBC endpoint and redeploy/restart the backend. Keep automated backups and snapshots according to the required recovery-point and retention objectives; test restores periodically.
