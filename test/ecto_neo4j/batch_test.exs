defmodule Ecto.Adapters.Neo4j.BatchTest do
  use ExUnit.Case, async: false
  @moduletag :supported

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  setup do
    Bolt.Sips.query!(Bolt.Sips.conn(), "MATCH (n) DETACH DELETE n")

    data =
      1..500
      |> Enum.map(fn x ->
        "CREATE (:posts{title: 'title_#{inspect(x)}'})"
      end)
      |> Enum.join("\n")

    Ecto.Adapters.Neo4j.query!(data)
    :ok
  end

  test "batch update classic" do
    cql = """
    MATCH
      (n:posts)
    WHERE
      NOT exists(n.touched)
    WITH
      n AS n
    LIMIT
      {limit}
    SET
      n.touched = true
    RETURN
      COUNT(n) AS nb_touched_nodes
    """

    assert {:ok, []} = Ecto.Adapters.Neo4j.Behaviour.Queryable.batch_query(cql)

    cql = """
    MATCH
      (n:posts)
    WHERE
      n.title CONTAINS "title"
    RETURN COUNT(n) AS nb_updated
    """

    assert %Bolt.Sips.Response{results: [%{"nb_updated" => 500}]} =
             Ecto.Adapters.Neo4j.query!(cql)
  end

  test "batch update with skip" do
    cql = """
    MATCH
      (n:posts)
    WITH
      n AS n
      ORDER By n.title
    SKIP
      {skip}
    LIMIT
      {limit}
    SET
      n.touched = true
    RETURN
      COUNT(n) AS nb_touched_nodes
    """

    assert {:ok, []} = Ecto.Adapters.Neo4j.Behaviour.Queryable.batch_query(cql, %{}, :with_skip)

    cql = """
    MATCH
      (n:posts)
    WHERE
      n.title CONTAINS "title"
    RETURN COUNT(n) AS nb_updated
    """

    assert %Bolt.Sips.Response{results: [%{"nb_updated" => 500}]} =
             Ecto.Adapters.Neo4j.query!(cql)
  end

  test "batch update with skip with specific chunksize" do
    cql = """
    MATCH
      (n:posts)
    WITH
      n AS n
      ORDER By n.title
    SKIP
      {skip}
    LIMIT
      {limit}
    SET
      n.touched = true
    RETURN
      COUNT(n) AS nb_touched_nodes
    """

    assert {:ok, []} =
             Ecto.Adapters.Neo4j.Behaviour.Queryable.batch_query(cql, %{}, :with_skip,
               chunk_size: 100
             )

    cql = """
    MATCH
      (n:posts)
    WHERE
      n.title CONTAINS "title"
    RETURN COUNT(n) AS nb_updated
    """

    assert %Bolt.Sips.Response{results: [%{"nb_updated" => 500}]} =
             Ecto.Adapters.Neo4j.query!(cql)
  end

  test "query! raises" do
    cql = """
    MATCH (n:Test)
    """

    assert_raise Bolt.Sips.Exception, fn ->
      Ecto.Adapters.Neo4j.Behaviour.Queryable.batch_query!(cql)
    end
  end

  test "insert, update and delete" do
    TestRepo.update_all(Post, [set: [title: "New title"]], batch: true)

    cql = """
    MATCH
      (n:posts)
    WHERE
      n.title = "New title"
    RETURN COUNT(n) AS nb_updated
    """

    assert %Bolt.Sips.Response{results: [%{"nb_updated" => 500}]} =
             Ecto.Adapters.Neo4j.query!(cql)

    TestRepo.delete_all(Post, batch: true)
    assert %Bolt.Sips.Response{results: [%{"nb_updated" => 0}]} = Ecto.Adapters.Neo4j.query!(cql)
  end
end
