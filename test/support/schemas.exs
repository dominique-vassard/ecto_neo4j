defmodule EctoNeo4j.Integration.User do
  use Ecto.Schema
  @primary_key {:uuid, Ecto.UUID, []}

  schema "User" do
    field :first_name, :string
    field :last_name, :string

    has_many :posts, EctoNeo4j.Integration.Post
  end
end

defmodule EctoNeo4j.Integration.Post do
  use Ecto.Schema
  @primary_key {:uuid, Ecto.UUID, []}

  schema "Post" do
    field :title, :string
    field :text, :string
    field :rel_wrote, :map, virtual: true

    belongs_to :author, EctoNeo4j.Integration.User, foreign_key: :user_uuid, type: Ecto.UUID
  end
end
