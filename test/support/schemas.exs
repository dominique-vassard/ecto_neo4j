defmodule EctoNeo4j.Integration.User do
  use Ecto.Adapters.Neo4j.Schema

  schema "User" do
    field :first_name, :string
    field :last_name, :string

    outgoing_relationship :wrote_comment, EctoNeo4j.Integration.Comment
    outgoing_relationship :has_userprofile, EctoNeo4j.Integration.UserProfile, unique: true
    outgoing_relationship(:wrote_post, EctoNeo4j.Integration.Post)
    outgoing_relationship :read_post, EctoNeo4j.Integration.Post
  end
end

defmodule EctoNeo4j.Integration.UserProfile do
  use Ecto.Adapters.Neo4j.Schema

  schema "UserProfile" do
    field :avatar, :string
    field :rel_has, :map

    incoming_relationship :has_userprofile, EctoNeo4j.Integration.User
  end
end

defmodule EctoNeo4j.Integration.Post do
  use Ecto.Adapters.Neo4j.Schema

  schema "Post" do
    field :title, :string
    field :text, :string
    field :rel_wrote, :map
    field :rel_read, :map

    outgoing_relationship :has_comment, EctoNeo4j.Integration.Comment
    incoming_relationship :wrote_post, EctoNeo4j.Integration.User
    incoming_relationship :read_post, EctoNeo4j.Integration.User
  end
end

defmodule EctoNeo4j.Integration.Comment do
  use Ecto.Adapters.Neo4j.Schema

  schema "Comment" do
    field :text, :string
    field :rel_wrote, :map
    field :rel_has, :map

    incoming_relationship :wrote_comment, EctoNeo4j.Integration.User
    incoming_relationship(:has_comment, EctoNeo4j.Integration.Post)
  end
end
