defmodule EctoNeo4j.BatchTest do
  use ExUnit.Case, async: false

  setup do
    Bolt.Sips.query!(Bolt.Sips.conn(), "MATCH (n) DETACH DELETE n")

    data =
      1..500
      |> Enum.map(fn x ->
        "CREATE (:posts{title: 'title_#{inspect(x)}'})"
        # [title: "title_#{inspect(x)}"]
      end)
      |> Enum.join("\n")

    # TestRepo.insert_all(Post, data)

    EctoNeo4j.Adapter.query!(data)
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

    assert {:ok, []} = EctoNeo4j.Behaviour.Queryable.batch_query(cql)

    cql = """
    MATCH
      (n:posts)
    WHERE
      n.title CONTAINS "title"
    RETURN COUNT(n) AS nb_updated
    """

    assert %Bolt.Sips.Response{results: [%{"nb_updated" => 500}]} = EctoNeo4j.Adapter.query!(cql)
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

    assert {:ok, []} = EctoNeo4j.Behaviour.Queryable.batch_query(cql, %{}, :with_skip)

    cql = """
    MATCH
      (n:posts)
    WHERE
      n.title CONTAINS "title"
    RETURN COUNT(n) AS nb_updated
    """

    assert %Bolt.Sips.Response{results: [%{"nb_updated" => 500}]} = EctoNeo4j.Adapter.query!(cql)
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
             EctoNeo4j.Behaviour.Queryable.batch_query(cql, %{}, :with_skip, chunk_size: 100)

    cql = """
    MATCH
      (n:posts)
    WHERE
      n.title CONTAINS "title"
    RETURN COUNT(n) AS nb_updated
    """

    assert %Bolt.Sips.Response{results: [%{"nb_updated" => 500}]} = EctoNeo4j.Adapter.query!(cql)
  end

  test "query! raises" do
    cql = """
    MATCH (n:Test)
    """

    assert_raise Bolt.Sips.Exception, fn ->
      EctoNeo4j.Behaviour.Queryable.batch_query!(cql)
    end
  end
end
