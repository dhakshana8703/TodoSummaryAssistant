# Todo Summary Assistant

Full-stack Todo application with a Spring Boot/MySQL API and React UI. This repository also contains a Docker-based local stack, CI/CD workflow, AWS deployment guidance, and Prometheus/Grafana monitoring.

## Requirements and assumptions

- Java 17+ and Maven 3.9+ for a local backend run; Node.js 20+ and npm for the frontend.
- Docker Engine with the Compose plugin for the reproducible local stack.
- Production persistence is MySQL, intended to run in private Amazon RDS. The Compose MySQL service is for local demonstration only.
- Cohere and Slack credentials are optional for CRUD and startup. Configure them only to exercise summary generation and Slack delivery.
- AWS resources and external credentials are not included or provisioned by this repository.

## Run locally with Docker Compose

On a normal Docker host, the full stack can be started with:

```bash
cp .env.example .env
docker compose up --build -d
docker compose ps
```

**Codespaces note:** this workspace's Docker bridge cannot route between containers. Use the [Codespaces fallback](#codespaces-fallback-if-compose-networking-is-blocked) below here instead of starting the full Compose stack.

Open:

- App: <http://localhost:3000>
- Backend health: <http://localhost:8080/actuator/health>
- Prometheus: <http://localhost:9090>
- Grafana: <http://localhost:3001> (credentials are in `.env`)

The Compose stack builds and runs both application images, a disposable local MySQL service, Prometheus, Grafana, Node Exporter, and cAdvisor. Local example passwords in `.env.example` are for development only; never reuse them in AWS. Stop with `docker compose down`; retain local database/monitoring volumes unless you intentionally want to discard them.

## Run without Docker

Start a MySQL 8 server and create the `todo_db` database, then configure the backend environment:

```bash
export SPRING_DATASOURCE_URL='jdbc:mysql://localhost:3306/todo_db?createDatabaseIfNotExist=true'
export SPRING_DATASOURCE_USERNAME='your-local-user'
export SPRING_DATASOURCE_PASSWORD='your-local-password'
export COHERE_API_KEY=''
export SLACK_WEBHOOK_URL=''
cd Backend/todo-summary-assistant
mvn spring-boot:run
```

In another terminal:

```bash
cd Frontend/todo
npm ci
npm start
```

The frontend defaults to the relative `/api/todos` URL. The React development server proxies `/api/` to the local backend, and the included production Nginx configuration proxies the same path to the backend container. Override `REACT_APP_API_BASE_URL` at frontend build time only if the frontend and API are hosted on different public origins.

### Codespaces fallback if Compose networking is blocked

Some hosted Docker environments cannot route traffic between bridge-network containers. If Compose shows MySQL healthy but the backend reports a connection timeout, run only the local MySQL service in Docker (its port is bound to `127.0.0.1`, not a public interface), then run Spring Boot and React directly in the Codespace:

```bash
cp .env.example .env  # Skip if your local .env is already configured.
docker compose up -d mysql
```

In terminal 1:

```bash
set -a
. ./.env
set +a
export SPRING_DATASOURCE_URL='jdbc:mysql://127.0.0.1:3306/todo_db?createDatabaseIfNotExist=true'
cd Backend/todo-summary-assistant
mvn spring-boot:run
```

In terminal 2:

```bash
cd Frontend/todo
npm start
```

Use the Codespaces forwarded port for 3000. Keep backend port 8080 forwarded for the frontend API; both processes run directly in the Codespace, so they can reach the loopback-published MySQL port. The Grafana/Prometheus containers can still be run separately with `docker compose up -d prometheus grafana node-exporter cadvisor`; with bridge networking blocked, their application/host-exporter scrape targets may remain unavailable.

## Configuration

| Variable | Purpose |
| --- | --- |
| `SPRING_DATASOURCE_URL` | JDBC URL; Compose uses `mysql` as the host, production uses the private RDS endpoint. |
| `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` | Database credentials. |
| `COHERE_API_KEY` | Optional key for pending-task summarization. |
| `SLACK_WEBHOOK_URL` | Optional incoming webhook for summary delivery. |
| `CORS_ALLOWED_ORIGIN` | Single permitted browser origin (Compose default `http://localhost:3000`). |
| `REACT_APP_API_BASE_URL` | Frontend API URL, including `/api/todos`; defaults to localhost for local development. |
| `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` | Local Grafana credentials; change the example password before use. |

Backend settings are read from environment variables; there are no production credentials in source. Use a secret store, not committed files, for non-local secrets. The test profile uses an in-memory H2 database and does not require MySQL.

## CI/CD and AWS

`.github/workflows/ci-cd.yml` tests the backend and builds the frontend on pushes and pull requests. It builds both Docker images on every trigger, publishes SHA-tagged images to Amazon ECR on pushes to `main` when the required AWS settings are present, and deploys that immutable SHA to EC2 through AWS Systems Manager. The deployment waits for both container health checks and attempts to restore the previous images if the new deployment fails. If AWS settings are missing, the workflow still validates both image builds and reports that publishing/deployment were skipped; it does not pretend that a cloud deployment happened.

Before enabling deployment, create the AWS resources and GitHub repository variables/secrets described in [aws/aws-setup.md](aws/aws-setup.md). The workflow assumes GitHub Actions OIDC, an EC2 instance with an SSM/ECR/Secrets Manager IAM role, two ECR repositories, and an application JSON secret in Secrets Manager. CI only runs a deployment when those resources are provisioned. No AWS deployment was performed while preparing this repository.

## Monitoring

Prometheus scrapes Spring Actuator/Prometheus metrics, Node Exporter, and cAdvisor. Grafana provisions a dashboard for application traffic/errors/latency, host CPU/memory/disk, and container uptime/restarts. Prometheus alert rules cover backend availability, elevated 5xx rate, high CPU, and low disk. See [MONITORING_AND_OPERATIONS.md](MONITORING_AND_OPERATIONS.md).

## Operational procedures

- Failure and rollback responses: [FAILURE_AND_ROLLBACK.md](FAILURE_AND_ROLLBACK.md)
- AWS networking, IAM, and setup: [aws/aws-setup.md](aws/aws-setup.md)
- Monitoring and alerting approach: [MONITORING_AND_OPERATIONS.md](MONITORING_AND_OPERATIONS.md)

## DevOps-specific application changes

The application behavior and data model were not changed. For DevOps enablement, the backend now exposes Actuator health and Prometheus metrics; the test profile uses H2 so CI does not depend on MySQL; CORS and the frontend API base URL are configurable; and both application images run as non-root users.
