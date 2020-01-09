# Ecto adapter for Neo4j graph database

[![Build Status](https://travis-ci.org/dominique-vassard/ecto_neo4j.svg?branch=master)](https://travis-ci.org/dominique-vassard/ecto_neo4j)

# Goal
EctoNeo4j is designed to ease the use of Neo4j in elixir and provides an adapter for Ecto.  
It allows to works with `schema` and to use the classic `Ecto.Repo` functions.  

Kepp in mind that `Ecto.Schema` is relational-database oriented, then some graph-specific operations have to be emulated with the Ecto terms, especially
`join`, `assoc`, `preload`.

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
As an effeot to have a usable package, Ecto feature like `join`, `assoc`, etc. are used to manage relationships.    

# Usage
## Schema
### Reserved field: id
As you may know, Neo4j uses a feild named `id` toi manage its internal identifiers. It is then strongly recommended to not use it in your schemas.  

### Defining schema
To define a schema designed to be used with ECtoNeo4j, it is recommended to use `Ecto.Adapters.Neo4j.Schema` as it :  
  - provides a primary key named `:uuid` to avoid conflic with Neo4j internal identifiers
  - provides 2 macros to manage relationships: `outgoing_relationship/2 (and /3)` and `incoming_relationship/2`
  - allows to not use `has_*` and `belongs_to` functions

Note that `many_to_many` is not covered as its mangement is not possible yet.

#### Relationships
Relationships can be defined via: `outgoing_relationship` and `incoming_relationship`.

`outgoing_relationship` takes 3 parameters:
  - a name which is an atom formated as [relationship_type]_[child_schema_name]
  - the related schema
  - [optional] the options. For now only `:unique` (bool) is available. It defiens wether many child nodes can be linked to parent node (unique: false, the default) or just one (unique: true)

`incoming_relationship` takes 2 parameters:
  - a name which is an atom formated as [relationship_type]_[child_schema_name]
  - the related schema

Relationships properties are a field in child schema. This field must be named `rel_[relationship_type]` and is a map.

Note that the `name` has to be the same in parent and child schema.

### Example
Considering the following graph schema:
```
(User)-[:WROTE]->(Post)
(User)-(:READ)->(Post)
(User)-[:HAS]->(Profile)
```
where a User can read / wrote mutiple posts, but has only one profile.  

This tranlates as:  
```elixir
defmodule MyApp.User do
  use Ecto.Adapters.Neo4j.Schema

  schema "User" do
    field :first_name, :string
    field :last_name, :string

    outgoing_relationship :has_userprofile, MyApp.UserProfil, unique: true
    outgoing_relationship(:wrote_post, MyApp.Post)
    outgoing_relationship :read_post, MyApp.Post
  end
end

defmodule MyApp.Profile do
  use Ecto.Adapters.Neo4j.Schema

  schema "UserProfile" do
    field :avatar, :string
    field :rel_has, :map

    incoming_relationship :has_profile, MyApp.User
  end
end

defmodule MyApp.Post do
  use Ecto.Adapters.Neo4j.Schema

  schema "Post" do
    field :title, :string
    field :text, :string
    field :rel_wrote, :map
    field :rel_read, :map

    incoming_relationship :wrote_post, MyApp.User
    incoming_relationship :read_post, MyApp.User
  end
end
```

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
  - `join` to manage relationships
  - `last`
  - `limit`
  - `offset` which is `SKIP` in cypher
  - `order_by`
  - `select` which is `RETURN` in cypher
  - `update` which is `MATCH... SET` in cypher 
  - `where`

For very specific operation like `CONTAINS`, `START_WITH`, etc. I encourage you to use [query fragment](https://hexdocs.pm/ecto/Ecto.Query.API.html#fragment/1)

### Working with relationships (associations in Ecto)
When you ant to work on relationship, you have to use Neo4j's adapter specific functions and not the Ecto one. In fact, if you work with EctoNeo4j, it is recommedned to always use these functions instead of their Ecto counterparts.  
The specific funtions are:
  - `Ecto.Adapters.Neo4j.insert(repo, data, opts \\ [])`: creates nodes and creates relationship if required
  - `Ecto.Adapters.Neo4j.preload(struct_or_structs_or_nil, preloads, opts \\ [])`: usage and goal are the same as `Repo.preload`
  - `Ecto.Adapters.Neo4j.update(changeset, repo, opts \\ [])`: updates nodes and creates / removes / updates realtionships if needed

The weird position of `repo` in the argument is to ease the piping.

#### Inserting
There is nothing special here, insert your data as you would do with classic Ecto associations. 

#### Updating / Deleting
For this kind of operation, [put_assoc](https://hexdocs.pm/ecto/Ecto.Changeset.html#put_assoc/4) has to be used.

#### Querying
Because relationship are not citizens in the relational world, Ecto does not provide the ability to query them. In order to retrieve relationship data, you will have to query the node in order to feed the relationship field (prefixed by `rel_`).  
To query a relationship, you can use `join` and `on` keywords. `join` allows you to specify the node to link, and `on` will have ALL clauses ti apply on relationship.

Example:
```elixir
# Unspecified relationship
from u in User,
join: p in Post
# will translates to:
MATCH
  (u:User)-[]->(:Post)
RETURN
  u
# Beware of the multiple results?

# Specific relationship (but without data)
from u in User,
join: p in Post,
on: p.rel_wrote == ^%{}
# will translates to:
MATCH
  (u:User)-[:WROTE]->(:Post)
RETURN
  u

# Specific relationship (without data)
from u in User,
join: p in Post,
on: p.rel_wrote == ^%{when: ~D[2019-12-12]}
# will translates to:
MATCH
  (u:User)-[rel:WROTE]->(:Post)
WHERE
  rel.when = "2019-12-12"
RETURN
  u

# Non existing relationship:
from u in User,
join: p in Post,
on: is_nil(p.rel_wrote)
# will translates to:
MATCH
  (u:User)
WHERE
  NOT (u)-[:WROTE]->(:Post)
RETURN
  u
```

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
  COUNT(n) AS nb_touched_nodes  <--- And return the number of nodes touched by the operation
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
  COUNT(n) AS nb_touched_nodes      <--- And return the number of nodes touched by the operation
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
[ ] Remove the `id` to `nodeId` conversion
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
[x] `ecto.drop` should remove constraints and indexes()


# Can I contribute?  
Yes, you can! Please, do!  
Just fork, commit and submit pull requests!