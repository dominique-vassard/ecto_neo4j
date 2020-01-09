# Schema

## General
A graph is composed of two objects: node and relationship, each with its own specifities.  
Node has:
- one or more labels 
- 0 or more properties

Relationship has:
- one type
- 0 or more properties
- a direction

Because of how ecto is designed, it is not possible for now to have more than one label per node.

In order to ease the schema building, we can use `Ecto.Adapters.Neo4j.Schema` which is a layer on top of `Ecto.Schema`. It sets the default primary key to `:uuid` instead of `:id` to avoid problem with Neo4j's internal identifier's system.  

### Describing relationships
Additionally, `Ecto.Adapters.Neo4j.Schema` offers two macros to work with relationships:
- `outgoing_relationship/2` and `outgoing_relationship/3` allows to describe outgoing relationship. Their usage is the same `has_*` macros: they take a _name_ as first parameter and the related schema as second parameter. The third parameter is for options, only one is available for now: :unique. Set to `true`, it indicates that the relationship is 1-1, set to false t's a 1-many relationship.  
- `incoming_relationship/2` allows to describe an incoming relationship. First parameter is the _name_, the eseond is the related schema.

Note that the _name_ is formated as: [lower_case_relationship_type]_[child_schema_name] and have to be the same in parent and child schema.  
For example:
Considering `(:Actor)-[:PLAYS_IN]->(:Movie)`, we will have:
```elixir
defmodule MyApp.Actor do
  schema "Actor" do
    ...
    outgoing_relationship :plays_in_movie, MyApp.Movie
  end
end

defmodule MyApp.Movie do
  schema "Movie" do
    ...
    outgoing_relationship :plays_in_movie, MyApp.Actor
  end
end
```

### About relationship properties
Relationship data will be in the child schema, and be fed when `preload` is used.
It is recommended to:
- have the field name set to _rel\_[lower_cased_relationship_type]_
- have field type set to `:map`

This field is mandatory, even if there will be no properties to use. It is still useful for querying purpose.


## Putting up the GraphApp schemas

### Remember the model
![GrapApp Model](../assets/model.png)  
a `User` can only have one `UserProfile`.  
a `User` can write multiple `Posts`.  
a `User` can read multiple `Posts`.
a `User` can write multiple `Comments`.  
a `Post` can have multiple `Comments`.  

`User` properties:
- firstName
- lastName

`UserProfile` properties:
- avatarUrl
- age

`Post` properties:
- title
- text

`Comment` properties:
- text

`:WROTE` (from `User` to `Post`, and from `User` to `Comment`) properties:
- when

Now, let's write our schemas:
### User
```elixir
# lib/graph_app/account/user.ex
defmodule GraphApp.Account.User do
  use Ecto.Adapters.Neo4j.Schema

  schema "User" do 
    field :firstName, :string
    field :lastName, :string

    # (:User)-[:HAS]->(:UserProfile) 
    # A user has only one UserProfile
    outgoing_relationship :has_userprofile, GraphApp.Account.UserProfile,  unique: true 

    # (:User)-[:WROTE]->(:Post)
    outgoing_relationship :wrote_post, GraphApp.Blog.Post  

    # (:User)-[:READ]->(:Post)
    outgoing_relationship :read_post, GraphApp.Blog.Post 
    
    # (:User)-[:READ]->(:Comment)
    outgoing_relationship :wrote_comment, GraphApp.Blog.Comment
  end
end
```

### UserProfile
```elixir
# lib/graph_app/account/user_profile.ex
defmodule GraphApp.Account.UserProfile do
  use Ecto.Adapters.Neo4j.Schema

  schema "UserProfile" do
    field :avatar, :string

    # Field for :HAS relationship's properties
    field :rel_has, :map

    # (:User)-[:HAS]->(:UserProfile) 
    # Note that the name of relationship is the same as in GraphApp.Account.User
    incoming_relationship :has_userprofile, GraphApp.Account.User
  end
end
```

### Post
```elixir
# lib/graph_app/blog/post.ex
defmodule GraphApp.Blog.Post do
  use Ecto.Adapters.Neo4j.Schema

  schema "Post" do
    field :title, :string
    field :text, :string

    # Field for :WROTE relationship's properties
    field :rel_wrote, :map

    # Field for :READ relationship's properties
    field :rel_read, :map

    # (:User)-[:WROTE]->(:Post)
    incoming_relationship :wrote_post, GraphApp.Account.User

    # (:User)-[:READ]->(:Post)
    incoming_relationship :read_post, GraphApp.Account.User
    
    # (:Post)-[:HAS]->(:Comment)
    outgoing_relationship :has_comment, GraphApp.Blog.Comment
  end
end
```

### Comment
```elixir
# lib/graph_app/blog/comment.ex
defmodule GraphApp.Blog.Comment do
  use Ecto.Adapters.Neo4j.Schema

  schema "Comment" do
    field :text, :string

    # Field for :WROTE relationship's properties
    field :rel_wrote, :map

    # Field for :HAS relationship's properties
    field :rel_has, :map

    # (:User)-[:WROTE]->(:Comment)
    incoming_relationship :wrote_comment, GraphApp.Account.User

    # (:Post)-[:HAS]->(:Comment)
    incoming_relationship :has_comment, GraphApp.Blog.Post
  end
end
```
