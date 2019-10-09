# Ecto adapter for Neo4j graph database

[![Build Status](https://travis-ci.org/dominique-vassard/ecto_neo4j.svg?branch=master)](https://travis-ci.org/dominique-vassard/ecto_neo4j)

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
    {:ecto, "~> 3.2"},
    {:ecto_sql, "~> 3.2"},
    {:ecto_neo4j, "~> 0.5"}
  ]
end
```
`ecto_sql` is required if you planned to use the migration features.  

# Configuration
Configuration is very similar to other adapters:
```elixir
# In your config/config.exs file
config :my_app, ecto_repos: [MyApp.Repo]

# In your env-specific config, define database config (see bolt_sips for more information):
config :my_app, MyApp.Repo,
  hostname: 'localhost',
  basic_auth: [username: "user", password: "pass"],
  port: 7687,
  pool_size: 5,
  max_overflow: 1

# In your application code
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Neo4j
end
```

# Knowns limitations 
## Ecto is designed for relational database but Neo4j is a graph database
Then not all of Ecto features are available in `EctoNeo4j`, either because they don't have their counterparts 
in Cypher Neo4j or because they don't make sense in Neo4j.  
The main feature unavailable in EctoNeo4j are those related to joins: `join`, `assoc`, `preload`, `foreign_key`, etc.  
Because of this limitations, EctoNeo4j is useful for one-node or one-label operations.   

## The special case of `id`s
As you may know, it is strongly recommended to NOT rely on Neo4j internal ids, as they can be reaffected.  
With Ecto.Schema, `id` can be managed automatically. `EctoNeo4j` allows to not change this way of working by
using a property called `nodeId` on created/updated nodes. This proprety is automatically converted into `id` when 
retrieving data from database.

# Usage
## Schema
Every schema features can be used as usual but keep in mind that all those related to joins will be irrelevants, this includes:
`has_many`, `has_one`, `belongs_to`, `many_to_many`.  
`prefix` is not available as there is no counterpart in Neo4j (yet, but maybe in version 4 with the multiple databases).

## Migration
All features work, but with some subtleties for some.  
One important thing if that all operations in migation are performed via batch. This means your migrations
will be successfully executed regardless of your database size, but it can take some time. More on batch [here](#batch).

What you need to know about migrations:
  - `create table` don't do anything as expected as Neo4j is schemaless
  - `drop table` will remove all the specified nodes and all existing indexes / constraints
  - `primary_key` will be transformed in a constraint `CONSTRAINT ON(n:label) ASSERT n.property IS UNIQUE`
  - `create index(label, properties, unique: true)` will either create an unique constraint or a node key constraint (the latter is only supported by Entreprise Edition)
  - `create index(label, properties)` will create a classic index
  - `rename table` and `rename col` will move the existing constraints and indexes from the old entity to the new one 

## DO NOT ADD A NAME TO INDEXES / CONSTRAINTS
You have the possibility to give index/constraint a name via the option of `create/3`. Don't do it.  
First, Neo4j doesn't support named indexes/constraints. Because of this "limitation", in case of uniqueness error or such, EctoNeo4j has to rebuild an index name, 
which it does considering the default index naming. 

## Repo
Most of `Ecto.Repo` features work then you are free to use the classic `Repo.insert`, `Repo.one`, `Repo.transaction` etc.  

### Unsupported features
  - `Repo.stream` (maybe soon)
  - nested transaction: they don't exist in Neo4j
  - `Repo.checkout`

### About Ecto.Query
As you expect, none all `Ecto.Query` are available, here is a list of whan can be used:
  - `distinct`
  - `dynamic`
  - `first`
  - `from` which is `MATCH` in cypher
  - `last`
  - `limit`
  - `offset` which is `SKIP` in cypher
  - `order_by`
  - `select` which is `RETURN` in cypher
  - `update` which is `MATCH... SET` in cypher 
  - `where`

For very specific operation like `CONTAINS`, `START_WITH`, etc. I encourage you to use [query fragment](https://hexdocs.pm/ecto/Ecto.Query.API.html#fragment/1)

### About `update_all` and `delete_all`
Because theses two operations can touch a large number of nodes, you can have them be performed as batch via the option `[batch: true]`.  
More on batch [here](#batch). 

## Raw cypher query
Raw cypher queries can be executed thanks to `Ecto.Adapters.Neo4j.query(cql, params, opts)` and `Ecto.Adapters.Neo4j.query!(cql, params, opts)`.  
They return a `Bolt.Sips.Response` if case of success

Example:
```elixir
iex> my_query = "RETURN {num} AS num"
iex> Ecto.Adapters.Neo4j.query(my_query, %{num: 5})
{:ok,
 %Bolt.Sips.Response{
   bookmark: nil,
   fields: ["num"],
   notifications: [],
   plan: nil,
   profile: nil,
   records: [[5]],
   results: [%{"num" => 5}],
   stats: [],
   type: "r"
 }}
```

## Batch
Some updates or deletes can touch a large number of node and therefore required to be executed as batch in order to perform well (and to finish...).   
EctoNeo4j provides utility functions for this purpose: `Ecto.Adapters.Neo4j.batch_query(cql, params, batch_type, opts)` and `Ecto.Adapters.Neo4j.batch_query!(cql, params, batch_type, opts)`.  
There is two types of batches and each require a specially formed query.  
They works on the same logic: 
  - 1. execute a query 
  - 2. count the touched nodes
  - if the number of touched nodes is not 0 then back to 1  

### Batch types
#### :basic
The default batch type is `:basic`. Query must have:  
  - `LIMIT {limit}` in order to specify the chunk size
  - returns `RETURN COUNT(the_node_you_re_touching) AS nb_touched_nodes` in order to have the count of touched nodes.  
This batch type is usually used for `delete` operation.  
It is not required to provide the `limit` in your `params`, it will be handled by `batch_query`.   

Example:
```
cql = """
MATCH
  (n:Post)
WHERE
  n.title CONTAINS "this"
WITH                            <--- The `WITH` allows to work on a subset...
  n AS n                        <--- 
LIMIT {limit}                   <--- with the specified nuber of node
DETACH DELETE                   <--- Perform the desired operation
  n
RETURN
  COUNT(n) AS nb_touched_nodes  <--- And return the numbere of node touched by the operation
"""
Ecto.Adapters.Neo4j.batch_query(cql)
```

#### :with_skip
This batch type is useful where a simple `COUNT` is irrevelant (in update operation for example). Query must have:  
  - `SKIP {skip} LIMIT {limit}` in order to specify the chunk size
  - returns `RETURN COUNT(the_node_you_re_touching) AS nb_touched_nodes` in order to have the count of touched nodes.  
It is not required to provide the `skip` nor the `limit` in your `params`, they will be handled by `batch_query`.   

Example:
```
cql = """
MATCH
  (n:Post)
WHERE
  n.title CONTAINS "this"
WITH                                <--- THe WITH allows to work on a subset...
  n AS n                            <--- 
SKIP {skip} LIMIT {limit}           <--- with the specified nuber of node
SET                                 <--- Perform the desired operation
  n.title = "Updated: " + n.title 
RETURN
  COUNT(n) AS nb_touched_nodes      <--- And return the numbere of node touched by the operation
"""
Ecto.Adapters.Neo4j.batch_query(cql, %{}, :with_skip)
```

### Chunk size
The default chunk size is 10_000.  
The ideal chunk size is tighly related to the machine RAM, and you can specify if you want:
  - at query level with the options `[chunk_size: integer]`  
  Example: `Ecto.Adapters.Neo4j.query(cql, params, :basic, [chunk_size: 50_000])`
  - in your configuration, you can define the desired default chunk_size:  
```elixir
  config :ecto_neo4j, Ecto.Adapters.Neo4j,
  chunk_size: 50_000
```

### update_all, delete_all
You can have `Repo.update_all` and `Repo.delete_all` executed as batches with the option `[batch: true]` (without any query tricks).  
This option can be added in your configuration if you want the behaviour to happen for all `update_all`s and `delete_all`s.
```elixir
  config :ecto_neo4j, Ecto.Adapters.Neo4j,
  batch: true
```

# TODO
[x] Manage bolt role  
[ ] Split test to allow bolt v1 testing  
[ ] Support prefix? (is there any use case for this?)  
[ ] Support optimistic locking?  
[x] Support migration (only: index creation, drop, rename, alter column name)  
[x] Migration is supposed to support large amount of data (use batch...)  
[ ] Support insert select?  
[ ] Support delete with returning?  
[ ] Support map update?  
[ ] Implement a merge?  
[ ] Telemetry  
[ ] insert_all performance
[ ] stream
[ ] `ecto.drop` should remove constraints and indexes()

# Can I contribute?  
Yes, you can! Please, do!  
Just fork, commit and submit pull requests!