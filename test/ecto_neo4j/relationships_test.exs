defmodule EctoNeo4j.RelationshipsTest do
  use ExUnit.Case, async: false
  @moduletag :supported

  import Ecto.Query

  alias Ecto.Integration.TestRepo
  alias EctoNeo4j.Integration.{User, Post, Comment}

  setup do
    Ecto.Adapters.Neo4j.query!("MATCH (n) DETACH DELETE n")
    :ok
  end

  describe "creation" do
    test "1 assoc ok" do
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

      assert {:ok,
              %User{
                posts: posts
              }} = Ecto.Adapters.Neo4j.insert(TestRepo, user)

      posts
      |> Enum.map(fn post ->
        refute :user_uuid in Map.keys(post)
      end)

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

    test "2 assoc ok" do
      {user, post1_data, post2_data, comment1_data, comment2_data} = fixtures()

      cql_check = """
      MATCH
        (u:User {uuid: {user_uuid}})-[rel1:WROTE {when: date({post1_when})}]->(p1:Post {uuid: {post1_uuid}}),
        (u)-[rel2:WROTE {when: date({post2_when})}]->(p2:Post {uuid: {post2_uuid}}),
        (u)-[rel3:READ]->(p2),
        (u)-[rel4:WROTE]->(:Comment {uuid: {comment1_uuid}}),
        (u)-[rel5:WROTE]->(:Comment {uuid: {comment2_uuid}})
        RETURN
          COUNT(rel1) + COUNT(rel2) + COUNT(rel3) + COUNT(rel4) + COUNT(rel5) AS nb_rel
      """

      params = %{
        user_uuid: user.uuid,
        post1_uuid: post1_data.uuid,
        post1_when: post1_data.rel_wrote.when,
        post2_uuid: post2_data.uuid,
        post2_when: post2_data.rel_wrote.when,
        comment1_uuid: comment1_data.uuid,
        comment2_uuid: comment2_data.uuid
      }

      assert {:ok,
              %User{
                comments: comments,
                posts: posts
              }} = Ecto.Adapters.Neo4j.insert(TestRepo, user)

      (posts ++ comments)
      |> Enum.map(fn post ->
        refute :user_uuid in Map.keys(post)
      end)

      assert %Bolt.Sips.Response{results: [%{"nb_rel" => 5}]} =
               Ecto.Adapters.Neo4j.query!(cql_check, params)
    end
  end

  describe "querying" do
    test "preload" do
      user = add_data()

      assert %User{
               posts: posts,
               comments: %Ecto.Association.NotLoaded{}
             } =
               TestRepo.get(User, user.uuid, preload: :posts)
               |> TestRepo.preload(:posts)

      assert [
               %EctoNeo4j.Integration.Post{
                 rel_read: %{},
                 rel_wrote: %{"when" => ~D[2018-02-01]},
                 text: "This is the second",
                 title: "Second",
                 uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab"
               },
               %EctoNeo4j.Integration.Post{
                 rel_read: nil,
                 rel_wrote: %{"when" => ~D[2018-01-01]},
                 text: "This is the first",
                 title: "First",
                 uuid: "ae830851-9e93-46d5-bbf7-23ab99846497"
               }
             ] = posts
    end

    test "preload 2 assocs" do
      user = add_data()

      assert %User{
               posts: posts,
               comments: comments
             } =
               TestRepo.get(User, user.uuid, preload: :posts)
               |> TestRepo.preload([:posts, :comments])

      assert [
               %EctoNeo4j.Integration.Post{
                 rel_read: %{},
                 rel_wrote: %{"when" => ~D[2018-02-01]},
                 text: "This is the second",
                 title: "Second",
                 uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab"
               },
               %EctoNeo4j.Integration.Post{
                 rel_read: nil,
                 rel_wrote: %{"when" => ~D[2018-01-01]},
                 text: "This is the first",
                 title: "First",
                 uuid: "ae830851-9e93-46d5-bbf7-23ab99846497"
               }
             ] = posts

      assert [
               %EctoNeo4j.Integration.Comment{
                 rel_wrote: %{"when" => ~D[2018-07-01]},
                 text: "THis is not the ebest post I've read...",
                 uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3"
               },
               %EctoNeo4j.Integration.Comment{
                 rel_wrote: %{"when" => ~D[2018-06-18]},
                 text: "This a comment from john Doe",
                 uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef"
               }
             ] = comments
    end

    test "simple join (no clause)" do
      _user = add_data()

      query =
        from u in User,
          join: p in Post

      TestRepo.all(query)
    end

    test "simple for a specific relationship type" do
      _user = add_data()

      _no_data_rel = %{}

      query =
        from u in User,
          join: c in Comment,
          on: c.rel_wrote == ^%{}

      TestRepo.all(query)
    end

    # test " on multiple rel types" do
    #   _user = add_data()

    #   query =
    #     from u in User,
    #       join: c in Comment,
    #       on: c.rel_wrote == ^%{} or c.rel_read == ^%{}

    #   TestRepo.all(query)
    # end

    test "with clause on rel props" do
      _user = add_data()

      rel_data = %{when: ~D[2018-01-01]}

      query =
        from u in User,
          join: p in Post,
          on: p.rel_wrote == ^rel_data

      TestRepo.all(query)
    end
  end

  defp fixtures() do
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

    comment1_data = %Comment{
      uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
      text: "This a comment from john Doe",
      rel_wrote: %{when: ~D[2018-06-18]}
    }

    comment2_data = %Comment{
      uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3",
      text: "THis is not the ebest post I've read...",
      rel_wrote: %{when: ~D[2018-07-01]}
    }

    user = %User{
      uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
      first_name: "John",
      last_name: "Doe",
      posts: [
        post1_data,
        post2_data
      ],
      comments: [
        comment1_data,
        comment2_data
      ]
    }

    {user, post1_data, post2_data, comment1_data, comment2_data}
  end

  defp add_data() do
    {user, _, _, _, _} = fixtures()

    assert {:ok, _} = Ecto.Adapters.Neo4j.insert(TestRepo, user)
    user
  end
end
