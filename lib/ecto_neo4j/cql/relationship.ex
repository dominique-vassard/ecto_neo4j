defmodule Ecto.Adapters.Neo4j.Cql.Relationship do
  @moduledoc """
  Cypher query builder for Node
  """

  @doc """
  Get cql to retrieve relationships between the two speccified nodes.

  ### Example

      iex> where = "n0.uuid = {uuid}"
      iex> Ecto.Adapters.Neo4j.Cql.Relationhip.get_related("User", "Post", where)
      "MATCH
        (n0:User)-[rel]->(n:Post)
      WHERE
        n0.uuid = {uuid}
      RETURN
        COLLECT(rel) AS relationships, n
    "
  """
  @spec get_related(String.t(), String.t(), String.t()) :: String.t()
  def get_related(start_node_label, end_node_label, where) do
    """
    MATCH
      (n0:#{start_node_label})-[rel]->(n:#{end_node_label})
    WHERE
      #{where}
    RETURN
      COLLECT(rel) AS relationships, n
    """
  end
end
