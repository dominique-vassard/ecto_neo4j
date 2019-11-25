defmodule Ecto.Adapters.Neo4j.SchemaTest do
  use ExUnit.Case, async: true

  @moduletag :supported

  alias Ecto.Adapters.Neo4j.Behaviour.Schema

  alias EctoNeo4j.Integration.{User, Post, Comment}

  test "get_forign_keys/1" do
    assert [:user_uuid] = Schema.get_foreign_keys(Comment)
    assert [] = Schema.get_foreign_keys(User)
  end

  test "remove_foreign_keys/1" do
    post1_data = %Post{
      uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
      title: "First",
      text: "This is the first",
      rel_wrote: %{
        when: ~D[2018-01-01]
      },
      user_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
    }

    post2_data = %Post{
      uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
      title: "Second",
      text: "This is the second",
      rel_read: %{},
      rel_wrote: %{
        when: ~D[2018-02-01]
      },
      user_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
    }

    user = %User{
      uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
      first_name: "John",
      last_name: "Doe",
      posts: [
        post1_data,
        post2_data
      ],
      comments: %Ecto.Association.NotLoaded{}
    }

    assert {:ok,
            %EctoNeo4j.Integration.User{
              comments: %Ecto.Association.NotLoaded{},
              first_name: "John",
              last_name: "Doe",
              posts: posts,
              uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
            }} = Schema.remove_foreign_keys({:ok, user})

    posts
    |> Enum.map(fn post ->
      refute :user_uuid in Map.keys(post)
    end)
  end
end
