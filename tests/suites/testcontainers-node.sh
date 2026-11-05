# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "Testcontainers (Node)"
check_agent "PostgreSQL in Testcontainers from Node" '
  d=/workspace/tc-node && mkdir -p $d && cd $d && npm init -y >/dev/null &&
  npm install testcontainers @testcontainers/postgresql pg >/dev/null 2>&1 &&
  cat > test.mjs <<EOF
import { PostgreSqlContainer } from "@testcontainers/postgresql";
import pg from "pg";
const container = await new PostgreSqlContainer("postgres:17-alpine").start();
const client = new pg.Client({ connectionString: container.getConnectionUri() });
await client.connect();
const { rows } = await client.query("select 40 + 2 as answer");
await client.end();
await container.stop();
if (rows[0].answer !== 42) throw new Error("unexpected " + JSON.stringify(rows));
console.log("answer", rows[0].answer);
EOF
  node test.mjs'
