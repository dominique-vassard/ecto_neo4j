defmodule EctoNeo4j.Cql.RelationshipTest do
  use ExUnit.Case, async: false
  @moduletag :supported

  alias Ecto.Adapters.Neo4j.Cql.Relationship, as: RelationshipCql

  test "get_related/3" do
    cql = """
    MATCH
      (n0:User)-[rel]->(n:Post)
    WHERE
      n0.uuid = {uuid}
    RETURN
      COLLECT(rel) AS relationships, n
    """

    assert cql == RelationshipCql.get_related("User", "Post", "n0.uuid = {uuid}")
  end
end
