defmodule EctoNeo4j.Integration.User do
  use Ecto.Schema
  @primary_key {:uuid, Ecto.UUID, []}

  schema "User" do
    field :first_name, :string
    field :last_name, :string

    has_many :wrote_comment, EctoNeo4j.Integration.Comment
    has_many :wrote_post, EctoNeo4j.Integration.Post
  end
end

defmodule EctoNeo4j.Integration.Post do
  use Ecto.Schema
  @primary_key {:uuid, Ecto.UUID, []}

  schema "Post" do
    field :title, :string
    field :text, :string
    field :rel_wrote, :map
    field :rel_read, :map

    has_many :comments, EctoNeo4j.Integration.Comment
    belongs_to :wrote_post, EctoNeo4j.Integration.User, foreign_key: :user_uuid, type: Ecto.UUID
  end
end

defmodule EctoNeo4j.Integration.Comment do
  use Ecto.Schema

  @primary_key {:uuid, Ecto.UUID, []}

  schema "Comment" do
    field :text, :string
    field :rel_wrote, :map
    # field :rel_has_comment, :map

    belongs_to :wrote_comment, EctoNeo4j.Integration.User,
      foreign_key: :user_uuid,
      type: Ecto.UUID

    # belongs_to :post, EctoNeo4j.Integration.Post, foreign_key: :post_uuid, type: Ecto.UUID
  end
end
