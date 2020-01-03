defmodule EctoNeo4j.RelationshipsTest do
  use ExUnit.Case, async: false
  @moduletag :supported

  import Ecto.Query

  alias Ecto.Integration.TestRepo
  alias EctoNeo4j.Integration.{User, UserProfile, Post, Comment}

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
        wrote_post: [
          post1_data,
          post2_data
        ],
        read_post: [
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

    test "multiple assoc ok" do
      {user, post1_data, post2_data, comment1_data, comment2_data} = fixtures()

      cql_check = """
      MATCH
        (u:User {uuid: {user_uuid}}),
        (up:UserProfile {uuid: {userprofile_uuid}}),
        (p1:Post {uuid: {post1_uuid}}),
        (p2:Post {uuid: {post2_uuid}}),
        (c1:Comment {uuid: {comment1_uuid}}),
        (c2:Comment {uuid: {comment2_uuid}}),
        (u)-[rel0:HAS]->(up),
        (u)-[rel1:WROTE {when: date({post1_when})}]->(p1),
        (u)-[rel2:WROTE {when: date({post2_when})}]->(p2),
        (u)-[rel3:READ]->(p2),
        (u)-[rel4:WROTE]->(c1),
        (u)-[rel5:WROTE]->(c2),
        (p1)-[rel6:HAS]->(c1),
        (p1)-[rel7:HAS]->(c2)
      RETURN
          COUNT(rel0) + COUNT(rel1) + COUNT(rel2) + COUNT(rel3) + COUNT(rel4)
          + COUNT(rel5) + COUNT(rel6) + COUNT(rel7) AS nb_rel
      """

      params = %{
        user_uuid: user.uuid,
        userprofile_uuid: user.has_userprofile.uuid,
        post1_uuid: post1_data.uuid,
        post1_when: post1_data.rel_wrote.when,
        post2_uuid: post2_data.uuid,
        post2_when: post2_data.rel_wrote.when,
        comment1_uuid: comment1_data.uuid,
        comment2_uuid: comment2_data.uuid
      }

      assert {:ok, _} = Ecto.Adapters.Neo4j.insert(TestRepo, user)

      assert %Bolt.Sips.Response{results: [%{"nb_rel" => 8}]} =
               Ecto.Adapters.Neo4j.query!(cql_check, params)
    end
  end

  describe "querying" do
    test "downward preload" do
      user = add_data()

      assert %User{
               wrote_post: posts,
               wrote_comment: %Ecto.Association.NotLoaded{}
             } =
               TestRepo.get(User, user.uuid)
               |> TestRepo.preload(:wrote_post)

      assert [
               %EctoNeo4j.Integration.Post{
                 rel_read: nil,
                 rel_wrote: %{"when" => ~D[2018-01-01]},
                 text: "This is the first",
                 title: "First",
                 uuid: "ae830851-9e93-46d5-bbf7-23ab99846497"
               },
               %EctoNeo4j.Integration.Post{
                 #  rel_read: %{},
                 rel_read: nil,
                 rel_wrote: %{"when" => ~D[2018-02-01]},
                 text: "This is the second",
                 title: "Second",
                 uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab"
               }
             ] = Enum.sort(posts)
    end

    test "downward preload 2 assocs" do
      user = add_data()

      assert %User{
               read_post: read_posts,
               wrote_post: wrote_posts,
               wrote_comment: comments
             } =
               TestRepo.get(User, user.uuid)
               |> TestRepo.preload([:wrote_post, :wrote_comment, :read_post])

      assert [
               %EctoNeo4j.Integration.Post{
                 rel_read: nil,
                 rel_wrote: %{"when" => ~D[2018-01-01]},
                 text: "This is the first",
                 title: "First",
                 uuid: "ae830851-9e93-46d5-bbf7-23ab99846497"
               },
               %EctoNeo4j.Integration.Post{
                 rel_read: nil,
                 #  rel_read: %{},
                 rel_wrote: %{"when" => ~D[2018-02-01]},
                 text: "This is the second",
                 title: "Second",
                 uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab"
               }
             ] = Enum.sort(wrote_posts)

      assert [
               %EctoNeo4j.Integration.Post{
                 rel_read: %{},
                 rel_wrote: nil,
                 text: "This is the second",
                 title: "Second"
               }
             ] = read_posts

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

    test "preload (unique upward)" do
      user = add_data()

      assert %EctoNeo4j.Integration.Comment{
               has_comment_uuid: nil,
               rel_wrote: %{"when" => ~D[2018-06-18]},
               text: "This a comment from john Doe",
               uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
               wrote_comment: %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               },
               wrote_comment_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
             } =
               TestRepo.get(Comment, List.first(user.wrote_comment).uuid)
               |> Ecto.Adapters.Neo4j.preload([:wrote_comment])
    end

    test "preload (many downward)" do
      user = add_data()

      assert %EctoNeo4j.Integration.User{
               first_name: "John",
               last_name: "Doe",
               uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
               wrote_comment: [
                 %EctoNeo4j.Integration.Comment{
                   has_comment_uuid: nil,
                   rel_wrote: %{"when" => ~D[2018-07-01]},
                   text: "THis is not the ebest post I've read...",
                   uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3",
                   wrote_comment_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
                 },
                 %EctoNeo4j.Integration.Comment{
                   has_comment_uuid: nil,
                   rel_wrote: %{"when" => ~D[2018-06-18]},
                   text: "This a comment from john Doe",
                   uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
                   wrote_comment_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
                 }
               ]
             } =
               TestRepo.get(User, user.uuid)
               |> Ecto.Adapters.Neo4j.preload(:wrote_comment)
    end

    test "preload (unique downward)" do
      user = add_data()

      assert %EctoNeo4j.Integration.User{
               first_name: "John",
               has_userprofile: [
                 %EctoNeo4j.Integration.UserProfile{
                   avatar: "user_avatar.png",
                   has_userprofile_uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
                   rel_has: %{},
                   uuid: "0f364433-c0d2-47ac-ad9b-1dc15bd40cde"
                 }
               ],
               last_name: "Doe",
               uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
             } =
               TestRepo.get(User, user.uuid)
               |> Ecto.Adapters.Neo4j.preload(:has_userprofile)
    end

    test "preload (many upward + many downward)" do
      user = add_data()

      assert %EctoNeo4j.Integration.Post{
               has_comment: [
                 %EctoNeo4j.Integration.Comment{
                   has_comment_uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
                   rel_has: %{},
                   rel_wrote: nil,
                   text: "THis is not the ebest post I've read...",
                   uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3",
                   wrote_comment_uuid: nil
                 },
                 %EctoNeo4j.Integration.Comment{
                   has_comment_uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
                   rel_has: %{},
                   rel_wrote: nil,
                   text: "This a comment from john Doe",
                   uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
                   wrote_comment_uuid: nil
                 }
               ],
               rel_read: nil,
               rel_wrote: %{"when" => ~D[2018-01-01]},
               text: "This is the first",
               title: "First",
               user_read_post_uuid: nil,
               uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
               wrote_post: %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               },
               wrote_post_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
             } =
               TestRepo.get(Post, List.first(user.wrote_post).uuid)
               |> Ecto.Adapters.Neo4j.preload([:wrote_post, :has_comment])
    end

    test "simple join (no clause)" do
      add_data()

      query =
        from u in User,
          join: p in Post

      assert [
               %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               },
               %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               },
               %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               }
             ] = TestRepo.all(query)
    end

    test "simple for a specific relationship type" do
      add_data()

      query =
        from u in User,
          join: c in Comment,
          on: c.rel_wrote == ^%{}

      assert [
               %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               },
               %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               }
             ] = TestRepo.all(query)
    end

    test " on multiple rel types" do
      add_data()

      query =
        from u in User,
          join: p in Post,
          on: p.rel_wrote == ^%{} or p.rel_read == ^%{}

      assert_raise RuntimeError, fn ->
        TestRepo.all(query)
      end
    end

    test "with clause on rel props" do
      add_data()

      rel_data = %{when: ~D[2018-01-01]}

      query =
        from u in User,
          join: p in Post,
          on: p.rel_wrote == ^rel_data

      assert [
               %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               }
             ] = TestRepo.all(query)
    end

    test "with clause on a non-existent relationship" do
      add_data()

      query =
        from u in User,
          join: p in Post,
          on: is_nil(p.rel_read),
          select: p

      assert [
               %EctoNeo4j.Integration.Post{
                 rel_read: nil,
                 rel_wrote: nil,
                 text: "This is the first",
                 title: "First",
                 user_read_post_uuid: nil,
                 wrote_post_uuid: nil,
                 uuid: "ae830851-9e93-46d5-bbf7-23ab99846497"
               }
             ] = TestRepo.all(query)
    end

    test "most complex join with simple return" do
      add_data()

      rel_data = %{when: ~D[2018-02-01]}
      empy_rel = %{}
      uuid = "zefzef-frzegz"

      query =
        from u in User,
          join: p in Post,
          on: p.rel_wrote == ^rel_data and p.rel_read == ^%{},
          join: c in Comment,
          on: c.rel_wrote == ^%{},
          where: u.uuid == ^"12903da6-5d46-417b-9cab-bd82766c868b"

      assert [
               %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               },
               %EctoNeo4j.Integration.User{
                 first_name: "John",
                 last_name: "Doe",
                 uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
               }
             ] = TestRepo.all(query)
    end

    test "most complex join with complex return" do
      add_data()

      rel_data = %{when: ~D[2018-01-01]}

      query =
        from u in User,
          join: p in Post,
          on:
            p.rel_wrote == ^rel_data and is_nil(p.rel_read) and p.rel_wrote == ^%{} and
              p.rel_read == ^%{},
          join: c in Comment,
          on: c.rel_wrote == ^%{},
          where: u.uuid == ^"12903da6-5d46-417b-9cab-bd82766c868b",
          select: [u.first_name, p.title, c.text]

      assert [] = TestRepo.all(query)
    end
  end

  describe "Update" do
    test "belongs to - update from child" do
      user_data = add_data()

      new_user =
        %User{
          uuid: "ec1741ba-28f2-47fc-8a96-a3c5e24c42da",
          first_name: "Jack",
          last_name: "Allops"
        }
        |> TestRepo.insert!()

      comment_uuid = List.first(user_data.wrote_comment).uuid

      comment =
        TestRepo.get(Comment, comment_uuid)
        |> Ecto.Adapters.Neo4j.preload([:has_comment, :wrote_comment])
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:wrote_comment, new_user)
        |> Ecto.Adapters.Neo4j.update(TestRepo)

      cql_check = """
      MATCH
        (new_user: User {uuid: {new_user_uuid}}),
        (comment:Comment {uuid: {comment_uuid}}),
        (new_user)-[:WROTE]->(comment)
      RETURN
        COUNT(comment) AS nb_comment
      """

      params = %{
        new_user_uuid: new_user.uuid,
        comment_uuid: comment_uuid
      }

      assert %Bolt.Sips.Response{results: [%{"nb_comment" => 1}]} =
               Ecto.Adapters.Neo4j.query!(cql_check, params)
    end

    test "belongs to - update from child (two relationships at the same time)" do
      user_data = add_data()

      new_user =
        %User{
          uuid: "ec1741ba-28f2-47fc-8a96-a3c5e24c42da",
          first_name: "Jack",
          last_name: "Allops"
        }
        |> TestRepo.insert!()

      post_uuid = List.last(user_data.wrote_post).uuid
      post = TestRepo.get(Post, post_uuid)

      comment_uuid = List.first(user_data.wrote_comment).uuid

      comment =
        TestRepo.get(Comment, comment_uuid)
        # |> Ecto.Adapters.Neo4j.preload(:has_comment)
        |> Ecto.Adapters.Neo4j.preload([:has_comment, :wrote_comment])
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:has_comment, post)
        |> Ecto.Changeset.put_assoc(:wrote_comment, new_user)
        |> Ecto.Adapters.Neo4j.update(TestRepo)

      cql_check = """
      MATCH
        (new_user: User {uuid: {new_user_uuid}}),
        (new_post:Post {uuid: {new_post_uuid}}),
        (comment:Comment {uuid: {comment_uuid}}),
        (new_user)-[:WROTE]->(comment),
        (new_post)-[:HAS]->(comment)
      RETURN
        COUNT(comment) AS nb_comment
      """

      params = %{
        new_user_uuid: new_user.uuid,
        new_post_uuid: post_uuid,
        comment_uuid: comment_uuid
      }

      assert %Bolt.Sips.Response{results: [%{"nb_comment" => 1}]} =
               Ecto.Adapters.Neo4j.query!(cql_check, params)
    end

    test "belongs to - update from child (remove relationship)" do
      user_data = add_data()

      new_user =
        %User{
          uuid: "ec1741ba-28f2-47fc-8a96-a3c5e24c42da",
          first_name: "Jack",
          last_name: "Allops"
        }
        |> TestRepo.insert!()

      comment_uuid = List.first(user_data.wrote_comment).uuid

      comment =
        TestRepo.get(Comment, comment_uuid)
        |> Ecto.Adapters.Neo4j.preload([:has_comment, :wrote_comment])
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:wrote_comment, nil)
        |> Ecto.Adapters.Neo4j.update(TestRepo)

      cql_check = """
      MATCH
        (user: User {uuid: {user_uuid}}),
        (comment:Comment {uuid: {comment_uuid}})
      WHERE
        NOT (user)-[:WROTE]->(comment)
      RETURN
        COUNT(comment) AS nb_comment
      """

      params = %{
        user_uuid: user_data.uuid,
        comment_uuid: comment_uuid
      }

      assert %Bolt.Sips.Response{results: [%{"nb_comment" => 1}]} =
               Ecto.Adapters.Neo4j.query!(cql_check, params)
    end

    test "has many - remove 2 relationships and add A" do
      user_data = add_data()

      user =
        TestRepo.get(User, user_data.uuid)
        |> TestRepo.preload([:wrote_post])

      post_data = %Post{
        uuid: "76633f38-cf5c-4987-8e59-ed2040f6b9c4",
        title: "Thrid",
        text: "This is a new  post",
        rel_read: %{},
        rel_wrote: %{}
      }

      new_post = TestRepo.insert!(post_data)

      assert {:ok,
              %EctoNeo4j.Integration.User{
                first_name: "changed!",
                last_name: "Doe",
                uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
                wrote_post: [
                  %EctoNeo4j.Integration.Post{
                    rel_read: %{},
                    rel_wrote: %{},
                    text: "This is a new  post",
                    title: "Thrid",
                    user_read_post_uuid: nil,
                    uuid: "76633f38-cf5c-4987-8e59-ed2040f6b9c4",
                    wrote_post_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
                  }
                ]
              }} =
               user
               |> TestRepo.preload([:wrote_post])
               |> Ecto.Changeset.change()
               |> Ecto.Changeset.put_change(:first_name, "changed!")
               |> Ecto.Changeset.put_assoc(:wrote_post, [new_post])
               |> Ecto.Adapters.Neo4j.update(TestRepo)

      cql_check = """
      MATCH
        (user: User {uuid: {user_uuid}}),
        (user)-[:WROTE]->(post:Post)
      RETURN
        COUNT(post) AS nb_post
      """

      params = %{user_uuid: user_data.uuid}

      assert %Bolt.Sips.Response{results: [%{"nb_post" => 1}]} =
               Ecto.Adapters.Neo4j.query!(cql_check, params)

      cql_nb_post = """
      MATCH
      (p:Post)
      RETURN
      COUNT(p) AS nb_post
      """

      assert %Bolt.Sips.Response{results: [%{"nb_post" => 3}]} =
               Ecto.Adapters.Neo4j.query!(cql_nb_post, params)
    end

    test "has many - remove one relationship" do
      user_data = add_data()

      user =
        TestRepo.get(User, user_data.uuid)
        |> TestRepo.preload([:wrote_post])

      assert {:ok,
              %EctoNeo4j.Integration.User{
                first_name: "John",
                last_name: "Doe",
                uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
                wrote_post: [
                  %EctoNeo4j.Integration.Post{
                    has_comment: [
                      %EctoNeo4j.Integration.Comment{
                        has_comment_uuid: nil,
                        rel_has: %{},
                        rel_wrote: %{when: ~D[2018-06-18]},
                        text: "This a comment from john Doe",
                        uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
                        wrote_comment_uuid: nil
                      },
                      %EctoNeo4j.Integration.Comment{
                        has_comment_uuid: nil,
                        rel_has: %{},
                        rel_wrote: %{when: ~D[2018-07-01]},
                        text: "THis is not the ebest post I've read...",
                        uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3",
                        wrote_comment_uuid: nil
                      }
                    ],
                    rel_read: nil,
                    rel_wrote: %{when: ~D[2018-01-01]},
                    text: "This is the first",
                    title: "First",
                    user_read_post_uuid: nil,
                    uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
                    wrote_post_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
                  }
                ]
              }} =
               user
               |> TestRepo.preload([:wrote_post])
               |> Ecto.Changeset.change()
               |> Ecto.Changeset.put_assoc(:wrote_post, [List.first(user_data.wrote_post)])
               |> Ecto.Adapters.Neo4j.update(TestRepo)

      cql_check = """
      MATCH
        (user: User {uuid: {user_uuid}}),
        (user)-[:WROTE]->(post:Post)
      RETURN
        COUNT(post) AS nb_post
      """

      params = %{user_uuid: user_data.uuid}

      assert %Bolt.Sips.Response{results: [%{"nb_post" => 1}]} =
               Ecto.Adapters.Neo4j.query!(cql_check, params)
    end

    test "mixed update: belongs_to and has_many" do
      user_data = add_data()

      new_user =
        %User{
          uuid: "ec1741ba-28f2-47fc-8a96-a3c5e24c42da",
          first_name: "Jack",
          last_name: "Allops"
        }
        |> TestRepo.insert!()

      post_uuid = List.first(user_data.wrote_post).uuid

      assert {:ok,
              %EctoNeo4j.Integration.Post{
                has_comment: [],
                rel_read: nil,
                rel_wrote: %{"when" => ~D[2018-01-01]},
                text: "This is the first",
                title: "First",
                user_read_post_uuid: nil,
                uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
                wrote_post: %EctoNeo4j.Integration.User{
                  first_name: "Jack",
                  last_name: "Allops",
                  uuid: "ec1741ba-28f2-47fc-8a96-a3c5e24c42da"
                },
                wrote_post_uuid: "ec1741ba-28f2-47fc-8a96-a3c5e24c42da"
              }} =
               TestRepo.get!(Post, post_uuid)
               |> Ecto.Adapters.Neo4j.preload([:wrote_post, :has_comment])
               |> Ecto.Changeset.change()
               |> Ecto.Changeset.put_assoc(:wrote_post, new_user)
               |> Ecto.Changeset.put_assoc(:has_comment, [])
               |> Ecto.Adapters.Neo4j.update(TestRepo)

      cql_check = """
      MATCH
        (user: User {uuid: {user_uuid}}),
        (user)-[:WROTE]->(post:Post {uuid: {post_uuid}})
      OPTIONAL MATCH
        (post)-[:HAS]->(comment:Comment)
      RETURN
        COUNT(comment) AS nb_comment
      """

      params = %{user_uuid: new_user.uuid, post_uuid: post_uuid}

      assert %Bolt.Sips.Response{results: [%{"nb_comment" => 0}]} =
               Ecto.Adapters.Neo4j.query!(cql_check, params)
    end

    # test "update relationship data" do
    #   user_data = add_data()

    #   post_uuid = List.first(user_data.wrote_post).uuid

    #   TestRepo.get!(Post, post_uuid)
    #   |> Ecto.Adapters.Neo4j.preload([:wrote_post])
    #   |> Ecto.Changeset.change()
    #   |> Ecto.Changeset.put_change(:rel_wrote, %{when: ~D[2020-03-04]})
    #   |> Ecto.Adapters.Neo4j.update(TestRepo)
    #   |> IO.inspect()
    # end
  end

  defp fixtures() do
    comment1_data = %Comment{
      uuid: "2be39329-d9b5-4b85-a07f-ee9a2997a8ef",
      text: "This a comment from john Doe",
      rel_wrote: %{when: ~D[2018-06-18]},
      rel_has: %{}
    }

    comment2_data = %Comment{
      uuid: "e923428a-6819-47ab-bfef-ca4a2e9b75c3",
      text: "THis is not the ebest post I've read...",
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
      first_name: "John",
      last_name: "Doe",
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

    {user, post1_data, post2_data, comment1_data, comment2_data}
  end

  defp add_data() do
    {user, _, _, _, _} = fixtures()

    assert {:ok, _} = Ecto.Adapters.Neo4j.insert(TestRepo, user)
    user
  end
end
