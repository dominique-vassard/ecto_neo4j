# Ecto adapter for Neo4j graph database

[![Build Status](https://travis-ci.org/dominique-vassard/ecto_neo4j.svg?branch=master)](https://travis-ci.org/dominique-vassard/ecto_neo4j)

**WARNING: WIP. This project is not production-ready (yet)**

# Goal
EctoNeo4j is designed to ease the use of Neo4j in elixir and provides an adapter for Ecto.  
It allows to works with `schema` and to use the classic `Ecto.Repo` functions.  

BUT, as `Ecto.Schema` is relational-database oriented and Neo4j is a graph database, there is some limitations:
`join`, `assoc`, `preload` related features are not available in Neo4j because they don't make sense in graph model.

## Installation
Add `ecto` and `ecto_neo4j` to your dependencies:  
```elixir
def deps do
  [
    {:ecto, "~> 3.1},
    {:ecto_neo4j, "~> 0.2.0"}
  ]
end
```

# Configuration
`ecto` configuration is quite the same:
```elixir
# In your config/config.exs file
config :my_app, ecto_repos: [Sample.Repo]

# In your application code
defmodule Sample.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: EctoNeo4j.Adapter
end
```

Now add your database config (see bolt_sips for more information):

```elixir
config :bolt_sips, Bolt,
  hostname: 'localhost',
  basic_auth: [username: "user", password: "pass"],
  port: 7687,
  pool_size: 5,
  max_overflow: 1
```

And now, you're good to go!

# Warning: about ids...
As you may know, it is strongly recommended to NOT rely on Neo4j internal ids, as they can be reaffected.  
With Ecto.Schema, `id` can be managed automatically. `EctoNeo4j` allows to not change this way of working by
using a property called `nodeId` on created/updated nodes. This proprety is automically converted into `id` when 
retrieving data from database.  

# Supported features
  - Compatible `Ecto.Repo` API.
  - Raw cypher queries via `EctoNeo4j.Adapter.query(cql, params, options)` and `query!` 

# Unsupported features
  - `join`, `assoc`, `preload`
  - migration
  - Upsert via `Repo.insert`, use `Repo.update` instead
  - `prefix`
  - Optimistic locking  

# TODO
[ ] Split test to allow bolt v1 testing  
[ ] Support prefix? (is there any use case for this?)  
[ ] Support optimistic locking?  
[ ] Support migration (only: index creation, drop, rename, alter column name) - migration is supposed to support large amount of data (use batch :))  
[ ] Support insert select?  
[ ] Support delete with returning?  
[ ] Support map update?  
[ ] Implement a merge?  

# Can I contribute?  
Yes, you can! Please, do!  
Just fork, commit and submit pull requests!