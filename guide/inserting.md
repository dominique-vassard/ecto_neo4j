# Inserting

Inserting is similar as what it is in with Ecto, except that we have to use `Ecto.Adapters.Neo4j.insert/3` instead of the classic `insert/2` in order to have our relationships created.

## Inserting nodes
It's straight forward as there is nothing more or less than in classic ecto.

```elixir
# Direct
alias GraphApp.Account.User
alias Ecto.Adapters.Neo4j

user = %User{
  uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
  firstName: "John",
  lastName: "Doe"
}

{:ok, user} = Neo4j.insert(GraphApp.Repo, user)

# Result
{:ok,
 %GraphApp.Account.User{
   __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
   firstName: "John",
   has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
   lastName: "Doe",
   read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
   uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
   wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
   wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>
 }}

# Through changeset
data = %{
  uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
  firstName: "John",
  lastName: "Doe"
}

changeset = Ecto.Changeset.change(%User{}, data)

{:ok, user} = Neo4j.insert(GraphApp.Repo, changeset)

# Result
{:ok,
 %GraphApp.Account.User{
   __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
   firstName: "John",
   has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
   lastName: "Doe",
   read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
   uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
   wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
   wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>
 }}
 ```

## Inserting nodes AND relationships
The only way to insert a lot of nodes and relationship at once required that we know the data to insert. Changeset won't work here.  
But it worths the shot as it allows us to insert a complete graph in one command!  
  
Just remember that relationship properties are set on child node. If no properties is required, just set the field to `%{}`.  
For example:
```elixir
comment1_data = %Comment{
  uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
  text: "This a comment from john Doe",
  # These are the properties for the :WROTE relationship
  rel_wrote: %{when: ~D[2018-06-18]},
  # These are the properties for the :HAS relationship
  rel_has: %{}
}
```

Now let's insert this graph:  
![insert graph](assets/insert_result.png)
```elixir
alias GraphApp.Account.{User, UserProfile}
alias GraphApp.Blog.{Post, Comment}
alias Ecto.Adapters.Neo4j

comment1_data = %Comment{
  uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
  text: "This a comment from john Doe",
  rel_wrote: %{when: ~D[2018-06-18]},
  rel_has: %{}
}

comment2_data = %Comment{
  uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3",
  text: "This is not the best post I've read...",
  rel_wrote: %{when: ~D[2018-07-01]},
  rel_has: %{}
}

post1_data = %Post{
  uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
  title: "First",
  text: "This is the first",
  rel_wrote: %{
    when: ~D[2018-01-01]
  },
  has_comment: [
    comment1_data,
    comment2_data
  ]
}

post2_data = %Post{
  uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
  title: "Second",
  text: "This is the second",
  rel_read: %{},
  rel_wrote: %{
    when: ~D[2018-02-01]
  }
}

user_profile = %UserProfile{
  uuid: "0f364433-c0d2-47ac-ad9b-1dc15bd40cde",
  avatar: "user_avatar.png",
  rel_has: %{}
}

user = %User{
  uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
  firstName: "John",
  lastName: "Doe",
  read_post: [
    post2_data
  ],
  wrote_post: [
    post1_data,
    post2_data
  ],
  wrote_comment: [
    comment1_data,
    comment2_data
  ],
  has_userprofile: user_profile
}

{:ok, user} = Neo4j.insert(GraphApp.Repo, user)

# Result
{:ok,
 %GraphApp.Account.User{
   __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
   firstName: "John",
   has_userprofile: %GraphApp.Account.UserProfile{
     __meta__: #Ecto.Schema.Metadata<:loaded, "UserProfile">,
     avatar: "user_avatar.png",
     has_userprofile: #Ecto.Association.NotLoaded<association :has_userprofile is not loaded>,
     has_userprofile_uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
     rel_has: %{},
     uuid: "0f364433-c0d2-47ac-ad9b-1dc15bd40cde"
   },
   lastName: "Doe",
   read_post: [
     %GraphApp.Blog.Post{
       __meta__: #Ecto.Schema.Metadata<:loaded, "Post">,
       has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
       read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
       read_post_uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
       rel_read: %{},
       rel_wrote: %{when: ~D[2018-02-01]},
       text: "This is the second",
       title: "Second",
       uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
       wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>,
       wrote_post_uuid: nil
     }
   ],
   uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
   wrote_comment: [
     %GraphApp.Blog.Comment{
       __meta__: #Ecto.Schema.Metadata<:loaded, "Comment">,
       has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
       has_comment_uuid: nil,
       rel_has: %{},
       rel_wrote: %{when: ~D[2018-06-18]},
       text: "This a comment from john Doe",
       uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
       wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
       wrote_comment_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
     },
     %GraphApp.Blog.Comment{
       __meta__: #Ecto.Schema.Metadata<:loaded, "Comment">,
       has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
       has_comment_uuid: nil,
       rel_has: %{},
       rel_wrote: %{when: ~D[2018-07-01]},
       text: "This is not the best post I've read...",
       uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3",
       wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
       wrote_comment_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
     }
   ],
   wrote_post: [
     %GraphApp.Blog.Post{
       __meta__: #Ecto.Schema.Metadata<:loaded, "Post">,
       has_comment: [
         %GraphApp.Blog.Comment{
           __meta__: #Ecto.Schema.Metadata<:loaded, "Comment">,
           has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
           has_comment_uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
           rel_has: %{},
           rel_wrote: %{when: ~D[2018-06-18]},
           text: "This a comment from john Doe",
           uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
           wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
           wrote_comment_uuid: nil
         },
         %GraphApp.Blog.Comment{
           __meta__: #Ecto.Schema.Metadata<:loaded, "Comment">,
           has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
           has_comment_uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
           rel_has: %{},
           rel_wrote: %{when: ~D[2018-07-01]},
           text: "This is not the best post I've read...",
           uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3",
           wrote_comment: #Ecto.Association.NotLoaded<association :wrote_comment is not loaded>,
           wrote_comment_uuid: nil
         }
       ],
       read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
       read_post_uuid: nil,
       rel_read: nil,
       rel_wrote: %{when: ~D[2018-01-01]},
       text: "This is the first",
       title: "First",
       uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
       wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>,
       wrote_post_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
     },
     %GraphApp.Blog.Post{
       __meta__: #Ecto.Schema.Metadata<:loaded, "Post">,
       has_comment: #Ecto.Association.NotLoaded<association :has_comment is not loaded>,
       read_post: #Ecto.Association.NotLoaded<association :read_post is not loaded>,
       read_post_uuid: nil,
       rel_read: %{},
       rel_wrote: %{when: ~D[2018-02-01]},
       text: "This is the second",
       title: "Second",
       uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
       wrote_post: #Ecto.Association.NotLoaded<association :wrote_post is not loaded>,
       wrote_post_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
     }
   ]
 }}
```

You can notice the presence of `wrote_post_uuid`, `wrote_comment_uuid`, etc. These are foreign keys and ecto requires them to work properly.  
But don't panic, they aren't persisted  in database.
