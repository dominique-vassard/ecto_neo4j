defmodule EctoNeo4j.RelationshipsTest do
  use ExUnit.Case, async: false
  @moduletag :supported

  alias Ecto.Integration.TestRepo
  alias EctoNeo4j.Integration.{User, Post}

  setup do
    Ecto.Adapters.Neo4j.query!("MATCH (n) DETACH DELETE n")
    :ok
  end

  test "creation ok" do
    post1_data = %Post{
      uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
      title: "First",
      text: "This is the first",
      rel_wrote: %{
        when: ~D[2018-01-01]
      }
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

    user = %User{
      uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
      first_name: "John",
      last_name: "Doe",
      posts: [
        post1_data,
        post2_data
      ]
    }

    assert {:ok, _} = Ecto.Adapters.Neo4j.insert(TestRepo, user)

    cql_check = """
    MATCH
      (u:User {uuid: {user_uuid}})-[rel1:WROTE {when: date({post1_when})}]->(p1:Post {uuid: {post1_uuid}}),
      (u)-[rel2:WROTE {when: date({post2_when})}]->(p2:Post {uuid: {post2_uuid}}),
      (u)-[rel3:READ]->(p2)
      RETURN
        COUNT(rel1) + COUNT(rel2) + COUNT(rel3) AS nb_rel
    """

    params = %{
      user_uuid: user.uuid,
      post1_uuid: post1_data.uuid,
      post1_when: post1_data.rel_wrote.when,
      post2_uuid: post2_data.uuid,
      post2_when: post2_data.rel_wrote.when
    }

    assert %Bolt.Sips.Response{results: [%{"nb_rel" => 3}]} =
             Ecto.Adapters.Neo4j.query!(cql_check, params)
  end
end
