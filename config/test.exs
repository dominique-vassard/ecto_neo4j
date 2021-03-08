use Mix.Config

config :bolt_sips, Bolt,
  hostname: 'localhost',
  basic_auth: [username: "neo4j", password: "test"],
  port: 7687,
  pool_size: 5,
  max_overflow: 1

config :ecto_neo4j, Ecto.Adapters.Neo4j,
  chunk_size: 10_000,
  batch: false,
  bolt_role: :direct
