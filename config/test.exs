use Mix.Config

config :bolt_sips, Bolt,
  hostname: 'localhost',
  basic_auth: [username: "neo4j", password: "channel-dialog-classic-nerve-mexico-8725"],
  port: 7687,
  pool_size: 5,
  max_overflow: 1
