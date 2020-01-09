# Querying

## Querying nodes
Nothing specific here, we can use Ecto functions the same we do with other adapters. We can:
- `Repo.get`
- `Repo.get_by`
- `Repo.all`
- `Repo.one`  
etc.

## Preloading
To preload data, we need to use `Ecto.Adapters.Neo4j.preload` instead of classic `Repo.preload`. This function works the same way except for subqueries and nested preloads which aren't supported.  

Considering the graph inserted in the [Inserting](inserting.html) section, we can do this:
```elixir
alias Ecto.Adapters.Neo4j

alias GraphApp.Repo
alias GraphApp.Account.User

Repo.get!(User, "12903da6-5d46-417b-9cab-bd82766c868b")
|> Neo4j.preload(:wrote_post)

# Result
%GraphApp.Account.User{
  __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
  firstName: "John",
  has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
  lastName: "Doe",
  read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
  uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
  wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
  wrote_post: [
    %GraphApp.Blog.Post{
      __meta__: #Ecto.Schema.Metadata<:built, "Post">,
      has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
      read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
      read_post_uuid: nil,
      rel_read: nil,
      rel_wrote: %{"when" => ~D[2018-02-01]},
      text: "This is the second",
      title: "Second",
      uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
      wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>,
      wrote_post_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
    },
    %GraphApp.Blog.Post{
      __meta__: #Ecto.Schema.Metadata<:built, "Post">,
      has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
      read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
      read_post_uuid: nil,
      rel_read: nil,
      rel_wrote: %{"when" => ~D[2018-01-01]},
      text: "This is the first",
      title: "First",
      uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
      wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>,
      wrote_post_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
    }
  ]
}
```

## Querying relationships and relationships' data
To query realtionships and their data, we need to use `join` and `on`.  
`join` will simply define the relationship and translate in cypher as an unqualified relationship between 2 nodes.  
For example:  
```elixir
from u in User,
join: p in Post
``` 
will translate to:  
`(:User)-[]->(:Post)`

`on` allows to qualifies relationship and to had clauses on relationship data.  
Remember that relationship data are part of the end node schema. We will use this field to had clause on relationship type and data:
- `rel_[relationship_type] == %{}` will check that there is a relationship of type _[relationship\_type]_ between the two nodes
- `is_nil(rel_[relationship_type])` will check that there is NOT a relationship of type _[relationship\_type]_ between the two nodes
- `rel_[relationship_type] == %{rel_property: prop_value}` will check that there is a relationship of type _[relationship\_type]_ between the two nodes AND that it has a property named _rel\_property_ with the given _prop\_value_

**IMPORTANT**: 
    - Always make joins from start node to end node, the opposite way is not supported yet
    - Relationship works at 1-level depth only for the moment
    - `or` operator in `on` clause is not supported 

### Examples
```elixir
alias Ecto.Adapters.Neo4j
import Ecto.Query

alias GraphApp.Repo
alias GraphApp.Account.{User, UserProfile}
alias GraphApp.Blog.{Post, Comment}
```
Considering the graph inserted in the [Inserting](inserting.html) section.

#### Retrieving users related to post in any kind of way:
In Cypher:
```cypher
MATCH
    (u:User)-[]->(:Post)
RETURN
    u
```

In EctoNeo4j:
```elixir
query = from u in User,
join: p in Post

Repo.all(query)

# Result
[
  %GraphApp.Account.User{
    __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
    firstName: "John",
    has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
    lastName: "Doe",
    read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
    uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
    wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
    wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>
  },
  %GraphApp.Account.User{
    __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
    firstName: "John",
    has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
    lastName: "Doe",
    read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
    uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
    wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
    wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>
  },
  %GraphApp.Account.User{
    __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
    firstName: "John",
    has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
    lastName: "Doe",
    read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
    uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
    wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
    wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>
  }
]
```
Notice the duplication of node "John Doe" which happens also when you launch the querey in Neo4j...


#### Retrieving users who wrote post
In Cypher:
```cypher
MATCH
    (u:User)-[:WROTE]->(:Post)
RETURN
    u
```

In EctoNeo4j:
```elixir
query = from u in User,
        join: p in Post,
        on: p.rel_wrote == ^%{}

Repo.all(query)

# Result
[
  %GraphApp.Account.User{
    __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
    firstName: "John",
    has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
    lastName: "Doe",
    read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
    uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
    wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
    wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>
  },
  %GraphApp.Account.User{
    __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
    firstName: "John",
    has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
    lastName: "Doe",
    read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
    uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
    wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
    wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>
  }
]
```

#### Retrieving posts wrote by user but not read:
In Cypher:
```cypher
MATCH
    (:User)-[:WROTE]->(p:Post)
WHERE
    NOT (:User)-[:READ]->(p)
RETURN
    p
```

In EctoNeo4j:
```elixir
query = from u in User,
        join: p in Post,
        on: p.rel_wrote == ^%{} and is_nil(p.rel_read),
        select: p

Repo.all(query)

# Result
[
  %GraphApp.Blog.Post{
    __meta__: #Ecto.Schema.Metadata<:loaded, "Post">,
    has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
    read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
    read_post_uuid: nil,
    rel_read: nil,
    rel_wrote: nil,
    text: "This is the first",
    title: "First",
    uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
    wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>,
    wrote_post_uuid: nil
  }
]
```

#### Retrieving user who wrote a post at a specific date:
In cypher:
```cypher
MATCH
    (u:User)-[rel:WROTE]->(:Post)
WHERE
    rel.when = ~D[2018-01-01]
RETURN
    u
```

In EctoNeo4j:
```elixir
rel_data = %{when: ~D[2018-01-01]}

query = from u in User,
        join: p in Post,
        on: p.rel_wrote == ^rel_data,
        select: [u, p]

Repo.all(query)

# Result
[
  [
    %GraphApp.Account.User{
      __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
      firstName: "John",
      has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
      lastName: "Doe",
      read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
      uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
      wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
      wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>
    },
    %GraphApp.Blog.Post{
      __meta__: #Ecto.Schema.Metadata<:loaded, "Post">,
      has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
      read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
      read_post_uuid: nil,
      rel_read: nil,
      rel_wrote: nil,
      text: "This is the first",
      title: "First",
      uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
      wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>,
      wrote_post_uuid: nil
    }
  ]
]
```