defmodule EctoNeo4j.Integration.User do
  use Ecto.Schema
  import Ecto.Adapters.Neo4j.Schema
  @primary_key {:uuid, Ecto.UUID, []}

  schema "User" do
    field :first_name, :string
    field :last_name, :string

    outgoing_relationship :wrote_comment, EctoNeo4j.Integration.Comment
    outgoing_relationship :has_userprofile, EctoNeo4j.Integration.UserProfile, unique: true

    # has_many :wrote_comment, EctoNeo4j.Integration.Comment, foreign_key: :user_wrote_comment_uuid
    has_many :wrote_post, EctoNeo4j.Integration.Post, foreign_key: :wrote_post_uuid
    has_many :read_post, EctoNeo4j.Integration.Post, foreign_key: :user_read_post_uuid
  end
end

defmodule EctoNeo4j.Integration.UserProfile do
  use Ecto.Schema
  import Ecto.Adapters.Neo4j.Schema
  @primary_key {:uuid, Ecto.UUID, []}

  schema "UserProfile" do
    field :avatar, :string
    field :rel_has, :map

    incoming_relationship :has_userprofile, EctoNeo4j.Integration.User
  end
end

defmodule EctoNeo4j.Integration.Post do
  use Ecto.Schema
  import Ecto.Adapters.Neo4j.Schema

  @primary_key {:uuid, Ecto.UUID, []}

  schema "Post" do
    field :title, :string
    field :text, :string
    field :rel_wrote, :map
    field :rel_read, :map

    # has_many :has_comment, EctoNeo4j.Integration.Comment, foreign_key: :post_has_comment_uuid
    outgoing_relationship :has_comment, EctoNeo4j.Integration.Comment

    incoming_relationship(:wrote_post, EctoNeo4j.Integration.User)

    # belongs_to :wrote_post, EctoNeo4j.Integration.User,
    #   foreign_key: :wrote_post_uuid,
    #   type: Ecto.UUID

    belongs_to :read_post, EctoNeo4j.Integration.User,
      foreign_key: :user_read_post_uuid,
      type: Ecto.UUID
  end
end

defmodule EctoNeo4j.Integration.Comment do
  use Ecto.Schema
  import Ecto.Adapters.Neo4j.Schema

  @primary_key {:uuid, Ecto.UUID, []}

  schema "Comment" do
    field :text, :string
    field :rel_wrote, :map
    field :rel_has, :map
    # field :rel_has_comment, :map

    incoming_relationship :wrote_comment, EctoNeo4j.Integration.User

    # belongs_to :wrote_comment, EctoNeo4j.Integration.User,
    #   foreign_key: :wrote_comment_uuid,
    #   # foreign_key: :user_wrote_comment_uuid,
    #   type: Ecto.UUID

    incoming_relationship(:has_comment, EctoNeo4j.Integration.Post)
    # belongs_to :post, EctoNeo4j.Integration.Post,
    #   foreign_key: :post_has_comment_uuid,
    #   type: Ecto.UUID
  end
end
