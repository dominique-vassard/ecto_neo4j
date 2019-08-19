defmodule EctoNeo4j.Cql.Node do
  @doc """
  Returns Cypher query to get one node given its uuid

  ### Parameters

    - node_label: The node label to search on

  ### Example

      iex> EctoNeo4j.Cql.Node.get_by_uuid("Post")
      "MATCH\\n  (n:Post)\\nWHERE\\n  n.uuid = {uuid}\\nRETURN\\n  n\\n"
  """
  @spec get_by_uuid(String.t()) :: String.t()
  def get_by_uuid(node_label) do
    """
    MATCH
      (n:#{node_label})
    WHERE
      n.uuid = {uuid}
    RETURN
      n
    """
  end

  @doc """
  Returns cypher query and params to insert a new node.

  ## Example

      iex> data = %{title: "New title", uuid: "a-valid-uuid"}
      iex> EctoNeo4j.Cql.Node.insert("Post", data)
      {"MERGE
        (n:Post {uuid: {uuid}})
      ON CREATE
      SET
        n.title = {title}, \\nn.uuid = {uuid}
      RETURN
        n
      ", %{title: "New title", uuid: "a-valid-uuid"}}
  """
  @spec insert(String.t(), map()) :: {String.t(), map()}
  def insert(node_label, data) do
    cql_set =
      data
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(", \n")

    cql_id =
      case Map.has_key?(data, :uuid) do
        true -> "uuid: {uuid}"
        _ -> "nodeId: {node_id}"
      end

    cql = """
    MERGE
      (n:#{node_label} {#{cql_id}})
    ON CREATE
    SET
      #{cql_set}
    RETURN
      n
    """

    {cql, data}
  end

  @doc """
  Returns cypher query to update node data.

  ## Example

      iex> data = %{title: "New title"}
      iex> filters = %{id: 5}
      iex> EctoNeo4j.Cql.Node.update("Post", data, filters)
      {"MATCH
        (n:Post)
      WHERE
        n.id = {id}
      SET
        n.title = {title}
      RETURN
        n
      ", %{id: 5, title: "New title"}}
  """
  @spec update(String.t(), map(), map()) :: {String.t(), map()}
  def update(node_label, data, filters) do
    set =
      data
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(", \n")

    where =
      filters
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(" AND ")

    cql = """
    MATCH
      (n:#{node_label})
    WHERE
      #{where}
    SET
      #{set}
    RETURN
      n
    """

    params = Map.merge(data, filters)

    {cql, params}
  end

  @doc """
  Returns cypher query to delete a node.

  ## Example

      iex> EctoNeo4j.Cql.Node.delete("Post", %{uuid: "a-valid-uuid"})
      {"MATCH
        (n:Post)
      WHERE
        n.uuid = {uuid}
      DETACH DELETE
        n
      RETURN
        n
      ", %{uuid: "a-valid-uuid"}}
  """
  @spec delete(String.t(), map()) :: {String.t(), map()}
  def delete(node_label, filters) do
    where =
      filters
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(" AND ")

    cql = """
    MATCH
      (n:#{node_label})
    WHERE
      #{where}
    DETACH DELETE
      n
    RETURN
      n
    """

    {cql, filters}
  end

  @doc """
  Builds a cypher query for given `node_label`, `where`, `return` parts.

  ## Example

      # with default `where` and `return`
      iex> EctoNeo4j.Cql.Node.build_query(:match, "Post")
      "MATCH
        (n:Post)\\n\\n
      RETURN
        n\\n
      "

      # with everything defined
      iex> node_label = "Post"
      iex> where = "title = {title}"
      iex> return = "n"
      iex> EctoNeo4j.Cql.Node.build_query(:match, node_label, where, return)
      "MATCH
        (n:Post)
      WHERE
        title = {title}\\n\\n
      RETURN
        n\\n
      "

      # for deleting
      iex> EctoNeo4j.Cql.Node.build_query(:delete, "Post")
      "MATCH
        (n:Post)\\n
      DETACH DELETE
        n\\n
      RETURN
        n\\n
      "
  """
  @spec build_query(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def build_query(query_type, node_label, where \\ "", return \\ "n", order_by \\ "") do
    cql_where =
      if String.length(where) > 0 do
        """
        WHERE
          #{where}
        """
      end

    cql_order_by =
      if String.length(order_by) > 0 do
        """
        ORDER BY
          #{order_by}
        """
      end

    cql_delete =
      if query_type == :delete do
        """
        DETACH DELETE
          n
        """
      end

    """
    MATCH
      (n:#{node_label})
    #{cql_where}
    #{cql_delete}
    RETURN
      #{return}
    #{cql_order_by}
    """
  end
end
