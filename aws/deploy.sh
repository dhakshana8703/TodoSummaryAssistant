set -eu

registry="${IMAGE_PREFIX%%/*}"
secret_json="$(aws secretsmanager get-secret-value \
  --secret-id "$APP_SECRET_ARN" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)"

secret_value() {
  printf '%s' "$secret_json" | jq -r --arg name "$1" '.[$name] // ""'
}

db_url="$(secret_value SPRING_DATASOURCE_URL)"
db_username="$(secret_value SPRING_DATASOURCE_USERNAME)"
db_password="$(secret_value SPRING_DATASOURCE_PASSWORD)"
cohere_key="$(secret_value COHERE_API_KEY)"
slack_webhook="$(secret_value SLACK_WEBHOOK_URL)"
cors_origin="$(secret_value CORS_ALLOWED_ORIGIN)"

if [ -z "$db_url" ] || [ -z "$db_username" ] || [ -z "$db_password" ] || [ -z "$cors_origin" ]; then
  echo "Required database or CORS settings are missing from the application secret."
  exit 1
fi

old_backend="$(docker inspect --format '{{.Config.Image}}' todo-backend 2>/dev/null || true)"
old_frontend="$(docker inspect --format '{{.Config.Image}}' todo-frontend 2>/dev/null || true)"

run_backend() {
  docker run -d --name todo-backend --restart unless-stopped \
    --network todo-network \
    -e SPRING_DATASOURCE_URL="$db_url" \
    -e SPRING_DATASOURCE_USERNAME="$db_username" \
    -e SPRING_DATASOURCE_PASSWORD="$db_password" \
    -e COHERE_API_KEY="$cohere_key" \
    -e SLACK_WEBHOOK_URL="$slack_webhook" \
    -e CORS_ALLOWED_ORIGIN="$cors_origin" \
    "$1"
}

run_frontend() {
  docker run -d --name todo-frontend --restart unless-stopped \
    --network todo-network --publish 80:8080 "$1"
}

wait_until_healthy() {
  name="$1"
  attempts="$2"
  delay="$3"
  for attempt in $(seq 1 "$attempts"); do
    state="$(docker inspect --format '{{.State.Health.Status}}' "$name" 2>/dev/null || true)"
    if [ "$state" = healthy ]; then return 0; fi
    if [ "$state" = unhealthy ]; then return 1; fi
    sleep "$delay"
  done
  return 1
}

rollback() {
  result=$?
  if [ "$result" -ne 0 ]; then
    docker rm -f todo-backend todo-frontend >/dev/null 2>&1 || true
    if [ -n "$old_backend" ]; then run_backend "$old_backend" || true; fi
    if [ -n "$old_frontend" ]; then run_frontend "$old_frontend" || true; fi
  fi
  exit "$result"
}
trap rollback EXIT

aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$registry"
docker network inspect todo-network >/dev/null 2>&1 || docker network create todo-network
backend_image="${IMAGE_PREFIX}-backend:${IMAGE_TAG}"
frontend_image="${IMAGE_PREFIX}-frontend:${IMAGE_TAG}"
docker pull "$backend_image"
docker pull "$frontend_image"
docker logout "$registry"

docker rm -f todo-backend todo-frontend >/dev/null 2>&1 || true
run_backend "$backend_image"
wait_until_healthy todo-backend 60 5
run_frontend "$frontend_image"
wait_until_healthy todo-frontend 30 2

trap - EXIT
